package com.harmonyocr.ai.dto;

/**
 * AI 文本处理动作枚举，属于 ai 模块。
 * 维护说明：枚举值与 V2.0-5 mandatory scope 对齐，作为 controller 入参白名单，避免自由字符串驱动未审计能力。
 */
public enum AiAction {
    CORRECTION,
    SUMMARY,
    TRANSLATION,
    TITLE,
    KEY_POINTS,
    FIELD_EXTRACTION,
    SMART_FORMAT,
    MARKDOWN
}
