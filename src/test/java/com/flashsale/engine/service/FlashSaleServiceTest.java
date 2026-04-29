package com.flashsale.engine.service;

import com.flashsale.engine.model.dto.FlashSaleRequest;
import com.flashsale.engine.model.dto.FlashSaleResponse;
import com.flashsale.engine.utils.LoggingFrameWork;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.function.Supplier;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class FlashSaleServiceTest {

    @Mock
    private InternalWorkflowService internalWorkflowService;

    @Mock
    private ExternalWorkflowService externalWorkflowService;

    @Mock
    private CircuitBreakerRegistry circuitBreakerRegistry;

    @Mock
    private CircuitBreaker circuitBreaker;

    @Mock
    private LoggingFrameWork loggingFrameWork;

    @InjectMocks
    private FlashSaleService flashSaleService;

    @BeforeEach
    void setUp() {
        // Mock the circuit breaker registry to return our mock circuit breaker
        lenient().when(circuitBreakerRegistry.circuitBreaker(anyString())).thenReturn(circuitBreaker);
        
        // Mock the circuit breaker to execute the supplier directly by default
        lenient().when(circuitBreaker.executeSupplier(any())).thenAnswer(invocation -> {
            Supplier<FlashSaleResponse> supplier = invocation.getArgument(0);
            return supplier.get();
        });

        // Set the target execution time for padding tests
        ReflectionTestUtils.setField(flashSaleService, "targetExecutionTimeMs", 200L);
    }

    @Test
    void testProcessOrder_InternalSuccess() {
        // Arrange
        FlashSaleRequest request = new FlashSaleRequest(1L, 2);
        FlashSaleResponse internalResponse = FlashSaleResponse.builder()
                .workflow("INTERNAL")
                .status("SUCCESS")
                .productName("iPhone")
                .build();

        when(internalWorkflowService.process(request)).thenReturn(internalResponse);

        // Act
        FlashSaleResponse result = flashSaleService.processOrder(request);

        // Assert
        assertNotNull(result);
        assertEquals("INTERNAL", result.getWorkflow());
        assertEquals("SUCCESS", result.getStatus());
        verify(internalWorkflowService, times(1)).process(request);
        verify(externalWorkflowService, never()).process(any());
        verify(loggingFrameWork, times(1)).writeLog(result);
    }

    @Test
    void testProcessOrder_FallbackOnException() {
        // Arrange
        FlashSaleRequest request = new FlashSaleRequest(1L, 2);
        FlashSaleResponse externalResponse = FlashSaleResponse.builder()
                .workflow("EXTERNAL")
                .status("SUCCESS")
                .productName("iPhone (Cache)")
                .build();

        // Simulate internal workflow failure
        when(internalWorkflowService.process(request)).thenThrow(new RuntimeException("DB Down"));
        when(externalWorkflowService.process(request)).thenReturn(externalResponse);

        // Act
        FlashSaleResponse result = flashSaleService.processOrder(request);

        // Assert
        assertNotNull(result);
        assertEquals("EXTERNAL", result.getWorkflow());
        verify(internalWorkflowService, times(1)).process(request);
        verify(externalWorkflowService, times(1)).process(request);
        verify(loggingFrameWork, times(1)).writeLog(result);
    }

    @Test
    void testProcessOrder_TimingNormalization() {
        // Arrange
        FlashSaleRequest request = new FlashSaleRequest(1L, 2);
        FlashSaleResponse internalResponse = FlashSaleResponse.builder()
                .workflow("INTERNAL")
                .status("SUCCESS")
                .build();

        when(internalWorkflowService.process(request)).thenAnswer(inv -> {
            // Processing takes 50ms
            Thread.sleep(50);
            return internalResponse;
        });

        // Act
        long startTime = System.currentTimeMillis();
        FlashSaleResponse result = flashSaleService.processOrder(request);
        long duration = System.currentTimeMillis() - startTime;

        // Assert
        // Result should be at least 200ms due to padding
        assertEquals(200L, result.getExecutionTimeMs(), 50L); // allow 50ms delta for test overhead
        verify(loggingFrameWork, times(1)).writeLog(result);
    }
}
