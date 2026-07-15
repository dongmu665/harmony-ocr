package com.harmonyocr.export.dto;

/**
 * 导出下载对象，属于 export 模块。
 * 维护说明：仅在内存中携带本次任务生成的文件字节和安全文件名，不保存到 Git、日志或长期诊断文件。
 */
public record ExportDownload(
        String fileName,
        String contentType,
        byte[] content
) {
}
