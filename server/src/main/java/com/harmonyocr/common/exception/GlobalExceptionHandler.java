package com.harmonyocr.common.exception;

import com.harmonyocr.common.api.Result;
import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import jakarta.validation.ConstraintViolationException;
import java.util.stream.Collectors;
import org.springframework.http.ResponseEntity;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * 全局异常处理器，属于 common/exception 模块。
 *
 * 维护说明：该类统一把业务异常、参数校验异常和兜底异常转换成 Result，避免控制器散落错误响应格式。
 * 安全注意：兜底异常不能把堆栈、SQL、文件路径、Token、API Key 或 OCR 全文回传给客户端。
 */
@RestControllerAdvice
public class GlobalExceptionHandler {

    /**
     * 处理业务层主动抛出的已知异常。
     *
     * @param ex 包含统一错误码和脱敏业务文案的异常
     * @return 与错误码 HTTP 状态一致的统一失败响应
     */
    @ExceptionHandler(BusinessException.class)
    public ResponseEntity<Result<Void>> handleBusinessException(BusinessException ex) {
        ErrorCode errorCode = ex.getErrorCode();
        return ResponseEntity
                .status(errorCode.getHttpStatus())
                .body(Result.failure(errorCode, ex.getMessage()));
    }

    /**
     * 处理请求体字段校验异常。
     *
     * @param ex Spring Validation 绑定异常
     * @return 统一校验失败响应
     */
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ResponseEntity<Result<Void>> handleMethodArgumentNotValid(MethodArgumentNotValidException ex) {
        String message = ex.getBindingResult()
                .getFieldErrors()
                .stream()
                .map(this::formatFieldError)
                .collect(Collectors.joining("; "));
        return ResponseEntity
                .status(ErrorCode.VALIDATION_ERROR.getHttpStatus())
                .body(Result.failure(ErrorCode.VALIDATION_ERROR, message));
    }

    /**
     * 处理路径参数、查询参数等约束校验异常。
     *
     * @param ex 参数约束异常
     * @return 统一校验失败响应
     */
    @ExceptionHandler(ConstraintViolationException.class)
    public ResponseEntity<Result<Void>> handleConstraintViolation(ConstraintViolationException ex) {
        String message = ex.getConstraintViolations()
                .stream()
                .map(violation -> violation.getPropertyPath() + ": " + violation.getMessage())
                .collect(Collectors.joining("; "));
        return ResponseEntity
                .status(ErrorCode.VALIDATION_ERROR.getHttpStatus())
                .body(Result.failure(ErrorCode.VALIDATION_ERROR, message));
    }

    /**
     * 处理未预期异常。
     *
     * @param ex 未被业务层转换的异常
     * @return 统一内部错误响应，不暴露异常细节
     */
    @ExceptionHandler(Exception.class)
    public ResponseEntity<Result<Void>> handleException(Exception ex) {
        return ResponseEntity
                .status(ErrorCode.INTERNAL_ERROR.getHttpStatus())
                .body(Result.failure(ErrorCode.INTERNAL_ERROR));
    }

    /**
     * 格式化字段校验错误。
     *
     * @param fieldError 单个字段校验错误
     * @return 字段名和脱敏校验说明
     */
    private String formatFieldError(FieldError fieldError) {
        return fieldError.getField() + ": " + fieldError.getDefaultMessage();
    }
}
