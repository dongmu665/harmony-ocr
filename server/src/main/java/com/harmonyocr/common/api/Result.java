package com.harmonyocr.common.api;

import com.harmonyocr.common.error.ErrorCode;
import java.time.Instant;

/**
 * 后端统一 API 响应结构，属于 common/api 模块。
 *
 * 维护说明：所有控制器返回值应通过该结构包装，便于移动端按 success/code/message/data 统一处理。
 * message 只放脱敏错误说明，不得包含密码、Token、API Key、对象存储签名地址或完整 OCR 隐私文本。
 */
public record Result<T>(
        boolean success,
        String code,
        String message,
        T data,
        Instant timestamp
) {

    /**
     * 构造成功响应。
     *
     * @param data 已通过业务层权限校验和脱敏处理的响应数据
     * @param <T> 响应数据类型
     * @return 统一成功响应
     */
    public static <T> Result<T> success(T data) {
        return new Result<>(true, ErrorCode.OK.getCode(), ErrorCode.OK.getMessage(), data, Instant.now());
    }

    /**
     * 使用错误码默认文案构造失败响应。
     *
     * @param errorCode 业务错误码
     * @param <T> 响应数据类型
     * @return 统一失败响应
     */
    public static <T> Result<T> failure(ErrorCode errorCode) {
        return failure(errorCode, errorCode.getMessage());
    }

    /**
     * 使用指定脱敏文案构造失败响应。
     *
     * @param errorCode 业务错误码
     * @param message 面向客户端展示的脱敏错误说明
     * @param <T> 响应数据类型
     * @return 统一失败响应
     */
    public static <T> Result<T> failure(ErrorCode errorCode, String message) {
        return new Result<>(false, errorCode.getCode(), message, null, Instant.now());
    }
}
