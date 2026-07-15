package com.harmonyocr.admin.dto;

import java.time.LocalDateTime;

/**
 * 管理后台记录响应 DTO，属于 admin 模块。
 * 维护说明：只返回记录元数据和文本长度，不返回 OCR 原文、编辑全文或 objectKey。
 */
public record AdminRecordResponse(
        Long id,
        Long userId,
        String title,
        String sourceType,
        int textLength,
        LocalDateTime createdAt) {
}
