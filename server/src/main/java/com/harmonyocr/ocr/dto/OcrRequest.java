package com.harmonyocr.ocr.dto;

/**
 * OCR Provider 请求对象，属于 ocr 模块。
 * 维护说明：只承载本次请求的已校验图片字节、MIME 类型、语言和识别模式；不得写入日志、数据库或长期诊断文件。
 */
public record OcrRequest(
        byte[] content,
        String contentType,
        String language,
        String mode
) {
}
