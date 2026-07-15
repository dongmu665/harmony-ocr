package com.harmonyocr.ocr.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * 扫描型 PDF OCR 配置，属于 ocr 模块。
 * 维护说明：这些限制用于约束上传大小、页数和渲染像素，避免 PDF 输入绕过图片 OCR 的内存与额度边界。
 */
@ConfigurationProperties(prefix = "app.ocr.pdf")
public record PdfOcrProperties(
        long maxSizeBytes,
        int maxPages,
        int renderDpi,
        long maxRenderedPixels,
        boolean allowEncrypted
) {

    public PdfOcrProperties {
        if (maxSizeBytes <= 0) {
            maxSizeBytes = 10 * 1024 * 1024L;
        }
        if (maxPages <= 0) {
            maxPages = 20;
        }
        if (renderDpi <= 0) {
            renderDpi = 200;
        }
        if (maxRenderedPixels <= 0) {
            maxRenderedPixels = 20_000_000L;
        }
    }
}
