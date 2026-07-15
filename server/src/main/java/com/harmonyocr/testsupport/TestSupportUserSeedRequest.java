package com.harmonyocr.testsupport;

/**
 * 测试用户准备请求，属于 testsupport 模块。
 * 维护说明：仅在 test profile 使用；明文密码只用于本地 BCrypt 写入，不会返回给调用方。
 */
public record TestSupportUserSeedRequest(
        String username,
        String password
) {
}
