package com.harmonyocr.common.error;

/**
 * 业务异常基类，属于 common/error 模块。
 *
 * 维护说明：服务层通过该异常携带统一错误码，GlobalExceptionHandler 负责转换为统一 Result。
 * message 必须保持脱敏，不得包含密码、Token、API Key、对象存储签名 URL 或完整 OCR 文本。
 */
public class BusinessException extends RuntimeException {

    private final ErrorCode errorCode;

    /**
     * 使用错误码默认文案创建业务异常。
     *
     * @param errorCode 统一业务错误码
     */
    public BusinessException(ErrorCode errorCode) {
        super(errorCode.getMessage());
        this.errorCode = errorCode;
    }

    /**
     * 使用指定脱敏文案创建业务异常。
     *
     * @param errorCode 统一业务错误码
     * @param message 面向客户端展示的脱敏错误说明
     */
    public BusinessException(ErrorCode errorCode, String message) {
        super(message);
        this.errorCode = errorCode;
    }

    public ErrorCode getErrorCode() {
        return errorCode;
    }
}
