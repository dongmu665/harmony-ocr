package com.harmonyocr.ocr.dto;

import java.util.List;

/**
 * 批量 OCR 任务响应，属于 ocr 模块。
 * 维护说明：jobId 是持久化批量任务 ID；响应不暴露本地临时文件或对象存储 key。
 */
public record BatchOcrJobResponse(
        String jobId,
        String status,
        Long recordId,
        int total,
        int completed,
        int failed,
        int progress,
        List<BatchOcrItemResponse> items
) {
}
