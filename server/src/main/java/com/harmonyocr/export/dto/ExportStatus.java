package com.harmonyocr.export.dto;

/**
 * 导出任务状态枚举，属于 export 模块。
 * 维护说明：状态只描述当前导出任务生命周期，不包含文件路径、对象存储 key 或 OCR 原文。
 */
public enum ExportStatus {
    PENDING,
    RUNNING,
    CANCELED,
    SUCCESS,
    FAILED
}
