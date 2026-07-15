package com.harmonyocr.testsupport;

/**
 * 测试管理员身份准备响应 DTO，属于 testsupport 模块。
 * 维护说明：仅返回测试用户 ID 和角色名称，不包含认证凭据或任何业务敏感字段。
 */
public record TestSupportAdminSeedResponse(
        Long userId,
        String role
) {
}
