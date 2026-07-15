package com.harmonyocr.record.dto;

import java.util.List;

/**
 * PDF 历史页创建请求，属于 record 模块。
 * 维护说明：仅承载 OCR 后端生成的页级结果，调用方不得填入本地路径、URI 或对象存储 key。
 */
public record RecordPageRequest(
        Integer pageIndex,
        Integer pageNumber,
        String status,
        String rawText,
        String editedText,
        Integer durationMs,
        Double confidence,
        String errorCode,
        String failureReason,
        List<RecordBlockRequest> blocks
) {
}
