package com.harmonyocr.auth.security;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * JWT 配置属性，属于 auth security 模块。
 * 维护说明：密钥和有效期必须来自 app.jwt.* 配置，生产环境应由环境变量或密钥系统提供。
 */
@ConfigurationProperties(prefix = "app.jwt")
public class JwtProperties {

    private String secret;
    private long accessTokenTtlMinutes = 30;
    private long refreshTokenTtlDays = 30;

    public String getSecret() {
        return secret;
    }

    public void setSecret(String secret) {
        this.secret = secret;
    }

    public long getAccessTokenTtlMinutes() {
        return accessTokenTtlMinutes;
    }

    public void setAccessTokenTtlMinutes(long accessTokenTtlMinutes) {
        this.accessTokenTtlMinutes = accessTokenTtlMinutes;
    }

    public long getRefreshTokenTtlDays() {
        return refreshTokenTtlDays;
    }

    public void setRefreshTokenTtlDays(long refreshTokenTtlDays) {
        this.refreshTokenTtlDays = refreshTokenTtlDays;
    }
}
