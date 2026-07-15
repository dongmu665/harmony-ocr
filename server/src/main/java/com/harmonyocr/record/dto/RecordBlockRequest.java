package com.harmonyocr.record.dto;

import java.math.BigDecimal;

/**
 * OCR 文本块创建请求，属于 record 模块。
 * 维护说明：boundingBox 保存坐标 JSON 字符串；本阶段只持久化和返回，不执行前端展示或几何计算。
 */
public record RecordBlockRequest(
        Integer blockIndex,
        String text,
        BigDecimal confidence,
        String boundingBox
) {
}
