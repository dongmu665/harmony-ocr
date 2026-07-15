package com.harmonyocr.auth.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 注册请求 DTO，属于 auth 模块。
 * 维护说明：密码由服务层使用 BCrypt 处理，控制器和 DTO 不保存明文副本。
 */
public record RegisterRequest(
        @NotBlank
        @Size(min = 3, max = 64)
        String username,

        @NotBlank
        @Size(min = 8, max = 128)
        String password,

        @Size(max = 64)
        String nickname
) {
}
