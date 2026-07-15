package com.harmonyocr.ocr.dto;

/**
 * 批量 OCR 单项摘要，属于 ocr 模块。
 * 维护说明：摘要只服务于任务列表和首页状态，不返回 OCR 全文、图片路径、Token 或对象存储 key。
 */
public record BatchOcrTaskItemSummaryResponse(
        int itemIndex,
        String fileName,
        BatchOcrItemStatus status,
        Long recordId,
        String errorCode,
        String failureReason
) {
}
