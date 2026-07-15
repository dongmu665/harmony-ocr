package com.harmonyocr.ocr.dto;

/**
 * OCR Provider 健康状态响应，属于 ocr 模块。
 * 维护说明：只暴露 Provider 是否可用和引擎名称，不输出本机路径、命令行参数或临时文件位置。
 */
public record OcrHealthResponse(
        boolean available,
        String ocrEngine
) {
}
