package com.harmonyocr.auth.security;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Date;
import javax.crypto.SecretKey;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

/**
 * JWT Access Token 服务，属于 auth security 模块。
 * 维护说明：只从 app.jwt.* 读取签名配置，负责签发和解析 Access Token，不处理 Refresh Token。
 */
@Service
public class JwtService {

    private final JwtProperties properties;
    private final SecretKey signingKey;

    /**
     * 初始化 JWT 签名服务并校验密钥强度。
     * 参数为 app.jwt.* 配置属性；当 secret 缺失或长度不足时抛出 IllegalStateException。
     * 安全注意：签名密钥只能来自配置，不允许在代码中硬编码生产密钥。
     */
    public JwtService(JwtProperties properties) {
        this.properties = properties;
        if (!StringUtils.hasText(properties.getSecret())
                || properties.getSecret().getBytes(StandardCharsets.UTF_8).length < 32) {
            throw new IllegalStateException("app.jwt.secret must be configured with at least 32 bytes");
        }
        this.signingKey = Keys.hmacShaKeyFor(properties.getSecret().getBytes(StandardCharsets.UTF_8));
    }

    /**
     * 为指定用户签发短期 Access Token。
     * 参数为用户 ID 和用户名；返回 JWT 字符串。安全注意：JWT secret 只来自配置，不在代码中硬编码。
     */
    public String generateAccessToken(Long userId, String username) {
        Instant issuedAt = Instant.now();
        Instant expiresAt = issuedAt.plusSeconds(accessTokenTtlSeconds());
        return Jwts.builder()
                .subject(username)
                .claim("userId", userId)
                .claim("username", username)
                .issuedAt(Date.from(issuedAt))
                .expiration(Date.from(expiresAt))
                .signWith(signingKey)
                .compact();
    }

    /**
     * 解析并校验 Access Token。
     * 参数为 Bearer 之后的 JWT 字符串；返回当前用户主体。Token 无效或过期时由 JJWT 抛出异常。
     */
    public CurrentUser parseAccessToken(String token) {
        Claims claims = Jwts.parser()
                .verifyWith(signingKey)
                .build()
                .parseSignedClaims(token)
                .getPayload();
        Long userId = claims.get("userId", Number.class).longValue();
        String username = claims.get("username", String.class);
        return new CurrentUser(userId, username);
    }

    /**
     * 返回 Access Token 有效期秒数。
     * 返回值来自配置分钟数换算，供接口响应中的 expiresIn 使用。
     */
    public long accessTokenTtlSeconds() {
        return properties.getAccessTokenTtlMinutes() * 60;
    }
}
