package com.harmonyocr.auth.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.harmonyocr.common.api.Result;
import com.harmonyocr.common.error.ErrorCode;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.http.MediaType;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.stereotype.Component;

/**
 * REST 认证失败入口，属于 auth security 模块。
 * 维护说明：Spring Security 过滤器链中的未认证错误不会进入全局异常处理器，因此这里统一输出 Result。
 */
@Component
public class RestAuthenticationEntryPoint implements AuthenticationEntryPoint {

    private final ObjectMapper objectMapper;

    public RestAuthenticationEntryPoint(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    /**
     * 将未登录或 Access Token 无效场景转换为统一 401 JSON 响应。
     * 参数为当前请求、响应对象和认证异常；不返回业务数据，不暴露底层异常细节。
     */
    @Override
    public void commence(HttpServletRequest request, HttpServletResponse response, AuthenticationException authException)
            throws IOException {
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding("UTF-8");
        objectMapper.writeValue(response.getWriter(), Result.failure(ErrorCode.UNAUTHORIZED));
    }
}
