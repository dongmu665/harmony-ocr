package com.harmonyocr.export.dto;

/**
 * 导出格式枚举，属于 export 模块。
 * 维护说明：枚举只包含已审计的文档导出格式，不混入 AI 或表格识别能力。
 */
public enum ExportFormat {
    TXT,
    MARKDOWN,
    JSON,
    PDF,
    SEARCHABLE_PDF
}
