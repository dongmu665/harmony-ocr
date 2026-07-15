package com.harmonyocr.record.dto;

import jakarta.validation.constraints.Size;
import java.util.List;

/**
 * OCR 历史记录创建请求，属于 record 模块。
 * 维护说明：请求不包含 userId，记录归属只能来自当前登录用户；图片字段只接受对象存储 key。
 */
public record CreateRecordRequest(
        @Size(max = 128) String title,
        String sourceType,
        @Size(max = 512) String imageObjectKey,
        String rawText,
        String editedText,
        @Size(max = 32) String language,
        @Size(max = 64) String ocrEngine,
        Integer durationMs,
        Boolean favorite,
        List<RecordBlockRequest> blocks,
        List<RecordPageRequest> pages
) {
}
