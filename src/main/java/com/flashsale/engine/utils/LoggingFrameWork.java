package com.flashsale.engine.utils;

import com.flashsale.engine.model.dto.FlashSaleResponse;
import com.flashsale.engine.strategy.LoggingStrategy;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.util.Map;

/**
 * LoggingFrameWork - Strategy Context
 * ----------------------------------
 * Manages available logging strategies and allows switching the active
 * strategy at runtime.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class LoggingFrameWork {

    /**
     * Map of strategy beans injected by Spring.
     * Keys: "fileStrategy", "databaseStrategy"
     */
    private final Map<String, LoggingStrategy> strategies;

    /**
     * Current active strategy type.
     * Can be "file" or "database".
     */
    private String activeStrategyType = "file";

    /**
     * Delegates logging to the current active strategy.
     */
    public void writeLog(FlashSaleResponse response) {
        String strategyKey = activeStrategyType + "Strategy";
        LoggingStrategy strategy = strategies.get(strategyKey);

        if (strategy == null) {
            log.warn("Strategy '{}' not found, falling back to fileStrategy", strategyKey);
            strategy = strategies.get("fileStrategy");
        }

        strategy.writeLog(response);
    }

    /**
     * Switches the active strategy at runtime.
     * @param type "file" or "database"
     */
    public void setActiveStrategyType(String type) {
        log.info("[LOGGING] Switching active strategy to: {}", type);
        this.activeStrategyType = type.toLowerCase();
    }

    public String getActiveStrategyType() {
        return activeStrategyType;
    }
}
