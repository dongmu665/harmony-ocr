package com.harmonyocr.testsupport;

/**
 * 测试额度耗尽请求，属于 testsupport 模块。
 * 维护说明：该 DTO 仅在 test profile 中使用，用于构造模拟器额度超限状态，不携带任何敏感凭据。
 */
public record TestSupportQuotaExhaustRequest(
        String resourceType
) {
}
