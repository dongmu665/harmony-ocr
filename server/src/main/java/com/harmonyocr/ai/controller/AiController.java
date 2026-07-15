package com.harmonyocr.ai.controller;

import com.harmonyocr.ai.dto.AiActionRequest;
import com.harmonyocr.ai.dto.AiActionResponse;
import com.harmonyocr.ai.dto.AiProviderConfigRequest;
import com.harmonyocr.ai.dto.AiProviderConfigResponse;
import com.harmonyocr.ai.dto.AiProviderTestResponse;
import com.harmonyocr.ai.dto.AiRuntimeConsentRequest;
import com.harmonyocr.ai.dto.AiRuntimeConsentResponse;
import com.harmonyocr.ai.service.AiActionService;
import com.harmonyocr.ai.service.AiProviderConfigService;
import com.harmonyocr.ai.service.AiRuntimeConsentService;
import com.harmonyocr.auth.security.CurrentUser;
import com.harmonyocr.common.api.Result;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * AI 能力控制器，属于 ai 模块。
 * 维护说明：只暴露认证用户的 AI 动作入口，不接收客户端 userId、API Key、Base URL 或完整 provider 配置。
 */
@RestController
@RequestMapping("/api/v1/ai")
public class AiController {

    private final AiActionService aiActionService;
    private final AiProviderConfigService aiProviderConfigService;
    private final AiRuntimeConsentService aiRuntimeConsentService;

    public AiController(
            AiActionService aiActionService,
            AiProviderConfigService aiProviderConfigService,
            AiRuntimeConsentService aiRuntimeConsentService) {
        this.aiActionService = aiActionService;
        this.aiProviderConfigService = aiProviderConfigService;
        this.aiRuntimeConsentService = aiRuntimeConsentService;
    }

    /**
     * 查询当前用户 AI 运行时隐私同意状态。
     * 返回值只包含同意范围与时间戳，不包含 OCR 文本、prompt、API Key 或 provider 响应。
     */
    @GetMapping("/consent")
    public Result<AiRuntimeConsentResponse> getConsent(@AuthenticationPrincipal CurrentUser currentUser) {
        return Result.success(aiRuntimeConsentService.current(currentUser.userId()));
    }

    /**
     * 保存当前用户 AI 运行时隐私同意状态。
     * 参数 request 只能表达是否同意，不允许夹带 OCR 全文、prompt、provider request 或密钥。
     */
    @PostMapping("/consent")
    public Result<AiRuntimeConsentResponse> updateConsent(
            @AuthenticationPrincipal CurrentUser currentUser,
            @Valid @RequestBody AiRuntimeConsentRequest request) {
        return Result.success(aiRuntimeConsentService.update(currentUser.userId(), request.accepted()));
    }

    /**
     * 执行单条 OCR 记录的 AI 文本处理。
     * 参数 request 必须带 consentAccepted=true；返回统一响应格式和 provider contract 元数据。
     */
    @PostMapping("/actions")
    public Result<AiActionResponse> process(
            @AuthenticationPrincipal CurrentUser currentUser,
            @Valid @RequestBody AiActionRequest request) {
        return Result.success(aiActionService.process(currentUser.userId(), request));
    }

    /**
     * 创建当前用户的 AI Provider 配置。
     * 参数 request 可包含一次性 apiKey；返回脱敏配置，不返回密钥原文。
     */
    @PostMapping("/providers")
    public Result<AiProviderConfigResponse> createProvider(
            @AuthenticationPrincipal CurrentUser currentUser,
            @Valid @RequestBody AiProviderConfigRequest request) {
        return Result.success(aiProviderConfigService.create(currentUser.userId(), request));
    }

    /**
     * 查询当前用户 AI Provider 配置列表。
     * 返回值只包含脱敏元数据和 fingerprint，不包含 API Key。
     */
    @GetMapping("/providers")
    public Result<List<AiProviderConfigResponse>> listProviders(@AuthenticationPrincipal CurrentUser currentUser) {
        return Result.success(aiProviderConfigService.list(currentUser.userId()));
    }

    /**
     * 更新当前用户的 AI Provider 配置。
     * 参数 id 必须属于当前用户；apiKey 替换只更新 fingerprint。
     */
    @PatchMapping("/providers/{id}")
    public Result<AiProviderConfigResponse> updateProvider(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id,
            @Valid @RequestBody AiProviderConfigRequest request) {
        return Result.success(aiProviderConfigService.update(currentUser.userId(), id, request));
    }

    /**
     * 测试当前用户 provider 配置。
     * loopback 与 HTTPS 外部 provider 均执行受限连接测试；外部请求只携带内存中的密钥和固定测试文本，响应保持脱敏。
     */
    @PostMapping("/providers/{id}/test")
    public Result<AiProviderTestResponse> testProvider(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id) {
        return Result.success(aiProviderConfigService.testConnection(currentUser.userId(), id));
    }

    /**
     * 重新加密当前用户 provider 的 API Key。
     * 参数 id 必须属于当前用户；服务层只在内存中短暂解密并写入新 AES-GCM 密文，响应仍不返回密钥或密文。
     */
    @PostMapping("/providers/{id}/reencrypt")
    public Result<AiProviderConfigResponse> reencryptProvider(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id) {
        return Result.success(aiProviderConfigService.reencrypt(currentUser.userId(), id));
    }

    /**
     * 删除当前用户的 AI Provider 配置。
     * 参数 id 必须属于当前用户；服务层执行软删除，避免跨用户删除。
     */
    @DeleteMapping("/providers/{id}")
    public Result<Void> deleteProvider(
            @AuthenticationPrincipal CurrentUser currentUser,
            @PathVariable Long id) {
        aiProviderConfigService.delete(currentUser.userId(), id);
        return Result.success(null);
    }
}
