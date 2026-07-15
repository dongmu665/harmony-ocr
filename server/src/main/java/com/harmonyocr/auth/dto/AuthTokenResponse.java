package com.harmonyocr.auth.dto;

import com.harmonyocr.user.dto.UserProfileResponse;

/**
 * 登录和刷新 Token 的响应 DTO，属于 auth 模块。
 * 维护说明：只返回客户端本次需要保存的 Token 字符串，不包含服务端保存的 token_hash。
 */
public record AuthTokenResponse(
        String accessToken,
        String refreshToken,
        String tokenType,
        long expiresIn,
        UserProfileResponse user
) {
}
