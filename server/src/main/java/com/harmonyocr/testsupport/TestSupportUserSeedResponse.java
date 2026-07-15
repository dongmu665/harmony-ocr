package com.harmonyocr.testsupport;

/**
 * 测试用户准备响应，属于 testsupport 模块。
 * 维护说明：响应只返回用户元数据，不包含 password、passwordHash、Token 或 Refresh Token。
 */
public record TestSupportUserSeedResponse(
        Long id,
        String username,
        String status
) {
}
