package com.harmonyocr.admin.dto;

/**
 * 当前用户管理员能力响应，属于 admin 模块。
 * 维护说明：只返回当前用户是否具备管理入口权限，不暴露管理员列表、角色细节或运营数据。
 */
public record AdminCapabilityResponse(boolean admin) {
}
