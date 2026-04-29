package com.flashsale.engine.strategy.impl;

import com.flashsale.engine.model.ExternalOrderLog;
import com.flashsale.engine.model.dto.FlashSaleResponse;
import com.flashsale.engine.repository.ExternalOrderLogRepository;
import com.flashsale.engine.strategy.LoggingStrategy;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

/**
 * Database-based logging strategy.
 */
@Component("databaseStrategy")
@RequiredArgsConstructor
@Slf4j
public class DatabaseLoggingStrategy implements LoggingStrategy {

    private final ExternalOrderLogRepository externalOrderLogRepository;

    @Override
    public void writeLog(FlashSaleResponse response) {
        try {
            ExternalOrderLog logEntry = ExternalOrderLog.builder()
                    .productName(response.getProductName())
                    .requestedQuantity(response.getRequestedQuantity())
                    .unitPrice(response.getUnitPrice())
                    .totalPrice(response.getTotalPrice())
                    .status(response.getStatus())
                    .executionTimeMs(response.getExecutionTimeMs())
                    .build();

            externalOrderLogRepository.save(logEntry);
            log.info("[STRATEGY:DB] Order persisted to external_order_log (executionTimeMs={})",
                    response.getExecutionTimeMs());
        } catch (Exception e) {
            log.error("[STRATEGY:DB] Sink failed (DB unreachable), but processing completed: {}", e.getMessage());
        }
    }

    @Override
    public String getDestinationName() {
        return "DB: external_order_log";
    }
}
