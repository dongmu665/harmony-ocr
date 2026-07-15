package com.harmonyocr.user.entity;

/**
 * 用户账号状态枚举，属于 user 模块。
 * 维护说明：登录只允许 ACTIVE 状态，DISABLED 和 DELETED 必须拒绝认证。
 */
public enum UserStatus {
    ACTIVE,
    DISABLED,
    DELETED
}
