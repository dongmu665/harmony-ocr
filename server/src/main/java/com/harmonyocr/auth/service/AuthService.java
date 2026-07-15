package com.harmonyocr.auth.service;

import com.harmonyocr.auth.dto.AuthTokenResponse;
import com.harmonyocr.auth.dto.LoginRequest;
import com.harmonyocr.auth.dto.LogoutRequest;
import com.harmonyocr.auth.dto.RefreshTokenRequest;
import com.harmonyocr.auth.dto.RegisterRequest;
import com.harmonyocr.auth.entity.RefreshTokenEntity;
import com.harmonyocr.auth.security.JwtService;
import com.harmonyocr.auth.security.RefreshTokenService;
import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.device.service.UserDeviceService;
import com.harmonyocr.user.dto.UserProfileResponse;
import com.harmonyocr.user.entity.UserEntity;
import com.harmonyocr.user.entity.UserStatus;
import com.harmonyocr.user.mapper.UserMapper;
import com.harmonyocr.user.service.UserService;
import java.time.LocalDateTime;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 认证业务服务，属于 auth 模块。
 * 维护说明：集中处理注册、登录、刷新和退出登录规则，控制器不得绕过该服务直接操作认证表。
 */
@Service
public class AuthService {

    private final UserMapper userMapper;
    private final UserService userService;
    private final UserDeviceService userDeviceService;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;
    private final RefreshTokenService refreshTokenService;

    public AuthService(
            UserMapper userMapper,
            UserService userService,
            UserDeviceService userDeviceService,
            PasswordEncoder passwordEncoder,
            JwtService jwtService,
            RefreshTokenService refreshTokenService) {
        this.userMapper = userMapper;
        this.userService = userService;
        this.userDeviceService = userDeviceService;
        this.passwordEncoder = passwordEncoder;
        this.jwtService = jwtService;
        this.refreshTokenService = refreshTokenService;
    }

    /**
     * 注册用户账号。
     * 参数包含用户名、明文密码和可选昵称；返回脱敏用户资料。密码会使用 BCrypt 后再入库。
     */
    @Transactional
    public UserProfileResponse register(RegisterRequest request) {
        if (userService.findByUsername(request.username()) != null) {
            throw new BusinessException(ErrorCode.USERNAME_ALREADY_EXISTS);
        }
        UserEntity user = new UserEntity();
        user.setUsername(request.username());
        user.setPasswordHash(passwordEncoder.encode(request.password()));
        user.setNickname(request.nickname());
        user.setStatus(UserStatus.ACTIVE.name());
        user.setCreatedAt(LocalDateTime.now());
        user.setUpdatedAt(LocalDateTime.now());
        try {
            userMapper.insert(user);
        } catch (DuplicateKeyException ex) {
            throw new BusinessException(ErrorCode.USERNAME_ALREADY_EXISTS);
        }
        return userService.toProfile(user);
    }

    /**
     * 用户登录并签发 Token。
     * 参数为用户名、密码和可选设备信息；返回 Access Token、Refresh Token 和用户资料。
     * 安全注意：用户不存在和密码错误统一返回相同错误码，避免用户枚举。
     */
    @Transactional
    public AuthTokenResponse login(LoginRequest request) {
        UserEntity user = userService.findByUsername(request.username());
        if (user == null || !passwordEncoder.matches(request.password(), user.getPasswordHash())) {
            throw new BusinessException(ErrorCode.AUTH_INVALID_CREDENTIALS);
        }
        if (UserStatus.DISABLED.name().equals(user.getStatus())) {
            throw new BusinessException(ErrorCode.ACCOUNT_DISABLED);
        }
        if (UserStatus.DELETED.name().equals(user.getStatus())) {
            throw new BusinessException(ErrorCode.ACCOUNT_DELETED);
        }
        if (!UserStatus.ACTIVE.name().equals(user.getStatus())) {
            throw new BusinessException(ErrorCode.AUTH_INVALID_CREDENTIALS);
        }
        user.setLastLoginAt(LocalDateTime.now());
        userMapper.updateById(user);
        userDeviceService.recordLoginDevice(user.getId(), request.deviceId(), request.deviceName());
        return tokenResponse(user, request.deviceId());
    }

    /**
     * 刷新 Access Token 并轮换 Refresh Token。
     * 参数为客户端提交的 Refresh Token；返回新的 Token 响应。旧 Token 必须先条件撤销成功，才允许签发新 Token。
     */
    @Transactional
    public AuthTokenResponse refresh(RefreshTokenRequest request) {
        RefreshTokenEntity oldToken = refreshTokenService.findByRawToken(request.refreshToken());
        if (oldToken == null) {
            throw new BusinessException(ErrorCode.AUTH_REFRESH_TOKEN_INVALID);
        }
        if (oldToken.getRevokedAt() != null) {
            throw new BusinessException(ErrorCode.AUTH_TOKEN_REVOKED);
        }
        if (oldToken.getExpiresAt().isBefore(LocalDateTime.now())) {
            throw new BusinessException(ErrorCode.AUTH_REFRESH_TOKEN_EXPIRED);
        }
        UserEntity user = userService.findById(oldToken.getUserId());
        if (user == null) {
            throw new BusinessException(ErrorCode.AUTH_INVALID_CREDENTIALS);
        }
        if (UserStatus.DELETED.name().equals(user.getStatus())) {
            throw new BusinessException(ErrorCode.ACCOUNT_DELETED);
        }
        if (!UserStatus.ACTIVE.name().equals(user.getStatus())) {
            throw new BusinessException(ErrorCode.AUTH_INVALID_CREDENTIALS);
        }
        if (!refreshTokenService.revokeIfActive(oldToken)) {
            throw new BusinessException(ErrorCode.AUTH_TOKEN_REVOKED);
        }
        return tokenResponse(user, oldToken.getDeviceId());
    }

    /**
     * 退出登录并撤销传入的 Refresh Token。
     * 参数包含当前认证用户 ID 和可选 Refresh Token；为空时直接成功返回。
     * 安全注意：只撤销归属于当前用户的 Token，避免攻击者用自己的 Access Token 撤销其他用户会话。
     */
    @Transactional
    public void logout(Long currentUserId, LogoutRequest request) {
        if (request == null || request.refreshToken() == null || request.refreshToken().isBlank()) {
            return;
        }
        RefreshTokenEntity token = refreshTokenService.findByRawToken(request.refreshToken());
        if (token != null && currentUserId.equals(token.getUserId()) && token.getRevokedAt() == null) {
            refreshTokenService.revoke(token);
        }
    }

    /**
     * 生成认证响应。
     * 参数为已认证用户和可选设备 ID；返回 Access Token、明文 Refresh Token 和用户资料。
     */
    private AuthTokenResponse tokenResponse(UserEntity user, String deviceId) {
        String accessToken = jwtService.generateAccessToken(user.getId(), user.getUsername());
        RefreshTokenService.IssuedRefreshToken refreshToken = refreshTokenService.issue(user.getId(), deviceId);
        return new AuthTokenResponse(
                accessToken,
                refreshToken.rawToken(),
                "Bearer",
                jwtService.accessTokenTtlSeconds(),
                userService.toProfile(user));
    }
}
