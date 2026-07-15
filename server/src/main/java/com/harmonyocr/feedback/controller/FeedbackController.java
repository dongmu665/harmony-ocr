package com.harmonyocr.feedback.controller;

import com.harmonyocr.auth.security.CurrentUser;
import com.harmonyocr.common.api.Result;
import com.harmonyocr.feedback.dto.CreateFeedbackRequest;
import com.harmonyocr.feedback.dto.FeedbackResponse;
import com.harmonyocr.feedback.service.FeedbackService;
import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 用户反馈接口控制器，属于 feedback 模块。
 * 维护说明：当前仅开放提交入口；登录用户归属来自 SecurityContext，匿名用户不绑定 userId，不提供后台查询或回复接口。
 */
@RestController
@RequestMapping("/api/v1/feedback")
public class FeedbackController {

    private final FeedbackService feedbackService;

    public FeedbackController(FeedbackService feedbackService) {
        this.feedbackService = feedbackService;
    }

    /**
     * 提交用户反馈。
     * 参数为可为空的认证主体和请求体；返回反馈 ID、类型、状态和创建时间。
     * 安全注意：无 Authorization Header 时按匿名保存；有无效 Bearer Token 会在 JWT 过滤器中返回 401，不会降级匿名。
     */
    @PostMapping
    public Result<FeedbackResponse> create(
            @AuthenticationPrincipal CurrentUser currentUser,
            @Valid @RequestBody CreateFeedbackRequest request) {
        Long userId = currentUser == null ? null : currentUser.userId();
        return Result.success(feedbackService.create(userId, request));
    }
}
