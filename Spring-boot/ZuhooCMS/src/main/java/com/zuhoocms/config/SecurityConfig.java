package com.zuhoocms.config;

import com.zuhoocms.auth.user.UserRepository;
import com.zuhoocms.security.JwtAuthFilter;
import com.zuhoocms.security.SubscriptionEnforcementFilter;
import lombok.RequiredArgsConstructor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpMethod;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.AuthenticationProvider;
import org.springframework.security.authentication.dao.DaoAuthenticationProvider;
import org.springframework.security.config.annotation.authentication.configuration.AuthenticationConfiguration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.core.userdetails.UsernameNotFoundException;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.config.annotation.method.configuration.EnableMethodSecurity;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.HttpStatusEntryPoint;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.http.HttpStatus;
import org.springframework.web.cors.CorsConfigurationSource;


@Configuration
@EnableWebSecurity
@EnableMethodSecurity
@RequiredArgsConstructor
public class SecurityConfig {

    private final JwtAuthFilter jwtAuthFilter;
    private final SubscriptionEnforcementFilter subscriptionEnforcementFilter;
    private final com.zuhoocms.modules.demo.DemoReadOnlyFilter demoReadOnlyFilter;
    private final UserRepository userRepository;
    private final CorsConfigurationSource corsConfigurationSource;

    private static final String[] PUBLIC_ENDPOINTS = {
        "/api/auth/**",
        "/api/companies/public/**",
        "/api/clients/public/**",
        // Permitted here only so signed links and public files work tokenless; FileServeController enforces the real rule (public reference, bearer auth + company/uploader, or valid ?exp&sig).
        "/uploads/*",
        "/api/public/files/*",
        "/api/payments/sslcommerz/callback/**",
        "/api/payments/sslcommerz/ipn",
        // Public company portal content (anonymous visitors browsing /portal/:subdomain)
        "/api/website/**",
        // Anonymous lead capture; honeypot + dedupe inside, rate-limit at the edge.
        "/api/public/crm/**",
        // "See Demo" session minting - the token it returns is made read-only by DemoReadOnlyFilter.
        "/api/public/demo/**",
        // Public careers pages: slug-scoped, OPEN postings only, honeypot in the apply endpoint.
        "/api/public/careers/**",
        // Landing-page live-traffic SSE stream (anonymous, unauthenticated /home)
        "/api/v1/metrics/**",
        // Browsers can't send an Authorization header on a WebSocket handshake, so WebSocketAuthInterceptor authenticates it via ?token= and refuses the upgrade instead - see WebSocketConfig.
        "/ws/**"
    };

    private static final String[] PUBLIC_GET_ENDPOINTS = {
        // Private file download: bearer auth OR ?exp&sig, decided in FileServeController.
        "/api/files/*",
        "/api/locations/**",
        // Name/price/description only, so the marketing homepage shows live prices rather than numbers that drift from what SslCommerzServiceImpl charges; mutating endpoints stay SUPER_ADMIN-only.
        "/api/subscription-plans"
    };

    @Bean
    // /uploads/** has no separate chain on purpose: FileServeController serves files through this one and sets Cache-Control per file (public, else private no-store).
    @Order(2)
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
            .cors(cors -> cors.configurationSource(corsConfigurationSource))
            .csrf(AbstractHttpConfigurer::disable)
            .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            // 401, not Spring's default 403: a 403 is indistinguishable from "no permission", so the frontend's silent-refresh-on-401 never fires once the access token expires.
            .exceptionHandling(ex -> ex.authenticationEntryPoint(new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED)))
            .authorizeHttpRequests(auth -> auth
                    // Container-internal ERROR dispatch only (Tomcat forwarding to /error after an exception escaped
                    // the DispatcherServlet). Without it the forward was authorized like a fresh request, /error is
                    // not public, and HttpStatusEntryPoint answered 401 - so a 404 or 400 reached the client as a
                    // misleading 401 with no body. This is a dispatcher-type matcher, not a path permit: a caller's
                    // own GET /error is a REQUEST dispatch and still needs authentication, and an ERROR dispatch
                    // cannot be triggered from outside.
                    .dispatcherTypeMatchers(jakarta.servlet.DispatcherType.ERROR).permitAll()
                    .requestMatchers("/swagger-ui/**",
                            "/v3/api-docs/**",
                            "/swagger-ui.html").permitAll()
                    .requestMatchers(PUBLIC_ENDPOINTS).permitAll()
                    .requestMatchers(HttpMethod.GET, PUBLIC_GET_ENDPOINTS).permitAll()
                    .anyRequest().authenticated()
            )
            .authenticationProvider(authenticationProvider())
            .addFilterBefore(jwtAuthFilter, UsernamePasswordAuthenticationFilter.class)
            .addFilterAfter(subscriptionEnforcementFilter, JwtAuthFilter.class)
            // Must run after JwtAuthFilter: it needs the authenticated user to tell whether this is the demo account.
            .addFilterAfter(demoReadOnlyFilter, SubscriptionEnforcementFilter.class);

        return http.build();
    }

    @Bean
    public UserDetailsService userDetailsService() {
        return email -> userRepository.findByEmail(email)
            .orElseThrow(() -> new UsernameNotFoundException("User not found: " + email));
    }

    @Bean
    public AuthenticationProvider authenticationProvider() {
        DaoAuthenticationProvider provider = new DaoAuthenticationProvider(userDetailsService());
        provider.setPasswordEncoder(passwordEncoder());
        return provider;
    }

    @Bean
    public AuthenticationManager authenticationManager(AuthenticationConfiguration config)
            throws Exception {
        return config.getAuthenticationManager();
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}
