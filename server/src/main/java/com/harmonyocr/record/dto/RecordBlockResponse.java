package com.harmonyocr.record.dto;

import java.math.BigDecimal;

/**
 * OCR 文本块响应对象，属于 record 模块。
 * 维护说明：仅在已通过父记录 ownership check 后返回，避免跨用户泄露 OCR 文本块内容。
 */
public record RecordBlockResponse(
        Long id,
        Integer blockIndex,
        String text,
        BigDecimal confidence,
        String boundingBox
) {
}
