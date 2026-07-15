package com.harmonyocr.admin.dto;

import java.util.List;

/**
 * Admin 批量创建激活码响应 DTO，属于 admin/membership 模块。
 * 维护说明：codes 中包含本次生成的明文 code；列表查询接口不会再次返回这些明文。
 */
public record ActivationCodeCreateResponse(
        List<ActivationCodeCreatedResponse> codes) {
}
