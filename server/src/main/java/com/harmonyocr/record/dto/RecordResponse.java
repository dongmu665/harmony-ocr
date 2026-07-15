package com.harmonyocr.record.dto;

import java.time.LocalDateTime;
import java.util.List;

/**
 * OCR 历史记录响应对象，属于 record 模块。
 * 维护说明：仅返回当前用户有权访问的记录信息，不暴露内部删除标记，也不包含任何密钥或 Token。
 */
public record RecordResponse(
        Long id,
        String title,
        String sourceType,
        String imageObjectKey,
        String rawText,
        String editedText,
        String language,
        String ocrEngine,
        Integer durationMs,
        Boolean favorite,
        LocalDateTime createdAt,
        LocalDateTime updatedAt,
        LocalDateTime deletedAt,
        List<RecordBlockResponse> blocks,
        List<TagResponse> tags,
        List<RecordPageResponse> pages,
        Integer pageCount,
        Integer successPageCount,
        Integer failedPageCount,
        Boolean partial
) {
}
