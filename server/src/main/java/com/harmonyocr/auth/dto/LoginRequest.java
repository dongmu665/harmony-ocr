package com.harmonyocr.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 登录请求 DTO，属于 auth 模块。
 * 维护说明：密码字段只用于本次认证校验，禁止写入日志或原样持久化。
 */
public record LoginRequest(
        @NotBlank
        @Size(max = 64)
        String username,

        @NotBlank
        @Size(max = 128)
        String password,

        @Size(max = 128)
        String deviceId,

        @Size(max = 128)
        String deviceName
) {
}
