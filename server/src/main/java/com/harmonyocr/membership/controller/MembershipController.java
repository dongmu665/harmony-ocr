package com.harmonyocr.membership.controller;

import com.harmonyocr.auth.security.CurrentUser;
import com.harmonyocr.common.api.Result;
import com.harmonyocr.membership.dto.ActivationCodeRedeemRequest;
import com.harmonyocr.membership.dto.MembershipResponse;
import com.harmonyocr.membership.service.MembershipActivationCodeService;
import com.harmonyocr.membership.service.MembershipService;
import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 会员额度控制器，属于 membership 模块。
 * 维护说明：当前只开放当前用户自己的额度概览，不暴露其他用户数据。
 */
@RestController
@RequestMapping("/api/v1/membership")
public class MembershipController {

    private final MembershipService membershipService;
    private final MembershipActivationCodeService activationCodeService;

    public MembershipController(
            MembershipService membershipService,
            MembershipActivationCodeService activationCodeService) {
        this.membershipService = membershipService;
        this.activationCodeService = activationCodeService;
    }

    /**
     * 查询当前用户会员等级和使用量。
     * 参数 currentUser 来自 JWT；返回当前月 OCR/AI/导出额度与已用次数。
     */
    @GetMapping("/me")
    public Result<MembershipResponse> me(@AuthenticationPrincipal CurrentUser currentUser) {
        return Result.success(membershipService.current(currentUser.userId()));
    }

    /**
     * 当前登录用户兑换会员激活码。
     * 参数 currentUser 来自 JWT；明文 code 只用于本次请求匹配，不保存、不记录，成功后返回最新会员额度。
     */
    @PostMapping("/activation-codes/redeem")
    public Result<MembershipResponse> redeemActivationCode(
            @AuthenticationPrincipal CurrentUser currentUser,
            @Valid @RequestBody ActivationCodeRedeemRequest request) {
        return Result.success(activationCodeService.redeem(currentUser.userId(), request));
    }
}
