package com.harmonyocr.auth.dto;

/**
 * 退出登录请求 DTO，属于 auth 模块。
 * 维护说明：refreshToken 可为空，服务端应保持退出接口幂等。
 */
public record LogoutRequest(
        String refreshToken
) {
}
