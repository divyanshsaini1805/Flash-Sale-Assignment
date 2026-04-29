package com.flashsale.engine.strategy.impl;

import com.flashsale.engine.model.dto.FlashSaleResponse;
import com.flashsale.engine.strategy.LoggingStrategy;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.io.File;
import java.io.FileWriter;
import java.io.IOException;

/**
 * File-based logging strategy (NDJSON format).
 */
@Component("fileStrategy")
@Slf4j
public class FileLoggingStrategy implements LoggingStrategy {

    @Value("${flashsale.internal.output-dir:output/internal-orders}")
    private String outputDir;

    @Override
    public void writeLog(FlashSaleResponse response) {
        try {
            File dir = new File(outputDir);
            if (!dir.exists()) {
                dir.mkdirs();
            }

            File outputFile = new File(dir, "internal_orders.log");

            ObjectMapper mapper = new ObjectMapper();
            mapper.registerModule(new JavaTimeModule());
            mapper.disable(SerializationFeature.INDENT_OUTPUT);

            try (FileWriter writer = new FileWriter(outputFile, true)) {
                writer.write(mapper.writeValueAsString(response) + System.lineSeparator());
            }

            log.info("[STRATEGY:FILE] Order appended to log file: {} (executionTimeMs={})",
                    outputFile.getAbsolutePath(), response.getExecutionTimeMs());
        } catch (IOException e) {
            log.error("[STRATEGY:FILE] Failed to append order to log file", e);
            throw new RuntimeException("Failed to append order to log file", e);
        }
    }

    @Override
    public String getDestinationName() {
        return "File: " + outputDir;
    }
}
