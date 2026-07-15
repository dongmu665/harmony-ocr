package com.harmonyocr.user.dto;

import jakarta.validation.constraints.Size;

/**
 * 当前用户资料更新请求，属于 user 模块。
 * 维护说明：只允许更新低敏展示资料；用户名、状态、密码哈希和 Token 均不得由该请求修改。
 */
public record UpdateCurrentUserRequest(
        @Size(max = 64)
        String nickname,

        @Size(max = 512)
        String avatarUrl
) {
}
