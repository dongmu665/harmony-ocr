package com.harmonyocr.admin.controller;

import com.harmonyocr.admin.dto.AdminAuditLogResponse;
import com.harmonyocr.admin.dto.AdminCapabilityResponse;
import com.harmonyocr.admin.dto.AdminFeedbackResponse;
import com.harmonyocr.admin.dto.AdminRecordResponse;
import com.harmonyocr.admin.dto.AdminUsageSummaryResponse;
import com.harmonyocr.admin.dto.AdminUserResponse;
import com.harmonyocr.admin.dto.ActivationCodeCreateRequest;
import com.harmonyocr.admin.dto.ActivationCodeCreateResponse;
import com.harmonyocr.admin.dto.ActivationCodeMetadataResponse;
import com.harmonyocr.admin.dto.FeedbackStatusUpdateRequest;
import com.harmonyocr.admin.dto.ManualMembershipOrderRequest;
import com.harmonyocr.admin.dto.ManualMembershipOrderResponse;
import com.harmonyocr.admin.service.AdminService;
import com.harmonyocr.auth.security.CurrentUser;
import com.harmonyocr.common.api.PageResult;
import com.harmonyocr.common.api.Result;
import com.harmonyocr.membership.dto.MembershipResponse;
import com.harmonyocr.membership.dto.UpdateMembershipRequest;
import com.harmonyocr.membership.service.MembershipActivationCodeService;
import com.harmonyocr.membership.service.MembershipService;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Web 管理后台控制器，属于 admin 模块。
 * 维护说明：所有接口先校验管理员身份，再返回脱敏管理数据；本阶段不实现支付或复杂运营工作流。
 */
@RestController
@RequestMapping("/api/v1/admin")
public class AdminController {

    private final AdminService adminService;
    private final MembershipService membershipService;
    private final MembershipActivationCodeService activationCodeService;

    public AdminController(
            AdminService adminService,
            MembershipService membershipService,
            MembershipActivationCodeService activationCodeService) {
        this.adminService = adminService;
        this.membershipService = membershipService;
        this.activationCodeService = activationCodeService;
    }

    /**
     * 查询当前用户是否具备 Admin 入口能力。
     * 返回值只包含布尔值；非管理员直接返回 FORBIDDEN，作为正式后台权限校验入口。
     */
    @GetMapping("/me")
    public Result<AdminCapabilityResponse> capability(@AuthenticationPrincipal CurrentUser currentUser) {
        adminService.requireAdmin(currentUser.userId());
        return Result.success(new AdminCapabilityResponse(true));
    }

    /**
     * 查询用户管理列表，可按关键字、状态和会员等级过滤。
     * 过滤参数只参与管理端只读查询，不返回密码哈希、Token 或联系方式。
     */
    @GetMapping("/users")
    public Result<PageResult<AdminUserResponse>> users(
            @AuthenticationPrincipal CurrentUser currentUser,
            @RequestParam(required = false) String keyword,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) String membershipLevel,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size) {
        return Result.success(adminService.users(currentUser.userId(), keyword, status, membershipLevel, page, size));
    }

    /**
     * 查询单个用户管理详情。
     * 返回 DTO 与列表一致，避免因详情页暴露认证敏感字段。
     */
    @GetMapping("/users/{id}")
    public Result<AdminUserResponse> user(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id) {
        return Result.success(adminService.user(currentUser.userId(), id));
    }

    /**
     * 管理员更新指定用户的会员额度。
     * 参数 id 为目标用户 ID，request 仅包含等级和额度；方法先校验管理员身份，再写入审计事件。
     */
    @PatchMapping("/users/{id}/membership")
    public Result<MembershipResponse> updateMembership(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id,
            @Valid @RequestBody UpdateMembershipRequest request) {
        adminService.requireAdmin(currentUser.userId());
        MembershipResponse response = membershipService.update(id, request);
        adminService.audit(currentUser.userId(), "ADMIN_UPDATE_MEMBERSHIP", "USER", id);
        return Result.success(response);
    }

    /**
     * 管理员创建课程版手工会员开通订单。
     * 安全边界：仅记录非敏感订单元数据和额度变更，不接入支付、退款或真实交易流水。
     */
    @PostMapping("/users/{id}/manual-orders")
    public Result<ManualMembershipOrderResponse> createManualMembershipOrder(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id,
            @Valid @RequestBody ManualMembershipOrderRequest request) {
        return Result.success(adminService.createManualMembershipOrder(currentUser.userId(), id, request));
    }

    /**
     * Admin 生成一个或多个会员激活码。
     * 响应仅本次包含明文 code；后续列表和审计日志均不返回或记录明文。
     */
    @PostMapping("/activation-codes")
    public Result<ActivationCodeCreateResponse> createActivationCodes(
            @AuthenticationPrincipal CurrentUser currentUser,
            @Valid @RequestBody ActivationCodeCreateRequest request) {
        return Result.success(activationCodeService.create(currentUser.userId(), request));
    }

    /**
     * Admin 查询激活码元数据列表。
     * 返回值只包含 codeFingerprint、状态、额度和兑换元数据，不返回明文 code 或完整 codeHash。
     */
    @GetMapping("/activation-codes")
    public Result<List<ActivationCodeMetadataResponse>> activationCodes(
            @AuthenticationPrincipal CurrentUser currentUser) {
        return Result.success(activationCodeService.list(currentUser.userId()));
    }

    /**
     * Admin 撤销未使用激活码。
     * 已兑换激活码不可撤销，以保留兑换审计和用户会员状态。
     */
    @PostMapping("/activation-codes/{id}/revoke")
    public Result<ActivationCodeMetadataResponse> revokeActivationCode(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id) {
        return Result.success(activationCodeService.revoke(currentUser.userId(), id));
    }

    /**
     * 查询管理端 OCR 记录元数据列表。
     * 响应不返回 OCR 全文、对象存储 key 或完整媒体路径，仅用于后台排查记录状态。
     */
    @GetMapping("/records")
    public Result<PageResult<AdminRecordResponse>> records(
            @AuthenticationPrincipal CurrentUser currentUser,
            @RequestParam(required = false) Long userId,
            @RequestParam(required = false) String sourceType,
            @RequestParam(required = false) String keyword,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size) {
        return Result.success(adminService.records(currentUser.userId(), userId, sourceType, keyword, page, size));
    }

    /**
     * 查询单条管理端 OCR 记录元数据。
     * 安全边界：详情仍保持脱敏，不因管理员入口暴露用户 OCR 正文或文件对象 key。
     */
    @GetMapping("/records/{id}")
    public Result<AdminRecordResponse> record(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id) {
        return Result.success(adminService.record(currentUser.userId(), id));
    }

    /**
     * 查询管理端反馈元数据列表。
     * 返回值用于运营处理状态概览，不返回反馈正文、联系方式或设备详情。
     */
    @GetMapping("/feedback")
    public Result<PageResult<AdminFeedbackResponse>> feedback(
            @AuthenticationPrincipal CurrentUser currentUser,
            @RequestParam(required = false) Long userId,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) String feedbackType,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size) {
        return Result.success(adminService.feedback(currentUser.userId(), userId, status, feedbackType, page, size));
    }

    /**
     * 查询单条反馈元数据详情。
     * 安全边界：详情页不暴露用户联系方式、原始反馈正文或设备指纹。
     */
    @GetMapping("/feedback/{id}")
    public Result<AdminFeedbackResponse> feedbackDetail(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id) {
        return Result.success(adminService.feedbackDetail(currentUser.userId(), id));
    }

    /**
     * 更新反馈处理状态。
     * 安全边界：只写入状态和审计日志，不返回或记录反馈正文、联系方式、设备信息。
     */
    @PatchMapping("/feedback/{id}/status")
    public Result<AdminFeedbackResponse> updateFeedbackStatus(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id,
            @Valid @RequestBody FeedbackStatusUpdateRequest request) {
        return Result.success(adminService.updateFeedbackStatus(currentUser.userId(), id, request));
    }

    /**
     * 查询管理端用量汇总。
     * 返回聚合计数，用于后台概览，不返回单条 OCR 文本、AI 请求内容或导出文件内容。
     */
    @GetMapping("/usage/summary")
    public Result<AdminUsageSummaryResponse> usageSummary(@AuthenticationPrincipal CurrentUser currentUser) {
        return Result.success(adminService.usageSummary(currentUser.userId()));
    }

    /**
     * 查询管理员审计日志。
     * 返回值只包含审计元数据，便于后台核对操作，不暴露请求体或敏感值。
     */
    @GetMapping("/audit-logs")
    public Result<PageResult<AdminAuditLogResponse>> auditLogs(
            @AuthenticationPrincipal CurrentUser currentUser,
            @RequestParam(required = false) String action,
            @RequestParam(required = false) String targetType,
            @RequestParam(required = false) Long targetId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size) {
        return Result.success(adminService.auditLogs(currentUser.userId(), action, targetType, targetId, page, size));
    }

    /**
     * 查询单条管理员审计日志。
     * 返回值仍只含动作和目标元数据，不暴露请求体、认证信息或业务正文。
     */
    @GetMapping("/audit-logs/{id}")
    public Result<AdminAuditLogResponse> auditLog(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id) {
        return Result.success(adminService.auditLog(currentUser.userId(), id));
    }
}
