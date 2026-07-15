package com.harmonyocr.feedback.entity;

/**
 * 用户反馈处理状态，属于 feedback 模块。
 * 维护说明：当前用户反馈提交接口只写入 PENDING，其他状态仅为后续后台处理能力预留，不提供状态流转接口。
 */
public enum FeedbackStatus {
    PENDING,
    PROCESSING,
    RESOLVED,
    CLOSED
}
