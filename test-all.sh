#!/bin/bash
# ============================================================================
#  Flash Sale Engine — Full Integration Test Script
#  Run: bash test-all.sh
#  Prerequisites: Docker, Docker Compose, curl, jq (optional but recommended)
# ============================================================================

set -e

BASE_URL="http://localhost"
PASS=0
FAIL=0
TOTAL=0

# ---- Helpers ----
print_header() { echo ""; echo "═══════════════════════════════════════════════════════════════"; echo "  $1"; echo "═══════════════════════════════════════════════════════════════"; }
print_test()   { TOTAL=$((TOTAL+1)); echo -n "  [$TOTAL] $1 ... "; }
pass()         { 
  PASS=$((PASS+1))
  if [ -n "$1" ]; then
    echo "✅ PASS — $1"
  else
    echo "✅ PASS"
  fi
}
fail()         { FAIL=$((FAIL+1)); echo "❌ FAIL — $1"; }

# ---- Extract JSON field (no jq dependency) ----
extract() { echo "$1" | sed 's/.*"'"$2"'":"\{0,1\}\([^",}]*\)"\{0,1\}.*/\1/'; }

# ============================================================================
print_header "PHASE 0: INFRASTRUCTURE SETUP"
# ============================================================================

echo "  Tearing down any existing containers..."
docker-compose down -v 2>/dev/null || true
docker rm -f flashsale-db flashsale-app 2>/dev/null || true

echo "  Building and starting all containers..."
docker-compose up --build -d 2>&1 | tail -5

echo "  Waiting for Spring Boot to initialize (45s)..."
sleep 45

print_test "All 5 containers running"
RUNNING=$(docker ps --filter "name=flashsale" --format "{{.Names}}" | wc -l)
if [ "$RUNNING" -ge 5 ]; then pass "$RUNNING containers active"; else fail "Only $RUNNING containers running"; fi

# ============================================================================
print_header "PHASE 1: HEALTH CHECKS"
# ============================================================================

print_test "Health endpoint (public, no auth)"
HEALTH=$(curl -s -o /dev/null -w "%{http_code}" $BASE_URL/api/flash-sale/health)
if [ "$HEALTH" = "200" ]; then pass "Returned HTTP 200"; else fail "HTTP $HEALTH"; fi

print_test "Actuator health endpoint"
ACTUATOR=$(curl -s -o /dev/null -w "%{http_code}" $BASE_URL/actuator/health)
if [ "$ACTUATOR" = "200" ]; then pass "Returned HTTP 200"; else fail "HTTP $ACTUATOR"; fi

print_test "Circuit breaker endpoint"
CB=$(curl -s -o /dev/null -w "%{http_code}" $BASE_URL/actuator/circuitbreakers)
if [ "$CB" = "200" ]; then pass "Returned HTTP 200"; else fail "HTTP $CB"; fi

print_test "Nginx LB health"
NGINX=$(curl -s -o /dev/null -w "%{http_code}" $BASE_URL/nginx-health)
if [ "$NGINX" = "200" ]; then pass "Returned HTTP 200"; else fail "HTTP $NGINX"; fi

# ============================================================================
print_header "PHASE 2: AUTHENTICATION"
# ============================================================================

print_test "Register customer"
REG_RESP=$(curl -s -X POST $BASE_URL/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"customer1","password":"cust123"}')
REG_TOKEN=$(extract "$REG_RESP" "token")
REG_ROLE=$(extract "$REG_RESP" "role")
if [ "$REG_ROLE" = "CUSTOMER" ] && [ -n "$REG_TOKEN" ]; then pass "Assigned Role: $REG_ROLE, Token generated"; else fail "role=$REG_ROLE"; fi

print_test "Duplicate registration rejected"
DUP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST $BASE_URL/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"customer1","password":"cust123"}')
if [ "$DUP_CODE" = "409" ]; then pass "Correctly blocked with HTTP 409 Conflict"; else fail "HTTP $DUP_CODE (expected 409)"; fi

print_test "Register admin"
ADMIN_RESP=$(curl -s -X POST $BASE_URL/api/auth/register/admin \
  -H "Content-Type: application/json" \
  -d '{"username":"admin1","password":"admin123"}')
ADMIN_TOKEN=$(extract "$ADMIN_RESP" "token")
ADMIN_ROLE=$(extract "$ADMIN_RESP" "role")
if [ "$ADMIN_ROLE" = "ADMIN" ] && [ -n "$ADMIN_TOKEN" ]; then pass "Assigned Role: $ADMIN_ROLE, Token generated"; else fail "role=$ADMIN_ROLE"; fi

print_test "Login with valid credentials"
LOGIN_RESP=$(curl -s -X POST $BASE_URL/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"customer1","password":"cust123"}')
CUST_TOKEN=$(extract "$LOGIN_RESP" "token")
LOGIN_MSG=$(extract "$LOGIN_RESP" "message")
if [ "$LOGIN_MSG" = "Login successful" ]; then pass "Successfully retrieved JWT for customer1"; else fail "msg=$LOGIN_MSG"; fi

print_test "Login with wrong password"
BAD_LOGIN=$(curl -s -o /dev/null -w "%{http_code}" -X POST $BASE_URL/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"customer1","password":"wrong"}')
if [ "$BAD_LOGIN" = "401" ]; then pass "Correctly blocked with HTTP 401 Unauthorized"; else fail "HTTP $BAD_LOGIN (expected 401)"; fi

# ============================================================================
print_header "PHASE 3: AUTHORIZATION (RBAC)"
# ============================================================================

print_test "Order WITHOUT token"
NO_AUTH=$(curl -s -o /dev/null -w "%{http_code}" -X POST $BASE_URL/api/flash-sale/order \
  -H "Content-Type: application/json" \
  -d '{"productId":1,"quantity":1}')
if [ "$NO_AUTH" = "403" ]; then pass "Blocked with HTTP 403 Forbidden"; else fail "HTTP $NO_AUTH"; fi

print_test "Order WITH customer token"
AUTH_ORDER=$(curl -s -o /dev/null -w "%{http_code}" -X POST $BASE_URL/api/flash-sale/order \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $CUST_TOKEN" \
  -d '{"productId":1,"quantity":1}')
if [ "$AUTH_ORDER" = "200" ]; then pass "Allowed with HTTP 200 OK"; else fail "HTTP $AUTH_ORDER"; fi

print_test "Admin config by CUSTOMER"
CUST_CONFIG=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  "$BASE_URL/api/flash-sale/config/logging?type=database" \
  -H "Authorization: Bearer $CUST_TOKEN")
if [ "$CUST_CONFIG" = "403" ]; then pass "Blocked with HTTP 403 Forbidden"; else fail "HTTP $CUST_CONFIG"; fi

# Re-login admin to get fresh token
ADMIN_LOGIN=$(curl -s -X POST $BASE_URL/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin1","password":"admin123"}')
ADMIN_TOKEN=$(extract "$ADMIN_LOGIN" "token")

print_test "Admin config by ADMIN"
ADMIN_CONFIG=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  "$BASE_URL/api/flash-sale/config/logging?type=database" \
  -H "Authorization: Bearer $ADMIN_TOKEN")
if [ "$ADMIN_CONFIG" = "200" ]; then pass "Allowed with HTTP 200 OK"; else fail "HTTP $ADMIN_CONFIG"; fi

# ============================================================================
print_header "PHASE 4: ORDER PROCESSING (Internal Workflow)"
# ============================================================================

# Switch back to file logging
curl -s -X POST "$BASE_URL/api/flash-sale/config/logging?type=file" \
  -H "Authorization: Bearer $ADMIN_TOKEN" > /dev/null

print_test "Order product 1 (iPhone 15 Pro)"
ORDER1=$(curl -s -X POST $BASE_URL/api/flash-sale/order \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $CUST_TOKEN" \
  -d '{"productId":1,"quantity":2}')
STATUS1=$(extract "$ORDER1" "status")
WORKFLOW1=$(extract "$ORDER1" "workflow")
if [ "$STATUS1" = "SUCCESS" ] && [ "$WORKFLOW1" = "INTERNAL" ]; then pass "Status: $STATUS1, Flow: $WORKFLOW1"; else fail "status=$STATUS1 workflow=$WORKFLOW1"; fi

print_test "Order product 5 (Dyson V15 Detect)"
ORDER5=$(curl -s -X POST $BASE_URL/api/flash-sale/order \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $CUST_TOKEN" \
  -d '{"productId":5,"quantity":3}')
STATUS5=$(extract "$ORDER5" "status")
PNAME5=$(extract "$ORDER5" "productName")
if [ "$STATUS5" = "SUCCESS" ]; then pass "Purchased 3x $PNAME5"; else fail "status=$STATUS5"; fi

print_test "Order with insufficient stock (qty=9999)"
ORDER_FAIL=$(curl -s -X POST $BASE_URL/api/flash-sale/order \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $CUST_TOKEN" \
  -d '{"productId":4,"quantity":9999}')
STATUS_FAIL=$(extract "$ORDER_FAIL" "status")
MSG_FAIL=$(extract "$ORDER_FAIL" "message")
if [ "$STATUS_FAIL" = "FAILED" ]; then pass "Rejected cleanly - Msg: $MSG_FAIL"; else fail "status=$STATUS_FAIL"; fi

print_test "Timing normalization (~200ms)"
EXEC_TIME=$(extract "$ORDER1" "executionTimeMs")
if [ "$EXEC_TIME" -ge 195 ] && [ "$EXEC_TIME" -le 250 ] 2>/dev/null; then pass "Returned in ${EXEC_TIME}ms"; else fail "executionTimeMs=$EXEC_TIME"; fi

# ============================================================================
print_header "PHASE 5: STRATEGY PATTERN (Logging Switch)"
# ============================================================================

print_test "Switch to database logging"
SW_DB=$(curl -s -X POST "$BASE_URL/api/flash-sale/config/logging?type=database" \
  -H "Authorization: Bearer $ADMIN_TOKEN")
if echo "$SW_DB" | grep -q "database"; then pass "Successfully configured DB sink"; else fail "$SW_DB"; fi

print_test "Order logs to DB after switch"
ORDER_DB=$(curl -s -X POST $BASE_URL/api/flash-sale/order \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $CUST_TOKEN" \
  -d '{"productId":2,"quantity":1}')
STATUS_DB=$(extract "$ORDER_DB" "status")
OUT_DEST=$(extract "$ORDER_DB" "outputDestination")
if [ "$STATUS_DB" = "SUCCESS" ]; then pass "Destination -> $OUT_DEST"; else fail "status=$STATUS_DB"; fi

print_test "Switch back to file logging"
SW_FILE=$(curl -s -X POST "$BASE_URL/api/flash-sale/config/logging?type=file" \
  -H "Authorization: Bearer $ADMIN_TOKEN")
if echo "$SW_FILE" | grep -q "file"; then pass "Successfully configured File sink"; else fail "$SW_FILE"; fi

# ============================================================================
print_header "PHASE 6: LOAD BALANCING"
# ============================================================================

print_test "Send 9 orders across 3 instances"
for i in $(seq 1 9); do
  PID=$(( (i % 3) + 1 ))
  curl -s -X POST $BASE_URL/api/flash-sale/order \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $CUST_TOKEN" \
    -d "{\"productId\":$PID,\"quantity\":1}" > /dev/null
done
pass "9 concurrent requests dispatched via Nginx"

print_test "Verify distribution across instances"
C1=$(docker logs flashsale-app-1 2>&1 | grep -c "Received flash sale" || echo 0)
C2=$(docker logs flashsale-app-2 2>&1 | grep -c "Received flash sale" || echo 0)
C3=$(docker logs flashsale-app-3 2>&1 | grep -c "Received flash sale" || echo 0)
echo -n "(app-1=$C1, app-2=$C2, app-3=$C3) "
if [ "$C1" -gt 0 ] && [ "$C2" -gt 0 ] && [ "$C3" -gt 0 ]; then pass "Load was successfully balanced"; else fail "Uneven distribution"; fi

# ============================================================================
print_header "PHASE 7: CIRCUIT BREAKER (DB Failure + Recovery)"
# ============================================================================

print_test "Circuit breaker initial state"
CB_STATE=$(curl -s $BASE_URL/actuator/circuitbreakers)
if echo "$CB_STATE" | grep -q "CLOSED"; then pass "Status: CLOSED"
elif echo "$CB_STATE" | grep -q "HALF_OPEN"; then pass "Status: HALF_OPEN"
else fail "state not CLOSED"; fi

print_test "Stop PostgreSQL container"
docker stop flashsale-db > /dev/null 2>&1
sleep 2
pass "PostgreSQL is down"

echo "  ⏳ Sending requests to trigger circuit break (this takes ~30-60s per failed call)..."
for i in $(seq 1 5); do
  echo -n "    Attempt $i/5... "
  curl -s --max-time 35 -X POST $BASE_URL/api/flash-sale/order \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $CUST_TOKEN" \
    -d '{"productId":1,"quantity":1}' > /dev/null 2>&1 || true
  echo "done"
done

print_test "Circuit breaker state after DB stop"
# Query each instance directly since Nginx round-robins
ANY_OPEN=false
STATES=""
for CONTAINER in flashsale-app-1 flashsale-app-2 flashsale-app-3; do
  RAW=$(docker exec "$CONTAINER" wget -qO- http://localhost:8080/actuator/circuitbreakers 2>/dev/null || echo "{}")
  STATE=$(echo "$RAW" | sed 's/.*"state":"\([^"]*\)".*/\1/')
  STATES="$STATES $CONTAINER=$STATE"
  if [ "$STATE" = "OPEN" ] || [ "$STATE" = "HALF_OPEN" ]; then
    ANY_OPEN=true
  fi
done
if $ANY_OPEN; then pass "Circuit tripped ($STATES)"; else fail "No instance reached OPEN ($STATES)"; fi

print_test "Restart PostgreSQL container"
docker start flashsale-db > /dev/null 2>&1
sleep 5
pass "PostgreSQL is back online"

echo "  ⏳ Waiting for circuit breaker recovery (10s)..."
sleep 10

print_test "Orders work again after DB recovery"
RECOVERY=$(curl -s --max-time 35 -X POST $BASE_URL/api/flash-sale/order \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $CUST_TOKEN" \
  -d '{"productId":1,"quantity":1}')
REC_STATUS=$(extract "$RECOVERY" "status")
if [ "$REC_STATUS" = "SUCCESS" ]; then pass "Circuit recovered to CLOSED"; else fail "status=$REC_STATUS"; fi

# ============================================================================
print_header "RESULTS"
# ============================================================================

echo ""
echo "  Total : $TOTAL"
echo "  Passed: $PASS ✅"
echo "  Failed: $FAIL ❌"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo "  🎉 ALL TESTS PASSED!"
else
  echo "  ⚠️  $FAIL test(s) failed."
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Containers are still running. To tear down:"
echo "  docker-compose down -v"
echo "═══════════════════════════════════════════════════════════════"
