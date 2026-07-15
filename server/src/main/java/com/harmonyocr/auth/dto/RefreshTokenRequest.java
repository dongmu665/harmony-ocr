package com.harmonyocr.auth.dto;

import jakarta.validation.constraints.NotBlank;

/**
 * 刷新 Token 请求 DTO，属于 auth 模块。
 * 维护说明：Refresh Token 只在请求中短暂使用，数据库仅保存其哈希值。
 */
public record RefreshTokenRequest(
        @NotBlank
        String refreshToken
) {
}
