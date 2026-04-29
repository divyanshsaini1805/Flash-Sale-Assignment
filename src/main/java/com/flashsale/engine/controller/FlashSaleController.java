package com.flashsale.engine.controller;

import com.flashsale.engine.model.dto.FlashSaleRequest;
import com.flashsale.engine.model.dto.FlashSaleResponse;
import com.flashsale.engine.service.FlashSaleService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

/**
 * FlashSaleController - REST API
 * --------------------------------
 * Exposes a single POST endpoint to process flash sale orders.
 * The client has NO KNOWLEDGE of internal vs external workflows.
 * They simply send the product ID and quantity, and the server 
 * routes dynamically based on system health (circuit breaker).
 */
@RestController
@RequestMapping("/api/flash-sale")
@RequiredArgsConstructor
@Slf4j
public class FlashSaleController {

    private final FlashSaleService flashSaleService;
    private final com.flashsale.engine.utils.LoggingFrameWork loggingFrameWork;

    /**
     * POST /api/flash-sale/order
     *
     * Example request body:
     * {
     *   "productId": 1,
     *   "quantity": 2
     * }
     */
    @PostMapping("/order")
    public ResponseEntity<FlashSaleResponse> placeOrder(@RequestBody FlashSaleRequest request) {
        log.info("Received flash sale order request: {}", request);
        FlashSaleResponse response = flashSaleService.processOrder(request);
        return ResponseEntity.ok(response);
    }

    /**
     * POST /api/flash-sale/config/logging?type=database
     * Switches the logging sink at runtime (Strategy Pattern).
     */
    @PostMapping("/config/logging")
    public ResponseEntity<String> switchLogging(@RequestParam String type) {
        loggingFrameWork.setActiveStrategyType(type);
        return ResponseEntity.ok("Logging strategy switched to: " + type);
    }

    /** Health check */
    @GetMapping("/health")
    public ResponseEntity<String> health() {
        return ResponseEntity.ok("Flash Sale Engine is up and running!");
    }
}
