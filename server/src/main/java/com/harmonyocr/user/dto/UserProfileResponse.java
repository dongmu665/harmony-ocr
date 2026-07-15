package com.harmonyocr.user.dto;

import java.time.LocalDateTime;

/**
 * 用户基础资料响应 DTO，属于 user 模块。
 * 维护说明：对外响应不得包含 password_hash、Refresh Token 哈希或其他认证敏感字段。
 */
public record UserProfileResponse(
        Long id,
        String username,
        String nickname,
        String avatarUrl,
        String status,
        LocalDateTime createdAt,
        LocalDateTime lastLoginAt
) {
}
