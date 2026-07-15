package com.harmonyocr.testsupport;

/**
 * 测试额度耗尽响应，属于 testsupport 模块。
 * 维护说明：只返回资源类型、额度与使用量，避免暴露 Token、密码、API Key、OCR 文本或用户隐私内容。
 */
public record TestSupportQuotaExhaustResponse(
        Long userId,
        String resourceType,
        int quota,
        int usedCount
) {
}
