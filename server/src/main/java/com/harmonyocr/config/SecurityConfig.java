package com.harmonyocr.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.harmonyocr.auth.security.JwtAuthenticationFilter;
import com.harmonyocr.auth.security.RestAuthenticationEntryPoint;
import com.harmonyocr.common.api.Result;
import com.harmonyocr.common.error.ErrorCode;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;

/**
 * Spring Security 配置，属于 config 模块。
 * 维护说明：配置无状态 JWT 鉴权、匿名接口白名单、统一安全错误响应和 BCrypt 密码编码器。
 */
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    /**
     * 构建后端安全过滤器链。
     * 参数包括 HttpSecurity、JWT 过滤器、认证失败入口和 JSON 序列化器；返回 SecurityFilterChain。
     * 安全注意：只放行 health、register、login、refresh、反馈提交、test profile 用户 seed 和静态管理台页面资源；管理 API 仍必须 JWT 鉴权。
     */
    @Bean
    SecurityFilterChain securityFilterChain(
            HttpSecurity http,
            JwtAuthenticationFilter jwtAuthenticationFilter,
            RestAuthenticationEntryPoint authenticationEntryPoint,
            ObjectMapper objectMapper) throws Exception {
        http
                .csrf(AbstractHttpConfigurer::disable)
                .httpBasic(AbstractHttpConfigurer::disable)
                .formLogin(AbstractHttpConfigurer::disable)
                .logout(AbstractHttpConfigurer::disable)
                .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .exceptionHandling(exceptions -> exceptions
                        .authenticationEntryPoint(authenticationEntryPoint)
                        .accessDeniedHandler((request, response, accessDeniedException) -> {
                            response.setStatus(HttpServletResponse.SC_FORBIDDEN);
                            response.setContentType(MediaType.APPLICATION_JSON_VALUE);
                            response.setCharacterEncoding("UTF-8");
                            objectMapper.writeValue(response.getWriter(), Result.failure(ErrorCode.FORBIDDEN));
                        }))
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers(HttpMethod.GET, "/api/v1/health").permitAll()
                        .requestMatchers(HttpMethod.GET,
                                "/admin/console",
                                "/admin/console.html",
                                "/admin/assets/**").permitAll()
                        .requestMatchers(HttpMethod.POST,
                                "/api/v1/auth/register",
                                "/api/v1/auth/login",
                                "/api/v1/auth/refresh",
                                "/api/v1/test-support/users",
                                "/api/v1/feedback").permitAll()
                        .anyRequest().authenticated())
                .addFilterBefore(jwtAuthenticationFilter, UsernamePasswordAuthenticationFilter.class)
                .cors(Customizer.withDefaults());
        return http.build();
    }

    /**
     * 提供 BCrypt 密码编码器。
     * 返回 PasswordEncoder，用于注册保存 password_hash 和登录密码校验。
     */
    @Bean
    PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    /**
     * 禁用 Spring Security 默认用户生成。
     * 返回空的内存用户服务，避免开发期生成随机密码干扰 JWT 认证体系。
     */
    @Bean
    UserDetailsService userDetailsService() {
        return new InMemoryUserDetailsManager();
    }
}
