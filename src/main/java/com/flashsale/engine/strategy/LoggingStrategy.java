package com.flashsale.engine.strategy;

import com.flashsale.engine.model.dto.FlashSaleResponse;

/**
 * Strategy interface for flash sale order logging (sinks).
 */
public interface LoggingStrategy {
    /**
     * Persist the order result to the specific sink.
     */
    void writeLog(FlashSaleResponse response);

    /**
     * Returns a descriptive name of the destination.
     */
    String getDestinationName();
}
