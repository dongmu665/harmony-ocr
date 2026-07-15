package com.harmonyocr.user.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 当前用户修改密码请求，属于 user 模块。
 * 维护说明：明文密码只在请求处理内短暂使用，服务端只保存 BCrypt 哈希，响应不得回显密码。
 */
public record ChangePasswordRequest(
        @NotBlank
        String currentPassword,

        @NotBlank
        @Size(min = 8, max = 128)
        String newPassword
) {
}
