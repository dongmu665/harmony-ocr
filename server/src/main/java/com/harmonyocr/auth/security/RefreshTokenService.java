package com.harmonyocr.auth.security;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.harmonyocr.auth.entity.RefreshTokenEntity;
import com.harmonyocr.auth.mapper.RefreshTokenMapper;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.LocalDateTime;
import java.util.Base64;
import org.springframework.stereotype.Service;

/**
 * Refresh Token 服务，属于 auth security 模块。
 * 维护说明：负责生成随机 Refresh Token、哈希入库、查询和撤销；数据库禁止保存明文 Token。
 */
@Service
public class RefreshTokenService {

    private static final SecureRandom SECURE_RANDOM = new SecureRandom();

    private final RefreshTokenMapper refreshTokenMapper;
    private final JwtProperties jwtProperties;

    public RefreshTokenService(RefreshTokenMapper refreshTokenMapper, JwtProperties jwtProperties) {
        this.refreshTokenMapper = refreshTokenMapper;
        this.jwtProperties = jwtProperties;
    }

    /**
     * 签发新的 Refresh Token。
     * 参数为用户 ID 和可选设备 ID；返回明文 Token 仅用于本次响应，数据库只保存 SHA-256 哈希。
     */
    public IssuedRefreshToken issue(Long userId, String deviceId) {
        String rawToken = generateRawToken();
        RefreshTokenEntity entity = new RefreshTokenEntity();
        entity.setUserId(userId);
        entity.setTokenHash(hash(rawToken));
        entity.setDeviceId(deviceId);
        entity.setExpiresAt(LocalDateTime.now().plusDays(jwtProperties.getRefreshTokenTtlDays()));
        entity.setCreatedAt(LocalDateTime.now());
        refreshTokenMapper.insert(entity);
        return new IssuedRefreshToken(rawToken, entity);
    }

    /**
     * 按明文 Refresh Token 查找对应记录。
     * 参数为客户端提交的 Token；查询前会先计算哈希，避免用明文 Token 访问数据库。
     */
    public RefreshTokenEntity findByRawToken(String rawToken) {
        return refreshTokenMapper.selectOne(new LambdaQueryWrapper<RefreshTokenEntity>()
                .eq(RefreshTokenEntity::getTokenHash, hash(rawToken)));
    }

    /**
     * 撤销指定 Refresh Token 记录。
     * 参数为数据库实体；方法只写入 revokedAt，不删除记录，便于识别已撤销 Token。
     */
    public void revoke(RefreshTokenEntity entity) {
        entity.setRevokedAt(LocalDateTime.now());
        refreshTokenMapper.updateById(entity);
    }

    /**
     * 条件撤销尚未撤销的 Refresh Token。
     * 参数为数据库实体；返回是否成功更新。安全注意：用于 refresh rotation，避免并发请求重复签发新 Token。
     */
    public boolean revokeIfActive(RefreshTokenEntity entity) {
        int updated = refreshTokenMapper.update(null, new LambdaUpdateWrapper<RefreshTokenEntity>()
                .eq(RefreshTokenEntity::getId, entity.getId())
                .isNull(RefreshTokenEntity::getRevokedAt)
                .set(RefreshTokenEntity::getRevokedAt, LocalDateTime.now()));
        return updated == 1;
    }

    /**
     * 批量撤销指定用户的所有未撤销 Refresh Token。
     * 参数为当前登录用户 ID；返回本次写入 revokedAt 的记录数。账号注销必须调用该方法，使所有设备上的会话失效。
     * 安全注意：仅按服务端认证上下文确认的 userId 操作，不接受客户端传入的任意用户 ID。
     */
    public int revokeAllByUserId(Long userId) {
        return refreshTokenMapper.update(null, new LambdaUpdateWrapper<RefreshTokenEntity>()
                .eq(RefreshTokenEntity::getUserId, userId)
                .isNull(RefreshTokenEntity::getRevokedAt)
                .set(RefreshTokenEntity::getRevokedAt, LocalDateTime.now()));
    }

    /**
     * 物理删除指定用户的全部 Refresh Token。
     * 参数为账号注销流程传入的用户 ID；返回删除行数。安全注意：注销后不再保留 token_hash，旧 Refresh Token 只能按无效 Token 处理。
     */
    public int deleteAllByUserId(Long userId) {
        return refreshTokenMapper.delete(new LambdaQueryWrapper<RefreshTokenEntity>()
                .eq(RefreshTokenEntity::getUserId, userId));
    }

    /**
     * 计算 Refresh Token 的 SHA-256 十六进制哈希。
     * 参数为明文 Token；返回固定长度哈希。该方法不得记录输入值，避免泄露 Token。
     */
    public String hash(String rawToken) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hashed = digest.digest(rawToken.getBytes(StandardCharsets.UTF_8));
            StringBuilder builder = new StringBuilder();
            for (byte value : hashed) {
                builder.append(String.format("%02x", value));
            }
            return builder.toString();
        } catch (NoSuchAlgorithmException ex) {
            throw new IllegalStateException("SHA-256 is unavailable", ex);
        }
    }

    /**
     * 生成高熵 URL-safe Refresh Token。
     * 返回值只交给调用方一次性返回客户端，不应写入日志或数据库明文字段。
     */
    private String generateRawToken() {
        byte[] bytes = new byte[48];
        SECURE_RANDOM.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    /**
     * Refresh Token 签发结果，属于 auth security 模块。
     * 维护说明：rawToken 仅用于响应客户端，entity 包含已入库的哈希记录。
     */
    public record IssuedRefreshToken(String rawToken, RefreshTokenEntity entity) {
    }
}
