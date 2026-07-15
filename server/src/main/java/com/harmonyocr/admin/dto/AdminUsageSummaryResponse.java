package com.harmonyocr.admin.dto;

/**
 * 管理后台用量汇总 DTO，属于 admin 模块。
 * 维护说明：返回聚合计数，不包含用户 OCR 文本、文件 key、API Key 或原始调用日志。
 */
public record AdminUsageSummaryResponse(
        int totalUsers,
        int totalRecords,
        int totalFeedback,
        int ocrUsed,
        int aiUsed,
        int exportUsed) {
}
