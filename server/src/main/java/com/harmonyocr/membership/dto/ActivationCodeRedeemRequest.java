package com.harmonyocr.membership.dto;

import jakarta.validation.constraints.NotBlank;

/**
 * 会员激活码兑换请求 DTO，属于 membership 模块。
 * 维护说明：只接收用户主动输入的短期明文 code；服务端不会持久化或记录该明文。
 */
public record ActivationCodeRedeemRequest(
        @NotBlank String code) {
}
