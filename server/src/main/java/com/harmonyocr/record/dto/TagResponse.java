package com.harmonyocr.record.dto;

import java.time.LocalDateTime;

/**
 * OCR 历史标签响应对象，属于 record 模块。
 * 维护说明：仅返回当前用户拥有的标签元信息，不返回 normalizedName 或内部归属字段。
 */
public record TagResponse(
        Long id,
        String name,
        String color,
        LocalDateTime createdAt,
        LocalDateTime updatedAt
) {
}
