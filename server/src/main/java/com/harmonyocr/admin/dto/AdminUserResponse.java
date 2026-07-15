package com.harmonyocr.admin.dto;

import java.time.LocalDateTime;

/**
 * 管理后台用户响应 DTO，属于 admin 模块。
 * 维护说明：不得包含 passwordHash、Token、API Key 或其他认证敏感字段。
 */
public record AdminUserResponse(
        Long id,
        String username,
        String status,
        LocalDateTime createdAt,
        String membershipLevel) {
}
