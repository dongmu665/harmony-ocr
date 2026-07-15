package com.harmonyocr.ocr.dto;

/**
 * OCR 文本块响应，属于 ocr 模块。
 * 维护说明：boundingBox 仅在真实 Provider 返回坐标时填写；不得为展示效果伪造位置。
 */
public record OcrTextBlockResponse(
        Integer order,
        String text,
        Double confidence,
        String boundingBox
) {
}
