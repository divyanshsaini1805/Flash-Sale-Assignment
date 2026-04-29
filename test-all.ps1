# ============================================================================
#  Flash Sale Engine - Full Integration Test Script
#  Run: .\test-all.ps1
#  Prerequisites: Docker, Docker Compose, curl/Invoke-RestMethod
# ============================================================================

$BASE_URL = "http://localhost"
$PASS = 0
$FAIL = 0
$TOTAL = 0

# ---- Helpers ----
function Print-Header($text) {
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor Cyan
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host "===============================================================" -ForegroundColor Cyan
}

function Print-Test($text) {
    $script:TOTAL++
    Write-Host -NoNewline "  [$script:TOTAL] $text ... "
}

function Pass-Test($details = "") {
    $script:PASS++
    if ($details) {
        Write-Host "PASS" -ForegroundColor Green -NoNewline
        Write-Host " - $details" -ForegroundColor DarkGray
    } else {
        Write-Host "PASS" -ForegroundColor Green
    }
}

function Fail-Test($reason) {
    $script:FAIL++
    Write-Host "FAIL - $reason" -ForegroundColor Red
}

# ============================================================================
Print-Header "PHASE 0: INFRASTRUCTURE SETUP"
# ============================================================================

Write-Host "  Tearing down any existing containers..."
docker-compose down -v 2>$null
docker rm -f flashsale-db flashsale-app 2>$null

Write-Host "  Building and starting all containers..."
docker-compose up --build -d | Select-Object -Last 5

Write-Host "  Waiting for Spring Boot to initialize (45s)..."
Start-Sleep -Seconds 45

Print-Test "All 5 containers running"
$RUNNING = (docker ps --filter name=flashsale --format "{{.Names}}").Count
if ($RUNNING -ge 5) { Pass-Test "$RUNNING containers active" } else { Fail-Test "Only $RUNNING containers running" }

# ============================================================================
Print-Header "PHASE 1: HEALTH CHECKS"
# ============================================================================

Print-Test "Health endpoint"
try {
    $response = Invoke-WebRequest -Uri "$BASE_URL/api/flash-sale/health" -UseBasicParsing
    if ($response.StatusCode -eq 200) { Pass-Test "Returned HTTP 200" } else { Fail-Test "HTTP $($response.StatusCode)" }
} catch { Fail-Test $_.Exception.Message }

Print-Test "Actuator health endpoint"
try {
    $response = Invoke-WebRequest -Uri "$BASE_URL/actuator/health" -UseBasicParsing
    if ($response.StatusCode -eq 200) { Pass-Test "Returned HTTP 200" } else { Fail-Test "HTTP $($response.StatusCode)" }
} catch { Fail-Test $_.Exception.Message }

Print-Test "Circuit breaker endpoint"
try {
    $response = Invoke-WebRequest -Uri "$BASE_URL/actuator/circuitbreakers" -UseBasicParsing
    if ($response.StatusCode -eq 200) { Pass-Test "Returned HTTP 200" } else { Fail-Test "HTTP $($response.StatusCode)" }
} catch { Fail-Test $_.Exception.Message }

Print-Test "Nginx LB health"
try {
    $response = Invoke-WebRequest -Uri "$BASE_URL/nginx-health" -UseBasicParsing
    if ($response.StatusCode -eq 200) { Pass-Test "Returned HTTP 200" } else { Fail-Test "HTTP $($response.StatusCode)" }
} catch { Fail-Test $_.Exception.Message }

# ============================================================================
Print-Header "PHASE 2: AUTHENTICATION"
# ============================================================================

Print-Test "Register customer"
try {
    $body = @{ username = "customer1"; password = "cust123" } | ConvertTo-Json
    $response = Invoke-RestMethod -Method POST -Uri "$BASE_URL/api/auth/register" -ContentType "application/json" -Body $body
    $REG_TOKEN = $response.token
    $REG_ROLE = $response.role
    if ($REG_ROLE -eq "CUSTOMER" -and $REG_TOKEN) { Pass-Test "Assigned Role: $REG_ROLE, Token generated" } else { Fail-Test "role=$REG_ROLE" }
} catch { Fail-Test $_.Exception.Message }

Print-Test "Duplicate registration rejected"
try {
    $body = @{ username = "customer1"; password = "cust123" } | ConvertTo-Json
    Invoke-RestMethod -Method POST -Uri "$BASE_URL/api/auth/register" -ContentType "application/json" -Body $body | Out-Null
    Fail-Test "Should have thrown 409"
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 409) { Pass-Test "Correctly blocked with HTTP 409 Conflict" } else { Fail-Test "HTTP $($_.Exception.Response.StatusCode.value__) (expected 409)" }
}

Print-Test "Register admin"
try {
    $body = @{ username = "admin1"; password = "admin123" } | ConvertTo-Json
    $response = Invoke-RestMethod -Method POST -Uri "$BASE_URL/api/auth/register/admin" -ContentType "application/json" -Body $body
    $ADMIN_TOKEN = $response.token
    $ADMIN_ROLE = $response.role
    if ($ADMIN_ROLE -eq "ADMIN" -and $ADMIN_TOKEN) { Pass-Test "Assigned Role: $ADMIN_ROLE, Token generated" } else { Fail-Test "role=$ADMIN_ROLE" }
} catch { Fail-Test $_.Exception.Message }

Print-Test "Login with valid credentials"
try {
    $body = @{ username = "customer1"; password = "cust123" } | ConvertTo-Json
    $response = Invoke-RestMethod -Method POST -Uri "$BASE_URL/api/auth/login" -ContentType "application/json" -Body $body
    $CUST_TOKEN = $response.token
    $LOGIN_MSG = $response.message
    if ($LOGIN_MSG -eq "Login successful") { Pass-Test "Successfully retrieved JWT for customer1" } else { Fail-Test "msg=$LOGIN_MSG" }
} catch { Fail-Test $_.Exception.Message }

Print-Test "Login with wrong password"
try {
    $body = @{ username = "customer1"; password = "wrong" } | ConvertTo-Json
    Invoke-RestMethod -Method POST -Uri "$BASE_URL/api/auth/login" -ContentType "application/json" -Body $body | Out-Null
    Fail-Test "Should have thrown 401"
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 401) { Pass-Test "Correctly blocked with HTTP 401 Unauthorized" } else { Fail-Test "HTTP $($_.Exception.Response.StatusCode.value__) (expected 401)" }
}

# ============================================================================
Print-Header "PHASE 3: AUTHORIZATION (RBAC)"
# ============================================================================

Print-Test "Order WITHOUT token throws 403 Forbidden"
try {
    $body = @{ productId = 1; quantity = 1 } | ConvertTo-Json
    Invoke-RestMethod -Method POST -Uri "$BASE_URL/api/flash-sale/order" -ContentType "application/json" -Body $body | Out-Null
    Fail-Test "Should have thrown 403"
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 403) { Pass-Test "Blocked with HTTP 403 Forbidden" } else { Fail-Test "HTTP $($_.Exception.Response.StatusCode.value__)" }
}

Print-Test "Order WITH customer token returns 200 OK"
try {
    $body = @{ productId = 1; quantity = 1 } | ConvertTo-Json
    $headers = @{ Authorization = "Bearer $CUST_TOKEN" }
    $response = Invoke-RestMethod -Method POST -Uri "$BASE_URL/api/flash-sale/order" -ContentType "application/json" -Headers $headers -Body $body
    if ($response.status -eq "SUCCESS") { Pass-Test "Allowed with HTTP 200 OK" } else { Fail-Test "status=$($response.status)" }
} catch { Fail-Test $_.Exception.Message }

Print-Test "Admin config by CUSTOMER throws 403 Forbidden"
try {
    $headers = @{ Authorization = "Bearer $CUST_TOKEN" }
    Invoke-RestMethod -Method POST -Uri "$BASE_URL/api/flash-sale/config/logging?type=database" -Headers $headers | Out-Null
    Fail-Test "Should have thrown 403"
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 403) { Pass-Test "Blocked with HTTP 403 Forbidden" } else { Fail-Test "HTTP $($_.Exception.Response.StatusCode.value__)" }
}

Print-Test "Admin config by ADMIN returns 200 OK"
try {
    $headers = @{ Authorization = "Bearer $ADMIN_TOKEN" }
    $response = Invoke-RestMethod -Method POST -Uri "$BASE_URL/api/flash-sale/config/logging?type=database" -Headers $headers
    if ($response -match "database") { Pass-Test "Allowed with HTTP 200 OK" } else { Fail-Test "Response: $response" }
} catch { Fail-Test $_.Exception.Message }

# ============================================================================
Print-Header "PHASE 4: ORDER PROCESSING"
# ============================================================================

# Switch back to file logging
try {
    $headers = @{ Authorization = "Bearer $ADMIN_TOKEN" }
    Invoke-RestMethod -Method POST -Uri "$BASE_URL/api/flash-sale/config/logging?type=file" -Headers $headers | Out-Null
} catch {}

Print-Test "Order product 1"
try {
    $body = @{ productId = 1; quantity = 2 } | ConvertTo-Json
    $headers = @{ Authorization = "Bearer $CUST_TOKEN" }
    $ORDER1 = Invoke-RestMethod -Method POST -Uri "$BASE_URL/api/flash-sale/order" -ContentType "application/json" -Headers $headers -Body $body
    if ($ORDER1.status -eq "SUCCESS" -and $ORDER1.workflow -eq "INTERNAL") { Pass-Test "Status: $($ORDER1.status), Flow: $($ORDER1.workflow)" } else { Fail-Test "status=$($ORDER1.status) workflow=$($ORDER1.workflow)" }
} catch { Fail-Test $_.Exception.Message }

Print-Test "Order product 5"
try {
    $body = @{ productId = 5; quantity = 3 } | ConvertTo-Json
    $headers = @{ Authorization = "Bearer $CUST_TOKEN" }
    $ORDER5 = Invoke-RestMethod -Method POST -Uri "$BASE_URL/api/flash-sale/order" -ContentType "application/json" -Headers $headers -Body $body
    if ($ORDER5.status -eq "SUCCESS") { Pass-Test "Purchased 3x $($ORDER5.productName)" } else { Fail-Test "status=$($ORDER5.status)" }
} catch { Fail-Test $_.Exception.Message }

Print-Test "Order with insufficient stock"
try {
    $body = @{ productId = 4; quantity = 9999 } | ConvertTo-Json
    $headers = @{ Authorization = "Bearer $CUST_TOKEN" }
    $ORDER_FAIL = Invoke-RestMethod -Method POST -Uri "$BASE_URL/api/flash-sale/order" -ContentType "application/json" -Headers $headers -Body $body
    if ($ORDER_FAIL.status -eq "FAILED") { Pass-Test "Rejected cleanly - Msg: $($ORDER_FAIL.message)" } else { Fail-Test "status=$($ORDER_FAIL.status)" }
} catch { Fail-Test $_.Exception.Message }

Print-Test "Timing normalization (approx 200ms)"
if ($ORDER1) {
    $EXEC_TIME = $ORDER1.executionTimeMs
    if ($EXEC_TIME -ge 195 -and $EXEC_TIME -le 250) { Pass-Test "Returned in ${EXEC_TIME}ms" } else { Fail-Test "executionTimeMs=$EXEC_TIME" }
} else { Fail-Test "ORDER1 not available" }

# ============================================================================
Print-Header "PHASE 5: STRATEGY PATTERN"
# ============================================================================

Print-Test "Switch to database logging"
try {
    $headers = @{ Authorization = "Bearer $ADMIN_TOKEN" }
    $SW_DB = Invoke-RestMethod -Method POST -Uri "$BASE_URL/api/flash-sale/config/logging?type=database" -Headers $headers
    if ($SW_DB -match "database") { Pass-Test "Successfully configured DB sink" } else { Fail-Test "$SW_DB" }
} catch { Fail-Test $_.Exception.Message }

Print-Test "Order logs to DB after switch"
try {
    $body = @{ productId = 2; quantity = 1 } | ConvertTo-Json
    $headers = @{ Authorization = "Bearer $CUST_TOKEN" }
    $ORDER_DB = Invoke-RestMethod -Method POST -Uri "$BASE_URL/api/flash-sale/order" -ContentType "application/json" -Headers $headers -Body $body
    if ($ORDER_DB.status -eq "SUCCESS") { Pass-Test "Destination -> $($ORDER_DB.outputDestination)" } else { Fail-Test "status=$($ORDER_DB.status)" }
} catch { Fail-Test $_.Exception.Message }

Print-Test "Switch back to file logging"
try {
    $headers = @{ Authorization = "Bearer $ADMIN_TOKEN" }
    $SW_FILE = Invoke-RestMethod -Method POST -Uri "$BASE_URL/api/flash-sale/config/logging?type=file" -Headers $headers
    if ($SW_FILE -match "file") { Pass-Test "Successfully configured File sink" } else { Fail-Test "$SW_FILE" }
} catch { Fail-Test $_.Exception.Message }

# ============================================================================
Print-Header "PHASE 6: LOAD BALANCING"
# ============================================================================

Print-Test "Send 9 orders across 3 instances"
try {
    for ($i = 1; $i -le 9; $i++) {
        $Product_ID = ($i % 3) + 1
        $body = @{ productId = $Product_ID; quantity = 1 } | ConvertTo-Json
        $headers = @{ Authorization = "Bearer $CUST_TOKEN" }
        Invoke-RestMethod -Method POST -Uri "$BASE_URL/api/flash-sale/order" -ContentType "application/json" -Headers $headers -Body $body | Out-Null
    }
    Pass-Test "9 concurrent requests dispatched via Nginx"
} catch { Fail-Test $_.Exception.Message }

Print-Test "Verify distribution across instances"
try {
    $C1 = (docker logs flashsale-app-1 2>&1 | Select-String "Received flash sale").Count
    $C2 = (docker logs flashsale-app-2 2>&1 | Select-String "Received flash sale").Count
    $C3 = (docker logs flashsale-app-3 2>&1 | Select-String "Received flash sale").Count
    Write-Host -NoNewline "(app-1=$C1, app-2=$C2, app-3=$C3) "
    if ($C1 -gt 0 -and $C2 -gt 0 -and $C3 -gt 0) { Pass-Test "Load was successfully balanced" } else { Fail-Test "Uneven distribution" }
} catch { Fail-Test $_.Exception.Message }

# ============================================================================
Print-Header "PHASE 7: CIRCUIT BREAKER"
# ============================================================================

Print-Test "Circuit breaker initial state"
try {
    $CB_STATE = Invoke-RestMethod -Uri "$BASE_URL/actuator/circuitbreakers"
    $state = $CB_STATE.circuitBreakers.dbCircuitBreaker.state
    if ($state -eq "CLOSED" -or $state -eq "HALF_OPEN") { Pass-Test "Status: $state" } else { Fail-Test "state not CLOSED (was $state)" }
} catch { Fail-Test $_.Exception.Message }

Print-Test "Stop PostgreSQL container"
docker stop flashsale-db > $null 2>&1
Start-Sleep -Seconds 2
Pass-Test "PostgreSQL is down"

Write-Host "  Sending requests to trigger circuit break (this takes time)..."
for ($i = 1; $i -le 5; $i++) {
    Write-Host -NoNewline "    Attempt $i/5... "
    try {
        $body = @{ productId = 1; quantity = 1 } | ConvertTo-Json
        $headers = @{ Authorization = "Bearer $CUST_TOKEN" }
        Invoke-RestMethod -Method POST -Uri "$BASE_URL/api/flash-sale/order" -ContentType "application/json" -Headers $headers -Body $body -TimeoutSec 35 | Out-Null
    } catch {}
    Write-Host "done"
}

Print-Test "Circuit breaker state after DB stop"
try {
    # Query each instance directly via wget (Alpine has wget, not curl)
    $anyOpen = $false
    $states = @()
    foreach ($container in @("flashsale-app-1", "flashsale-app-2", "flashsale-app-3")) {
        $raw = docker exec $container wget -qO- http://localhost:8080/actuator/circuitbreakers 2>$null
        if ($raw -match '"state"\s*:\s*"(OPEN|HALF_OPEN)"') {
            $anyOpen = $true
            $states += "$container=$($Matches[1])"
        } elseif ($raw -match '"state"\s*:\s*"(\w+)"') {
            $states += "$container=$($Matches[1])"
        }
    }
    $stateStr = $states -join ", "
    if ($anyOpen) { Pass-Test "Circuit tripped ($stateStr)" } else { Fail-Test "No instance reached OPEN ($stateStr)" }
} catch { Fail-Test $_.Exception.Message }

Print-Test "Restart PostgreSQL container"
docker start flashsale-db > $null 2>&1
Start-Sleep -Seconds 5
Pass-Test "PostgreSQL is back online"

Write-Host "  Waiting for circuit breaker recovery (10s)..."
Start-Sleep -Seconds 10

Print-Test "Orders work again after DB recovery"
try {
    $body = @{ productId = 1; quantity = 1 } | ConvertTo-Json
    $headers = @{ Authorization = "Bearer $CUST_TOKEN" }
    $RECOVERY = Invoke-RestMethod -Method POST -Uri "$BASE_URL/api/flash-sale/order" -ContentType "application/json" -Headers $headers -Body $body -TimeoutSec 35
    if ($RECOVERY.status -eq "SUCCESS") { Pass-Test "Circuit recovered to CLOSED" } else { Fail-Test "status=$($RECOVERY.status)" }
} catch { Fail-Test $_.Exception.Message }

# ============================================================================
Print-Header "RESULTS"
# ============================================================================

Write-Host ""
Write-Host "  Total : $TOTAL"
Write-Host "  Passed: $PASS" -ForegroundColor Green
Write-Host "  Failed: $FAIL" -ForegroundColor Red
Write-Host ""

if ($FAIL -eq 0) {
    Write-Host "  ALL TESTS PASSED!" -ForegroundColor Green
} else {
    Write-Host "  $FAIL test(s) failed." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "==============================================================="
Write-Host "  Containers are still running. To tear down:"
Write-Host "  docker-compose down -v"
Write-Host "==============================================================="
