package com.harmonyocr.common.error;

import org.springframework.http.HttpStatus;

/**
 * 统一错误码枚举，属于 common error 模块。
 * 维护说明：认证错误码用于稳定 API 响应，避免直接暴露底层异常、密码校验细节或 Token 解析细节。
 */
public enum ErrorCode {
    OK("OK", "success", HttpStatus.OK),
    BAD_REQUEST("BAD_REQUEST", "Bad request", HttpStatus.BAD_REQUEST),
    UNAUTHORIZED("UNAUTHORIZED", "Unauthorized", HttpStatus.UNAUTHORIZED),
    FORBIDDEN("FORBIDDEN", "Forbidden", HttpStatus.FORBIDDEN),
    NOT_FOUND("NOT_FOUND", "Not found", HttpStatus.NOT_FOUND),
    VALIDATION_ERROR("VALIDATION_ERROR", "Validation failed", HttpStatus.BAD_REQUEST),
    FILE_TYPE_NOT_ALLOWED("FILE_TYPE_NOT_ALLOWED", "File type is not allowed", HttpStatus.BAD_REQUEST),
    FILE_TOO_LARGE("FILE_TOO_LARGE", "File is too large", HttpStatus.BAD_REQUEST),
    PDF_INVALID("PDF_INVALID", "PDF is invalid", HttpStatus.BAD_REQUEST),
    PDF_TOO_MANY_PAGES("PDF_TOO_MANY_PAGES", "PDF has too many pages", HttpStatus.BAD_REQUEST),
    PDF_ENCRYPTED("PDF_ENCRYPTED", "Encrypted PDF is not supported", HttpStatus.BAD_REQUEST),
    PDF_RENDER_FAILED("PDF_RENDER_FAILED", "PDF page render failed", HttpStatus.BAD_REQUEST),
    UPLOAD_FAILED("UPLOAD_FAILED", "File upload failed", HttpStatus.INTERNAL_SERVER_ERROR),
    OCR_FAILED("OCR_FAILED", "OCR recognition failed", HttpStatus.BAD_GATEWAY),
    OCR_TIMEOUT("OCR_TIMEOUT", "OCR recognition timed out", HttpStatus.GATEWAY_TIMEOUT),
    QUOTA_EXCEEDED("QUOTA_EXCEEDED", "Quota exceeded", HttpStatus.TOO_MANY_REQUESTS),
    USERNAME_ALREADY_EXISTS("USERNAME_ALREADY_EXISTS", "Username already exists", HttpStatus.BAD_REQUEST),
    USER_NOT_FOUND("USER_NOT_FOUND", "User not found", HttpStatus.NOT_FOUND),
    AUTH_INVALID_CREDENTIALS("AUTH_INVALID_CREDENTIALS", "Invalid username or password", HttpStatus.UNAUTHORIZED),
    AUTH_TOKEN_EXPIRED("AUTH_TOKEN_EXPIRED", "Token expired", HttpStatus.UNAUTHORIZED),
    AUTH_TOKEN_INVALID("AUTH_TOKEN_INVALID", "Token invalid", HttpStatus.UNAUTHORIZED),
    AUTH_REFRESH_TOKEN_INVALID("AUTH_REFRESH_TOKEN_INVALID", "Refresh token invalid", HttpStatus.UNAUTHORIZED),
    AUTH_REFRESH_TOKEN_EXPIRED("AUTH_REFRESH_TOKEN_EXPIRED", "Refresh token expired", HttpStatus.UNAUTHORIZED),
    AUTH_TOKEN_REVOKED("AUTH_TOKEN_REVOKED", "Token revoked", HttpStatus.UNAUTHORIZED),
    ACCOUNT_DISABLED("ACCOUNT_DISABLED", "Account disabled", HttpStatus.FORBIDDEN),
    ACCOUNT_DELETED("ACCOUNT_DELETED", "Account deleted", HttpStatus.FORBIDDEN),
    INTERNAL_ERROR("INTERNAL_ERROR", "Internal server error", HttpStatus.INTERNAL_SERVER_ERROR);

    private final String code;
    private final String message;
    private final HttpStatus httpStatus;

    ErrorCode(String code, String message, HttpStatus httpStatus) {
        this.code = code;
        this.message = message;
        this.httpStatus = httpStatus;
    }

    public String getCode() {
        return code;
    }

    public String getMessage() {
        return message;
    }

    public HttpStatus getHttpStatus() {
        return httpStatus;
    }
}
