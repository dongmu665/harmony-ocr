package com.harmonyocr.user.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.user.dto.ChangePasswordRequest;
import com.harmonyocr.user.dto.UpdateCurrentUserRequest;
import com.harmonyocr.user.dto.UserProfileResponse;
import com.harmonyocr.user.entity.UserEntity;
import com.harmonyocr.user.entity.UserStatus;
import com.harmonyocr.user.mapper.UserMapper;
import java.time.LocalDateTime;
import java.util.UUID;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 用户资料服务，属于 user 模块。
 * 维护说明：负责用户查询和对外资料转换，必须避免把密码哈希或 Token 哈希放入响应。
 */
@Service
public class UserService {

    private final UserMapper userMapper;
    private final UserDataDeletionService userDataDeletionService;
    private final PasswordEncoder passwordEncoder;

    public UserService(
            UserMapper userMapper,
            UserDataDeletionService userDataDeletionService,
            PasswordEncoder passwordEncoder) {
        this.userMapper = userMapper;
        this.userDataDeletionService = userDataDeletionService;
        this.passwordEncoder = passwordEncoder;
    }

    /**
     * 按用户 ID 查询用户实体。
     * 参数为认证上下文或业务层传入的用户 ID；返回数据库用户实体，未找到时返回 null。
     * 安全注意：调用方不得把 passwordHash 等敏感字段直接返回给客户端。
     */
    public UserEntity findById(Long id) {
        return userMapper.selectById(id);
    }

    /**
     * 按用户名查询用户实体。
     * 参数为登录名；返回数据库用户实体或 null。调用方不得把 passwordHash 返回给客户端。
     */
    public UserEntity findByUsername(String username) {
        return userMapper.selectOne(new LambdaQueryWrapper<UserEntity>()
                .eq(UserEntity::getUsername, username));
    }

    /**
     * 查询当前用户资料。
     * 参数为认证上下文中的用户 ID；返回脱敏用户资料，用户不存在时抛出业务异常。
     */
    public UserProfileResponse currentUserProfile(Long userId) {
        UserEntity user = findById(userId);
        if (user == null) {
            throw new BusinessException(ErrorCode.USER_NOT_FOUND);
        }
        return toProfile(user);
    }

    /**
     * 更新当前用户低敏资料。
     * 参数为认证上下文中的用户 ID 和更新请求；返回更新后的脱敏资料。
     * 安全注意：该方法不允许修改 username/status/passwordHash/Token，避免资料接口越权改变认证状态。
     */
    @Transactional
    public UserProfileResponse updateCurrentUserProfile(Long userId, UpdateCurrentUserRequest request) {
        UserEntity user = activeUser(userId);
        LocalDateTime now = LocalDateTime.now();
        user.setNickname(blankToNull(request.nickname()));
        user.setAvatarUrl(blankToNull(request.avatarUrl()));
        user.setUpdatedAt(now);
        userMapper.updateById(user);
        return toProfile(user);
    }

    /**
     * 修改当前用户密码。
     * 参数为认证用户 ID 和密码请求；当前密码错误时统一返回认证失败，避免泄露密码校验细节。
     * 安全注意：只保存 BCrypt 哈希，不返回或记录任何明文密码。
     */
    @Transactional
    public void changePassword(Long userId, ChangePasswordRequest request) {
        UserEntity user = activeUser(userId);
        if (!passwordEncoder.matches(request.currentPassword(), user.getPasswordHash())) {
            throw new BusinessException(ErrorCode.AUTH_INVALID_CREDENTIALS);
        }
        user.setPasswordHash(passwordEncoder.encode(request.newPassword()));
        user.setUpdatedAt(LocalDateTime.now());
        userMapper.updateById(user);
    }

    /**
     * 注销当前登录用户账号。
     * 参数为 SecurityContext 中确认的当前用户 ID；方法不返回用户资料，避免在注销响应中泄露敏感字段。
     * 可能抛出 USER_NOT_FOUND 或 ACCOUNT_DELETED 业务异常。安全注意：注销会匿名化 username、清空 PII、替换 password_hash，并清理设备、Refresh Token 和业务隐私数据，
     * 并将用户状态改为 DELETED，使旧 Access Token 在下一次受保护接口访问时被 JWT 过滤器拒绝。
     */
    @Transactional
    public void deleteCurrentUser(Long userId) {
        UserEntity user = findById(userId);
        if (user == null) {
            throw new BusinessException(ErrorCode.USER_NOT_FOUND);
        }
        if (UserStatus.DELETED.name().equals(user.getStatus())) {
            throw new BusinessException(ErrorCode.ACCOUNT_DELETED);
        }

        LocalDateTime now = LocalDateTime.now();
        userDataDeletionService.deleteUserOwnedData(userId);

        int updated = userMapper.update(null, new LambdaUpdateWrapper<UserEntity>()
                .eq(UserEntity::getId, userId)
                .set(UserEntity::getUsername, anonymizedUsername(userId))
                .set(UserEntity::getEmail, null)
                .set(UserEntity::getPhone, null)
                .set(UserEntity::getNickname, null)
                .set(UserEntity::getAvatarUrl, null)
                .set(UserEntity::getPasswordHash, passwordEncoder.encode(UUID.randomUUID().toString()))
                .set(UserEntity::getLastLoginAt, null)
                .set(UserEntity::getStatus, UserStatus.DELETED.name())
                .set(UserEntity::getDeletedAt, now)
                .set(UserEntity::getUpdatedAt, now));
        if (updated == 0) {
            throw new BusinessException(ErrorCode.USER_NOT_FOUND);
        }
    }

    /**
     * 将用户实体转换为对外响应。
     * 参数为用户实体；返回不包含 passwordHash、Refresh Token hash 的基础资料。
     */
    public UserProfileResponse toProfile(UserEntity user) {
        return new UserProfileResponse(
                user.getId(),
                user.getUsername(),
                user.getNickname(),
                user.getAvatarUrl(),
                user.getStatus(),
                user.getCreatedAt(),
                user.getLastLoginAt());
    }

    private UserEntity activeUser(Long userId) {
        UserEntity user = findById(userId);
        if (user == null) {
            throw new BusinessException(ErrorCode.USER_NOT_FOUND);
        }
        if (UserStatus.DELETED.name().equals(user.getStatus())) {
            throw new BusinessException(ErrorCode.ACCOUNT_DELETED);
        }
        if (UserStatus.DISABLED.name().equals(user.getStatus())) {
            throw new BusinessException(ErrorCode.ACCOUNT_DISABLED);
        }
        return user;
    }

    private String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.trim();
    }

    private String anonymizedUsername(Long userId) {
        return "deleted_user_%d_%s".formatted(userId, UUID.randomUUID().toString().replace("-", "").substring(0, 12));
    }
}
