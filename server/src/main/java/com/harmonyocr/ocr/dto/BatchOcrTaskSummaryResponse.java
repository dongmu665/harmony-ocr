package com.harmonyocr.ocr.dto;

import java.time.Instant;
import java.util.List;

/**
 * 批量 OCR 任务摘要，属于 ocr 模块。
 * 维护说明：该 DTO 用于当前用户读取持久化任务状态，不返回 OCR 结果全文或底层存储信息。
 */
public record BatchOcrTaskSummaryResponse(
        String jobId,
        String status,
        Long recordId,
        int total,
        int completed,
        int failed,
        int progress,
        Instant createdAt,
        List<BatchOcrTaskItemSummaryResponse> items
) {
}
