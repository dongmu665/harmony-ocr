package com.harmonyocr.record.dto;

import java.util.List;

/**
 * PDF 历史页响应，属于 record 模块。
 * 维护说明：failureReason 为面向产品的脱敏短文案，不暴露底层异常、文件路径或对象 key。
 */
public record RecordPageResponse(
        Long id,
        Integer pageIndex,
        Integer pageNumber,
        String status,
        String rawText,
        String editedText,
        Integer durationMs,
        Double confidence,
        String errorCode,
        String failureReason,
        List<RecordBlockResponse> blocks
) {
}
