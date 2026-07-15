package com.harmonyocr.testsupport;

import java.util.List;

/**
 * V2.0 UI 仪表盘测试数据种子响应，属于 testsupport 模块。
 * 维护说明：仅返回当前测试用户下创建的数据数量和内部 ID，不返回密码、Token、objectKey、OCR 原文或导出文件内容。
 */
public record TestSupportDashboardSeedResponse(
        int recordCount,
        int batchJobCount,
        int exportJobCount,
        List<Long> recordIds,
        List<String> batchJobIds,
        List<String> exportJobIds
) {
}
