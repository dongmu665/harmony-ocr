package com.harmonyocr.feedback.entity;

import java.util.Arrays;
import java.util.Locale;

/**
 * 用户反馈类型白名单，属于 feedback 模块。
 * 维护说明：接口只接受这里列出的低风险分类，避免客户端提交任意状态或后台处理含义。
 */
public enum FeedbackType {
    BUG("bug"),
    SUGGESTION("suggestion"),
    COMPLAINT("complaint"),
    OTHER("other");

    private final String code;

    FeedbackType(String code) {
        this.code = code;
    }

    public String getCode() {
        return code;
    }

    /**
     * 将请求中的反馈类型归一化为白名单编码。
     * 参数为客户端提交的 feedbackType；返回小写编码，非法或空白时返回 null 由业务层转换为校验错误。
     */
    public static String normalize(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        String normalized = value.trim().toLowerCase(Locale.ROOT);
        return Arrays.stream(values())
                .map(FeedbackType::getCode)
                .filter(code -> code.equals(normalized))
                .findFirst()
                .orElse(null);
    }
}
