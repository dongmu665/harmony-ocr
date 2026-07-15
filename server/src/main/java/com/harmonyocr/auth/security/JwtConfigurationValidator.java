package com.harmonyocr.auth.security;

import jakarta.annotation.PostConstruct;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.Set;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

/**
 * JWT 配置启动校验器，属于 auth security 模块。
 * 维护说明：防止生产或未声明环境误用 dev/test 占位密钥；校验过程不得输出 JWT secret 原文。
 */
@Component
public class JwtConfigurationValidator {

    private static final int MIN_SECRET_BYTES = 32;
    private static final Set<String> NON_PRODUCTION_PROFILES = Set.of("dev", "test");
    private static final Set<String> PLACEHOLDER_SECRETS = Set.of(
            "dev-only-change-me-at-least-32-characters",
            "test-only-placeholder-not-for-production-at-least-32-characters");

    private final JwtProperties jwtProperties;
    private final Environment environment;

    public JwtConfigurationValidator(JwtProperties jwtProperties, Environment environment) {
        this.jwtProperties = jwtProperties;
        this.environment = environment;
    }

    /**
     * 校验 JWT secret 和有效期配置。
     * 参数来自构造器注入；返回值为空。安全注意：异常消息只说明配置来源要求，不包含 secret 原文。
     */
    @PostConstruct
    public void validate() {
        String secret = jwtProperties.getSecret();
        if (!StringUtils.hasText(secret) || secret.getBytes(StandardCharsets.UTF_8).length < MIN_SECRET_BYTES) {
            throw new IllegalStateException("app.jwt.secret must be configured with at least 32 bytes");
        }
        if (jwtProperties.getAccessTokenTtlMinutes() <= 0 || jwtProperties.getRefreshTokenTtlDays() <= 0) {
            throw new IllegalStateException("app.jwt token TTL values must be positive");
        }
        if (isProductionLikeProfile() && PLACEHOLDER_SECRETS.contains(secret)) {
            throw new IllegalStateException("JWT_SECRET must be provided by environment or secret manager in production");
        }
    }

    private boolean isProductionLikeProfile() {
        String[] activeProfiles = environment.getActiveProfiles();
        if (activeProfiles.length == 0) {
            String configured = environment.getProperty("spring.profiles.active", "");
            activeProfiles = Arrays.stream(configured.split(","))
                    .map(String::trim)
                    .filter(StringUtils::hasText)
                    .toArray(String[]::new);
        }
        if (activeProfiles.length == 0) {
            return true;
        }
        return Arrays.stream(activeProfiles)
                .noneMatch(NON_PRODUCTION_PROFILES::contains);
    }
}
