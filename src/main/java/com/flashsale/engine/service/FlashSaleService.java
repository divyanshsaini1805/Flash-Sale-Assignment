package com.flashsale.engine.service;

import com.flashsale.engine.model.dto.FlashSaleRequest;
import com.flashsale.engine.model.dto.FlashSaleResponse;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * FlashSaleService - Orchestrator
 * --------------------------------
 * 1. Uses a Circuit Breaker to attempt the INTERNAL workflow first.
 * 2. If the DB is unhealthy (circuit open or DB throws exception), automatically
 *    falls back to the EXTERNAL workflow (in-memory cache).
 * 3. Measures actual processing time.
 * 4. Pads to a configurable target time so both workflows take equal duration.
 * 5. Sets executionTimeMs on the response.
 * 6. Dispatches the sink write (file for internal, DB for external).
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class FlashSaleService {

    private final InternalWorkflowService internalWorkflowService;
    private final ExternalWorkflowService externalWorkflowService;
    private final CircuitBreakerRegistry circuitBreakerRegistry;
    private final com.flashsale.engine.utils.LoggingFrameWork loggingFrameWork;

    @Value("${flashsale.target-execution-time-ms:200}")
    private long targetExecutionTimeMs;

    public FlashSaleResponse processOrder(FlashSaleRequest request) {
        log.info("Processing order for productId={} (targetTime={}ms)", request.getProductId(), targetExecutionTimeMs);

        // 1. Time the actual processing
        long startTime = System.currentTimeMillis();
        FlashSaleResponse response;

        CircuitBreaker circuitBreaker = circuitBreakerRegistry.circuitBreaker("dbCircuitBreaker");

        try {
            // Attempt the internal workflow wrapped in the circuit breaker
            response = circuitBreaker.executeSupplier(() -> internalWorkflowService.process(request));
        } catch (Exception e) {
            // Circuit is OPEN or the DB query failed -> fallback to external workflow
            log.warn("Circuit Breaker triggered fallback due to: {}", e.getMessage());
            response = externalWorkflowService.process(request);
        }

        long elapsed = System.currentTimeMillis() - startTime;

        // 2. Pad to target time so both workflows take the same duration
        if (elapsed < targetExecutionTimeMs) {
            long sleepTime = targetExecutionTimeMs - elapsed;
            log.info("Workflow '{}' finished in {}ms, padding {}ms to reach target {}ms",
                    response.getWorkflow(), elapsed, sleepTime, targetExecutionTimeMs);
            try {
                Thread.sleep(sleepTime);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                log.warn("Sleep interrupted during execution time normalization");
            }
        } else {
            log.info("Workflow '{}' took {}ms (>= target {}ms), no padding needed",
                    response.getWorkflow(), elapsed, targetExecutionTimeMs);
        }

        long finalExecutionTime = System.currentTimeMillis() - startTime;

        // 3. Set execution time on the response
        response.setExecutionTimeMs(finalExecutionTime);

        // 4. Dispatch sink write (using the active Strategy via LoggingFrameWork)
        loggingFrameWork.writeLog(response);

        log.info("Order completed: workflow={}, executionTimeMs={}", response.getWorkflow(), finalExecutionTime);
        return response;
    }
}
