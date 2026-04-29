# Flash Sale Engine — Architecture Deep Dive

This document explains the **why** behind every design decision. It's structured as a walkthrough — each section covers one architectural concern, the problem it solves, and how this codebase implements it.

---

## 1. The Problem

A flash sale generates **massive, instantaneous traffic spikes**. Thousands of users hit "Buy" at the exact same second. The system must:

- **Not crash** — even when the database falls over under load
- **Not leak information** — response times shouldn't reveal internal routing
- **Not lose orders** — fallback must be seamless and invisible to the client
- **Scale horizontally** — adding more instances should be trivial

This engine solves all four.

---

## 2. System Topology

```
  Users ──► Nginx (port 80) ──► 3× Spring Boot (port 8080) ──► PostgreSQL (port 5432)
                │                        │
           Load Balance           Circuit Breaker
           (least_conn)          (Resilience4j)
                                        │
                                 ┌──────┴──────┐
                                 │             │
                            DB (Real)    Cache (Fallback)
```

**5 containers**, one `docker-compose up`:

| Container | Purpose | Why it exists |
|-----------|---------|--------------|
| `flashsale-db` | PostgreSQL 16 | Real inventory, user accounts, order logs |
| `flashsale-app-1/2/3` | Spring Boot instances | Horizontal scaling, fault isolation |
| `flashsale-lb` | Nginx reverse proxy | Single entry point, load distribution |

---

## 3. Request Lifecycle

Here's what happens when a user sends `POST /api/flash-sale/order`:

```
1. Nginx receives the request on port 80
2. Nginx selects the least-loaded app instance (least_conn)
3. JwtAuthFilter extracts + validates the JWT (NO database call)
4. SecurityConfig checks RBAC (CUSTOMER or ADMIN role required)
5. FlashSaleController delegates to FlashSaleService
6. FlashSaleService starts a timer
7. CircuitBreaker wraps the call to InternalWorkflowService
   ├── Circuit CLOSED → InternalWorkflow queries PostgreSQL
   └── Circuit OPEN   → ExternalWorkflow uses in-memory cache
8. FlashSaleService pads response to exactly 200ms
9. LoggingFrameWork dispatches to active logging strategy (file or DB)
10. Response returned with workflow metadata
```

---

## 4. Design Pattern: Circuit Breaker

### The Problem
When PostgreSQL goes down, naive implementations either:
- **Hang** — waiting 30s for connection timeout on every request
- **Crash** — unhandled exceptions bubble up as 500s
- **Cascade** — connection pool exhaustion takes down the app

### The Solution
Resilience4j's circuit breaker wraps all DB calls in `FlashSaleService.processOrder()`:

```java
CircuitBreaker cb = circuitBreakerRegistry.circuitBreaker("dbCircuitBreaker");
try {
    response = cb.executeSupplier(() -> internalWorkflowService.process(request));
} catch (Exception e) {
    // Circuit is OPEN or DB failed → fallback
    response = externalWorkflowService.process(request);
}
```

### State Machine

```
  CLOSED ──(failures exceed threshold)──► OPEN ──(wait 10s)──► HALF_OPEN
    ▲                                                              │
    └──────────(test calls succeed)────────────────────────────────┘
```

| State | Behavior |
|-------|----------|
| **CLOSED** | Normal operation. All requests hit PostgreSQL. Failures are counted. |
| **OPEN** | DB is assumed down. All requests go directly to the fallback cache. Fast-fail, no wasted connections. |
| **HALF_OPEN** | Recovery probe. A few test requests are sent to DB. If they succeed, circuit closes. If they fail, circuit re-opens. |

### Configuration Rationale

```properties
sliding-window-size=3              # Small window — trip fast in a 3-instance cluster
minimum-number-of-calls=2          # Don't need many samples to detect outage
failure-rate-threshold=50           # Half the calls failing = something is wrong
wait-duration-in-open-state=10s     # 10s before probing recovery
```

**Why these values?** With 3 load-balanced instances, each instance only sees ~1/3 of all requests. A large window (e.g., 10) would mean the circuit never trips because no single instance accumulates enough failures. The small window ensures fast detection.

### Why the Auth Filter is Stateless

This is a critical design decision. The JWT auth filter reads the user's **role directly from the JWT claims** — it never queries the database:

```java
String username = jwtService.extractUsername(jwt);
String role = jwtService.extractRole(jwt);  // From JWT claims, NOT from DB
```

**Why this matters:** If the auth filter hit the DB, then when PostgreSQL goes down:
1. Auth filter tries `userRepository.findByUsername()` → **fails**
2. Request gets a 403 Forbidden **before reaching the circuit breaker**
3. Circuit breaker never sees any failures → **never opens**
4. System appears healthy but returns 403 on every request

By keeping auth stateless, requests pass through the filter and reach the circuit breaker, which correctly detects the DB outage and routes to the fallback.

---

## 5. Design Pattern: Strategy

### The Problem
The system needs two logging sinks (File and Database), and an admin should be able to switch between them at runtime without redeploying.

### The Solution
Classic **GoF Strategy Pattern**:

```
┌─────────────────────┐
│  LoggingFrameWork   │  ← Context (holds active strategy)
│  (Strategy Context) │
└────────┬────────────┘
         │ delegates to
         ▼
┌─────────────────────┐
│  LoggingStrategy    │  ← Interface
│  + writeLog()       │
└────┬──────────┬─────┘
     │          │
     ▼          ▼
┌──────────┐ ┌──────────────┐
│  File    │ │  Database    │
│ Strategy │ │  Strategy    │
└──────────┘ └──────────────┘
```

**Runtime switching:**
```bash
# Admin switches to database logging (no restart needed)
POST /api/flash-sale/config/logging?type=database

# Switch back
POST /api/flash-sale/config/logging?type=file
```

The `LoggingFrameWork` context class holds a reference to the active `LoggingStrategy`. The admin endpoint swaps the reference. All subsequent orders use the new strategy.

---

## 6. Timing Normalization (Anti-Timing-Attack)

### The Problem
The internal workflow (DB query + stock update) takes ~5-20ms. The external workflow (in-memory HashMap lookup) takes <1ms. An attacker could measure response times to determine:
- Which workflow was used (information leakage)
- Whether the DB is down (infrastructure probing)

### The Solution
Every response is padded to exactly **200ms**:

```java
long elapsed = System.currentTimeMillis() - startTime;
if (elapsed < targetExecutionTimeMs) {
    Thread.sleep(targetExecutionTimeMs - elapsed);
}
```

From the client's perspective, every request takes 200ms — whether it hit PostgreSQL or the in-memory cache. The `executionTimeMs` field in the response always reads `200`.

---

## 7. Load Balancing

### Strategy: `least_conn`

```nginx
upstream flashsale_backend {
    least_conn;
    server app-1:8080;
    server app-2:8080;
    server app-3:8080;
}
```

**Why `least_conn` over round-robin?** During a flash sale, some requests take longer (DB writes, circuit breaker timeouts). Round-robin would send new requests to instances still processing slow ones. `least_conn` routes to the instance with the fewest active connections — natural backpressure.

### Stateless Scaling
Because JWT tokens carry all authentication state, any instance can handle any request. There are no sticky sessions, no shared state between instances (except the shared PostgreSQL). Adding a 4th instance is a one-line change in `docker-compose.yml` and `nginx.conf`.

---

## 8. Security Model

### RBAC (Role-Based Access Control)

| Role | Can Do | Cannot Do |
|------|--------|-----------|
| `CUSTOMER` | Place orders | Switch logging config |
| `ADMIN` | Place orders + Switch logging config | — |
| Anonymous | Health check, register, login | Everything else (403) |

### JWT Structure
```json
{
  "sub": "john",           // username
  "role": "CUSTOMER",      // embedded in claims
  "iat": 1714400000,       // issued at
  "exp": 1714400900        // expires (15 min)
}
```

The token is signed with HMAC-SHA384. The secret is configured via environment variable (`FLASHSALE_JWT_SECRET`), so each deployment can have its own key.

---

## 9. Database Design

### Products Table (pre-seeded with 10 items)
```sql
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    original_price DECIMAL(10,2),
    sale_price DECIMAL(10,2),
    stock_quantity INT
);
```

### External Order Log (fallback logging)
```sql
CREATE TABLE external_order_log (
    id SERIAL PRIMARY KEY,
    product_name VARCHAR(100),
    requested_quantity INT,
    unit_price DECIMAL(10,2),
    total_price DECIMAL(10,2),
    status VARCHAR(20),
    workflow VARCHAR(20),
    logged_at TIMESTAMP DEFAULT NOW()
);
```

Stock updates use `@Transactional` in `InternalWorkflowService` — read + validate + decrement happens atomically.

---

## 10. What the Automated Tests Prove

The `test-all.sh` / `test-all.ps1` scripts run **28 tests across 7 phases**. Here's what each phase demonstrates:

### Phase 0: Infrastructure
> "Can I stand up the entire system with one command?"
- All 5 containers start and become healthy

### Phase 1: Health Checks
> "Are all endpoints reachable through the load balancer?"
- App health, Actuator, Circuit Breaker status, Nginx health

### Phase 2: Authentication
> "Does JWT auth work correctly?"
- Register → token returned with correct role
- Duplicate registration → 409 Conflict
- Login → fresh token
- Wrong password → 401 Unauthorized

### Phase 3: RBAC
> "Are role boundaries enforced?"
- No token → 403 Forbidden
- Customer token → 200 OK (order)
- Customer token → 403 (admin endpoint)
- Admin token → 200 OK (admin endpoint)

### Phase 4: Order Processing
> "Does the core business logic work?"
- Successful order → correct product name, price, stock deduction
- Insufficient stock → clean rejection with remaining stock count
- Timing normalization → response time ≈ 200ms

### Phase 5: Strategy Pattern
> "Can logging be switched at runtime?"
- Switch to database → confirmed
- Order → logs correctly
- Switch back to file → confirmed

### Phase 6: Load Balancing
> "Does Nginx distribute traffic across all instances?"
- 9 orders sent → all 3 instances received requests

### Phase 7: Circuit Breaker
> "Does the system survive a database crash?"
- Initial state → CLOSED
- Stop PostgreSQL → confirmed down
- Send 5 orders → circuit opens on instances that received failures
- Query each instance directly → at least one shows OPEN
- Restart PostgreSQL → circuit recovers to CLOSED
- Send order → back to INTERNAL workflow

---

## 11. File Map

| File | Responsibility |
|------|---------------|
| `FlashSaleService.java` | **Orchestrator** — circuit breaker + timing + logging dispatch |
| `InternalWorkflowService.java` | Primary path — PostgreSQL queries + stock management |
| `ExternalWorkflowService.java` | Fallback path — ConcurrentHashMap cache |
| `JwtAuthFilter.java` | Stateless auth filter (reads role from JWT, not DB) |
| `JwtService.java` | Token generation, validation, claim extraction |
| `SecurityConfig.java` | Endpoint security rules (public vs. authenticated vs. admin) |
| `LoggingFrameWork.java` | Strategy context — holds active logging strategy |
| `LoggingStrategy.java` | Strategy interface — `writeLog(response)` |
| `FileLoggingStrategy.java` | Appends NDJSON to `output/internal-orders/` |
| `DatabaseLoggingStrategy.java` | Inserts into `external_order_log` table |
| `docker-compose.yml` | Full 5-container topology |
| `nginx.conf` | `least_conn` upstream + proxy config |
| `01-seed.sql` | Product data + schema for external order log |
| `application.properties` | All tunables (JWT, CB, timing, DB) |

---

## 12. What I'd Add Next (Production Roadmap)

| Priority | Enhancement | Why |
|----------|-------------|-----|
| P0 | **Redis** for distributed fallback cache | Current in-memory cache is per-instance; Redis shares state |
| P0 | **Flyway** for schema migrations | `ddl-auto=update` is fine for dev, not for production |
| P1 | **Prometheus + Grafana** | Circuit breaker metrics are already exposed via Actuator — just needs scraping |
| P1 | **Refresh token rotation** | Current 15-min expiry means users re-login frequently |
| P2 | **Rate limiting** | Nginx `limit_req` to prevent bot abuse during flash sales |
| P2 | **Distributed tracing** (Zipkin/Jaeger) | Trace requests across Nginx → App → DB |
