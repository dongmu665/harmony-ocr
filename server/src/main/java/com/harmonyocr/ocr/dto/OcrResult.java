package com.harmonyocr.ocr.dto;

import java.util.List;

/**
 * OCR Provider 统一结果对象，属于 ocr 模块。
 * 维护说明：Provider 只能填写真正返回的置信度、识别框和错误码；缺失字段保持 null，避免把推断值伪装成引擎输出。
 */
public record OcrResult(
        String providerName,
        String engineName,
        String mode,
        String rawText,
        long durationMs,
        String language,
        Double confidence,
        String boundingBox,
        List<OcrTextBlockResponse> blocks,
        String errorCode
) {
}
