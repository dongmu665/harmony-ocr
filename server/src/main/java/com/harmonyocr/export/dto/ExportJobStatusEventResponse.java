package com.harmonyocr.export.dto;

import java.time.Instant;

/**
 * 导出任务状态事件响应，属于 export 模块。
 * 维护说明：仅暴露任务状态、进度和时间戳，用于审计本地队列生命周期；不包含文件内容、存储路径或对象存储 key。
 */
public record ExportJobStatusEventResponse(
        ExportStatus status,
        int progress,
        Instant createdAt
) {
}
