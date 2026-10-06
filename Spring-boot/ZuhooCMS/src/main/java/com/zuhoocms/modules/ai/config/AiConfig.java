package com.zuhoocms.modules.ai.config;
import org.springframework.boot.restclient.RestTemplateBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;

import java.time.Duration;

@Configuration
public class AiConfig {

    // Connect stays short (ai.global-timeout-ms) so an unreachable provider fails fast; read gets its own longer ai.read-timeout-ms, since cutting off a legitimate long generation turned a slow success into a retried failure.
    @Bean("aiRestTemplate")
    public RestTemplate aiRestTemplate(RestTemplateBuilder builder, AiProperties props) {
        return builder
            .connectTimeout(Duration.ofMillis(props.getGlobalTimeoutMs()))
            .readTimeout(Duration.ofMillis(props.getReadTimeoutMs()))
            .build();
    }
}
