package com.harmonyocr.record.dto;

/**
 * OCR 历史高级查询条件，属于 record 模块。
 * 维护说明：该对象只承载白名单筛选参数，sort 在 service 层解析，禁止拼接未校验字段名。
 */
public record RecordSearchQuery(
        Integer page,
        Integer size,
        Boolean favorite,
        String sourceType,
        String keyword,
        String createdFrom,
        String createdTo,
        String dateFrom,
        String dateTo,
        Long tagId,
        String ocrEngine,
        String sort
) {
}
