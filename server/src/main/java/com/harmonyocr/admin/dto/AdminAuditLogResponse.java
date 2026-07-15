package com.harmonyocr.admin.dto;

import java.time.LocalDateTime;

/**
 * 管理员审计日志响应，属于 admin 模块。
 * 维护说明：只返回动作、目标类型、目标 ID 和时间，不返回请求体、Token、密码、API Key 或 OCR 文本。
 */
public record AdminAuditLogResponse(
        Long id,
        Long adminUserId,
        String action,
        String targetType,
        Long targetId,
        LocalDateTime createdAt
) {
}
