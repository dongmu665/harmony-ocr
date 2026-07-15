package com.harmonyocr.user.controller;

import com.harmonyocr.auth.security.CurrentUser;
import com.harmonyocr.common.api.Result;
import com.harmonyocr.user.dto.ChangePasswordRequest;
import com.harmonyocr.user.dto.UpdateCurrentUserRequest;
import com.harmonyocr.user.dto.UserProfileResponse;
import com.harmonyocr.user.service.UserService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 用户资料接口控制器，属于 user 模块。
 * 维护说明：提供当前登录用户资料查询和账号注销入口；所有操作都以 SecurityContext 中的 CurrentUser 为准。
 */
@RestController
@RequestMapping("/api/v1/users")
public class UserController {

    private final UserService userService;

    public UserController(UserService userService) {
        this.userService = userService;
    }

    /**
     * 查询当前登录用户基础资料。
     * 参数来自 SecurityContext 中的 CurrentUser，禁止从请求参数信任 userId。
     */
    @GetMapping("/me")
    public Result<UserProfileResponse> me(@AuthenticationPrincipal CurrentUser currentUser) {
        return Result.success(userService.currentUserProfile(currentUser.userId()));
    }

    /**
     * 更新当前登录用户基础资料。
     * 参数只能修改低敏展示字段；用户 ID、账号状态、密码和 Token 均以服务端为准。
     */
    @PatchMapping("/me")
    public Result<UserProfileResponse> updateMe(
            @AuthenticationPrincipal CurrentUser currentUser,
            @Valid @RequestBody UpdateCurrentUserRequest request) {
        return Result.success(userService.updateCurrentUserProfile(currentUser.userId(), request));
    }

    /**
     * 修改当前登录用户密码。
     * 参数包含当前密码和新密码；服务端先校验当前密码，再保存 BCrypt 哈希，响应不回显任何密码字段。
     */
    @PatchMapping("/me/password")
    public Result<Void> changePassword(
            @AuthenticationPrincipal CurrentUser currentUser,
            @Valid @RequestBody ChangePasswordRequest request) {
        userService.changePassword(currentUser.userId(), request);
        return Result.success(null);
    }

    /**
     * 注销当前登录用户账号。
     * 参数来自 SecurityContext 中的 CurrentUser；返回统一 Result 空数据。安全注意：不接受请求体中的 userId，
     * 避免用户注销他人账号，实际软删除和 Token 撤销由 UserService 事务化处理。
     */
    @DeleteMapping("/me")
    public Result<Void> deleteMe(@AuthenticationPrincipal CurrentUser currentUser) {
        userService.deleteCurrentUser(currentUser.userId());
        return Result.success(null);
    }
}
