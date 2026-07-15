package com.harmonyocr.ocr.dto;

import java.util.List;

/**
 * PDF OCR 聚合响应，属于 ocr 模块。
 * 维护说明：rawText 仅由成功页按页序拼接；partial=true 表示至少一页失败且至少一页成功。
 */
public record PdfOcrRecognizeResponse(
        String rawText,
        String editedText,
        int pageCount,
        int successPageCount,
        int failedPageCount,
        long durationMs,
        String language,
        String providerName,
        String engineName,
        String mode,
        List<PdfOcrPageResult> pages,
        String errorCode,
        boolean partial,
        Long recordId
) {
}
