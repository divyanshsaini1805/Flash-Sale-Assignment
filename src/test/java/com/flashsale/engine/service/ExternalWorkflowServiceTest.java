package com.flashsale.engine.service;

import com.flashsale.engine.model.dto.FlashSaleRequest;
import com.flashsale.engine.model.dto.FlashSaleResponse;
import com.flashsale.engine.repository.ExternalOrderLogRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ExternalWorkflowServiceTest {

    @Mock
    private ExternalOrderLogRepository externalOrderLogRepository;

    @InjectMocks
    private ExternalWorkflowService externalWorkflowService;

    @BeforeEach
    void setUp() {
        // The service initializes its cache in @PostConstruct, 
        // but for unit tests we can just let it happen or re-init if needed.
        // Actually, it's already initialized in the constructor/field for simplicity.
    }

    @Test
    void testProcess_Success() {
        // Arrange
        FlashSaleRequest request = new FlashSaleRequest(1L, 5); // Product 1 (iPhone) starts with 50

        // Act
        FlashSaleResponse response = externalWorkflowService.process(request);

        // Assert
        assertEquals("SUCCESS", response.getStatus());
        assertEquals("EXTERNAL", response.getWorkflow());
        assertEquals("iPhone 15 Pro", response.getProductName());
        assertEquals(45, response.getRemainingStock());
        
        // Note: Repository save is handled by FlashSaleService orchestrator, not here.
    }

    @Test
    void testProcess_InsufficientStock() {
        // Arrange
        FlashSaleRequest request = new FlashSaleRequest(1L, 999);

        // Act
        FlashSaleResponse response = externalWorkflowService.process(request);

        // Assert
        assertEquals("FAILED", response.getStatus());
        assertEquals("Insufficient stock in cache. Available: 50", response.getMessage());
    }

    @Test
    void testProcess_ProductNotFound() {
        // Arrange
        FlashSaleRequest request = new FlashSaleRequest(999L, 1);

        // Act
        FlashSaleResponse response = externalWorkflowService.process(request);

        // Assert
        assertEquals("FAILED", response.getStatus());
        assertEquals("Product not found in fallback cache for ID: 999", response.getMessage());
    }
}
