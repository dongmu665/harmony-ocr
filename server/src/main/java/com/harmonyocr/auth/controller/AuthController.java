package com.harmonyocr.auth.controller;

import com.harmonyocr.auth.dto.AuthTokenResponse;
import com.harmonyocr.auth.dto.LoginRequest;
import com.harmonyocr.auth.dto.LogoutRequest;
import com.harmonyocr.auth.dto.RefreshTokenRequest;
import com.harmonyocr.auth.dto.RegisterRequest;
import com.harmonyocr.auth.security.CurrentUser;
import com.harmonyocr.auth.service.AuthService;
import com.harmonyocr.common.api.Result;
import com.harmonyocr.user.dto.UserProfileResponse;
import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 认证接口控制器，属于 auth 模块，负责暴露注册、登录、刷新 Token 和退出登录入口。
 * 维护说明：控制器只做参数校验和统一响应封装，认证业务规则集中在 AuthService。
 */
@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {

    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    /**
     * 注册新用户账号。
     * 参数为用户名、密码和可选昵称；返回不包含 password_hash 的用户基础资料。
     * 可能抛出参数校验异常或用户名重复业务异常。
     */
    @PostMapping("/register")
    public Result<UserProfileResponse> register(@Valid @RequestBody RegisterRequest request) {
        return Result.success(authService.register(request));
    }

    /**
     * 使用用户名和密码登录。
     * 成功时返回 Access Token、Refresh Token 和用户资料；失败时不区分用户不存在和密码错误。
     */
    @PostMapping("/login")
    public Result<AuthTokenResponse> login(@Valid @RequestBody LoginRequest request) {
        return Result.success(authService.login(request));
    }

    /**
     * 使用 Refresh Token 刷新会话。
     * 安全注意：服务端只按 Refresh Token 哈希查询，并在刷新成功后轮换旧 Token。
     */
    @PostMapping("/refresh")
    public Result<AuthTokenResponse> refresh(@Valid @RequestBody RefreshTokenRequest request) {
        return Result.success(authService.refresh(request));
    }

    /**
     * 退出登录并尽量撤销传入的 Refresh Token。
     * 参数可为空；当前用户来自 SecurityContext，只允许撤销本人 Refresh Token。
     */
    @PostMapping("/logout")
    public Result<Void> logout(
            @AuthenticationPrincipal CurrentUser currentUser,
            @RequestBody(required = false) LogoutRequest request) {
        authService.logout(currentUser.userId(), request);
        return Result.success(null);
    }
}
