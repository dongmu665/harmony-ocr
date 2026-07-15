package com.harmonyocr.ocr.dto;

import java.util.List;

/**
 * PDF 单页 OCR 结果，属于 ocr 模块。
 * 维护说明：失败页只返回脱敏错误码和短文案，不包含 PDF 路径、对象 key 或内部异常堆栈。
 */
public record PdfOcrPageResult(
        int pageIndex,
        int pageNumber,
        String status,
        String rawText,
        String editedText,
        long durationMs,
        Double confidence,
        String errorCode,
        String failureReason,
        String previewImageBase64,
        String previewContentType,
        List<OcrTextBlockResponse> blocks
) {
}
