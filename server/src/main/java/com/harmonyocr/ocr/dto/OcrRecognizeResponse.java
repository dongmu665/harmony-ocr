package com.harmonyocr.ocr.dto;

import java.util.List;

/**
 * OCR 识别响应，属于 ocr 模块。
 * 维护说明：rawText/editedText 只通过 API 返回给当前认证用户，服务端不得把全文写入日志或长期诊断文件。
 */
public record OcrRecognizeResponse(
        String rawText,
        String editedText,
        long durationMs,
        String language,
        String ocrEngine,
        String providerName,
        String engineName,
        String mode,
        Double confidence,
        String boundingBox,
        String errorCode,
        List<OcrTextBlockResponse> blocks
) {
}
