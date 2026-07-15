package com.harmonyocr.auth;

import com.harmonyocr.auth.security.JwtConfigurationValidator;
import com.harmonyocr.auth.security.JwtProperties;
import com.harmonyocr.auth.security.JwtService;
import org.junit.jupiter.api.Test;
import org.springframework.mock.env.MockEnvironment;

import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * JWT 配置校验测试。
 * 维护说明：确保应用不会接受过短或缺失的 JWT secret，避免测试或生产环境降级成弱签名配置。
 */
class JwtConfigurationTest {

    @Test
    void jwtServiceRejectsBlankOrShortSecret() {
        JwtProperties blank = properties("");
        assertThatThrownBy(() -> new JwtService(blank))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("app.jwt.secret");

        JwtProperties shortSecret = properties("short");
        assertThatThrownBy(() -> new JwtService(shortSecret))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("at least 32 bytes");
    }

    @Test
    void productionLikeProfileRejectsDevOrTestPlaceholderSecret() {
        JwtConfigurationValidator validator = new JwtConfigurationValidator(
                properties("dev-only-change-me-at-least-32-characters"),
                new MockEnvironment().withProperty("spring.profiles.active", "prod"));

        assertThatThrownBy(validator::validate)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("JWT_SECRET");

        JwtConfigurationValidator noExplicitProfile = new JwtConfigurationValidator(
                properties("test-only-placeholder-not-for-production-at-least-32-characters"),
                new MockEnvironment());

        assertThatThrownBy(noExplicitProfile::validate)
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("JWT_SECRET");
    }

    @Test
    void devAndTestProfilesMayUseExplicitNonProductionSecrets() {
        assertThatCode(new JwtConfigurationValidator(
                properties("dev-only-change-me-at-least-32-characters"),
                new MockEnvironment().withProperty("spring.profiles.active", "dev"))::validate)
                .doesNotThrowAnyException();

        assertThatCode(new JwtConfigurationValidator(
                properties("test-only-placeholder-not-for-production-at-least-32-characters"),
                new MockEnvironment().withProperty("spring.profiles.active", "test"))::validate)
                .doesNotThrowAnyException();
    }

    private JwtProperties properties(String secret) {
        JwtProperties properties = new JwtProperties();
        properties.setSecret(secret);
        properties.setAccessTokenTtlMinutes(30);
        properties.setRefreshTokenTtlDays(30);
        return properties;
    }
}
