package com.harmonyocr.export.dto;

import java.time.Instant;
import java.util.List;

/**
 * 导出任务响应，属于 export 模块。
 * 维护说明：响应只暴露前端需要的任务状态、格式、下载入口和降级说明，不返回磁盘路径或对象存储 key。
 */
public record ExportJobResponse(
        String jobId,
        ExportStatus status,
        ExportFormat format,
        String fileName,
        String contentType,
        long sizeBytes,
        int progress,
        String checksumSha256,
        boolean searchable,
        boolean degraded,
        String downgradeReason,
        String downloadPath,
        Instant createdAt,
        List<ExportJobStatusEventResponse> statusHistory
) {
}
