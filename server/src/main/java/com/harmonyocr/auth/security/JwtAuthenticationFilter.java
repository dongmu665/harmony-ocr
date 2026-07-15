package com.harmonyocr.auth.security;

import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.user.entity.UserEntity;
import com.harmonyocr.user.entity.UserStatus;
import com.harmonyocr.user.service.UserService;
import io.jsonwebtoken.JwtException;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.List;
import org.springframework.http.HttpHeaders;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.AuthenticationEntryPoint;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * JWT 认证过滤器，属于 auth security 模块。
 * 维护说明：从 Authorization Bearer 头解析 Access Token，并把最小化 CurrentUser 放入 SecurityContext。
 */
@Component
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtService jwtService;
    private final UserService userService;
    private final AuthenticationEntryPoint authenticationEntryPoint;

    public JwtAuthenticationFilter(
            JwtService jwtService,
            UserService userService,
            RestAuthenticationEntryPoint authenticationEntryPoint) {
        this.jwtService = jwtService;
        this.userService = userService;
        this.authenticationEntryPoint = authenticationEntryPoint;
    }

    /**
     * 执行每个请求的 JWT 认证。
     * 参数为 Servlet 请求、响应和过滤器链；无 Bearer 头时放行给后续鉴权规则处理。
     * 安全注意：Token 无效时清空 SecurityContext，并返回统一未认证响应。
     */
    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        String authorization = request.getHeader(HttpHeaders.AUTHORIZATION);
        if (authorization == null || !authorization.startsWith("Bearer ")) {
            filterChain.doFilter(request, response);
            return;
        }

        try {
            CurrentUser currentUser = jwtService.parseAccessToken(authorization.substring(7));
            UserEntity user = userService.findById(currentUser.userId());
            if (user == null || !UserStatus.ACTIVE.name().equals(user.getStatus())) {
                SecurityContextHolder.clearContext();
                authenticationEntryPoint.commence(request, response,
                        new JwtAuthenticationException(ErrorCode.UNAUTHORIZED.getMessage()));
                return;
            }
            UsernamePasswordAuthenticationToken authentication =
                    new UsernamePasswordAuthenticationToken(currentUser, null, List.of());
            SecurityContextHolder.getContext().setAuthentication(authentication);
            filterChain.doFilter(request, response);
        } catch (JwtException | IllegalArgumentException ex) {
            SecurityContextHolder.clearContext();
            authenticationEntryPoint.commence(request, response,
                    new JwtAuthenticationException(ErrorCode.UNAUTHORIZED.getMessage()));
        }
    }

    /**
     * 判断是否跳过 JWT 解析。
     * 参数为当前请求；返回 true 表示匿名端点不解析 Bearer 头，确保 health 和登录注册不被坏 Token 干扰。
     */
    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String method = request.getMethod();
        String path = request.getRequestURI();
        String contextPath = request.getContextPath();
        if (contextPath != null && !contextPath.isBlank() && path.startsWith(contextPath)) {
            path = path.substring(contextPath.length());
        }
        return ("GET".equals(method) && "/api/v1/health".equals(path))
                || ("POST".equals(method) && (
                        "/api/v1/auth/register".equals(path)
                                || "/api/v1/auth/login".equals(path)
                                || "/api/v1/auth/refresh".equals(path)));
    }

    /**
     * JWT 认证异常，属于过滤器内部类型。
     * 维护说明：只携带通用错误信息，不暴露 Token 解析细节。
     */
    private static class JwtAuthenticationException extends org.springframework.security.core.AuthenticationException {
        JwtAuthenticationException(String message) {
            super(message);
        }
    }
}
