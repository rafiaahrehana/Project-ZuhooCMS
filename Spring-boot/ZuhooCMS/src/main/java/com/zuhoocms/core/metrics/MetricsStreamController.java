package com.zuhoocms.core.metrics;

import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.io.IOException;
import java.util.Random;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

@RestController
@RequestMapping("/api/v1/metrics")
public class MetricsStreamController {

    private final Random random = new Random();
    private final ExecutorService executor = Executors.newCachedThreadPool();

    /** Streams simulated traffic metrics over SSE; the frontend WebGL uses them to drive particle simulation speed. */
    @GetMapping(value = "/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public SseEmitter streamTrafficMetrics() {
        // Bounded timeout rather than -1L (infinite).
        SseEmitter emitter = new SseEmitter(600000L);
        
        executor.execute(() -> {
            try {
                for (int i = 0; i < 1000; i++) {
                    int simulatedTraffic = 1000 + random.nextInt(4000); // 1000 to 5000

                    emitter.send(SseEmitter.event()
                            .data(String.valueOf(simulatedTraffic)));
                    
                    Thread.sleep(500); // Send every 500ms
                }
                emitter.complete();
            } catch (IOException | InterruptedException ex) {
                emitter.completeWithError(ex);
            }
        });
        
        return emitter;
    }
}
