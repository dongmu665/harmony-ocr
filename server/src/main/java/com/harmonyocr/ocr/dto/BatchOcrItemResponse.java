package com.harmonyocr.ocr.dto;

/**
 * 批量 OCR 单项响应，属于 ocr 模块。
 * 维护说明：failureReason 必须使用脱敏短消息，不返回堆栈、图片路径、Token、对象 key 或 OCR 全文日志。
 */
public record BatchOcrItemResponse(
        int itemIndex,
        String fileName,
        BatchOcrItemStatus status,
        OcrRecognizeResponse result,
        Long recordId,
        String errorCode,
        String failureReason
) {
}
