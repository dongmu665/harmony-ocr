package com.harmonyocr.auth.security;

/**
 * 当前认证用户主体，属于 auth security 模块。
 * 维护说明：仅保存用户 ID 和用户名，避免把密码哈希、Token 或敏感资料放入 SecurityContext。
 */
public record CurrentUser(
        Long userId,
        String username
) {
}
