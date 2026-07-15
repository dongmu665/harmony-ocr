package com.harmonyocr.ai.service;

import com.harmonyocr.ai.dto.AiActionRequest;
import com.harmonyocr.ai.dto.AiActionResponse;
import com.harmonyocr.ai.dto.AiProviderRequest;
import com.harmonyocr.ai.provider.AiFailoverProvider;
import com.harmonyocr.ai.provider.AiProvider;
import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.membership.service.MembershipService;
import com.harmonyocr.record.dto.RecordResponse;
import com.harmonyocr.record.service.RecordService;
import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Service;

/**
 * AI 动作业务服务，属于 ai 模块。
 * 维护说明：集中处理用户同意、OCR 记录归属和 provider 调用；任何第三方发送前必须经过 consentAccepted 显式确认。
 */
@Service
public class AiActionService {

    private final RecordService recordService;
    private final AiProvider aiProvider;
    private final MembershipService membershipService;
    private final AiProviderConfigService aiProviderConfigService;
    private final AiRuntimeConsentService aiRuntimeConsentService;

    @Autowired
    public AiActionService(
            RecordService recordService,
            List<AiProvider> aiProviders,
            MembershipService membershipService,
            AiProviderConfigService aiProviderConfigService,
            AiRuntimeConsentService aiRuntimeConsentService,
            Environment environment) {
        this.recordService = recordService;
        this.aiProvider = selectProvider(aiProviders, environment);
        this.membershipService = membershipService;
        this.aiProviderConfigService = aiProviderConfigService;
        this.aiRuntimeConsentService = aiRuntimeConsentService;
    }

    public AiActionService(
            RecordService recordService,
            List<AiProvider> aiProviders,
            MembershipService membershipService,
            Environment environment) {
        this(recordService, aiProviders, membershipService, null, null, environment);
    }

    public AiActionService(RecordService recordService, AiProvider aiProvider, MembershipService membershipService) {
        this(recordService, List.of(aiProvider), membershipService, null);
    }

    /**
     * 对当前用户拥有的 OCR 记录执行 AI 动作。
     * 参数 userId 来自认证上下文，request 包含记录 ID、动作和同意标记；返回 provider contract 响应。
     * 安全注意：未显式同意时拒绝处理；记录不存在或越权由 RecordService 统一返回 NOT_FOUND。
     */
    public AiActionResponse process(Long userId, AiActionRequest request) {
        if (!Boolean.TRUE.equals(request.consentAccepted())) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "consentAccepted must be true before AI processing");
        }
        if (aiRuntimeConsentService != null) {
            aiRuntimeConsentService.requireAccepted(userId);
        }
        RecordResponse record = recordService.detail(userId, request.recordId());
        String sourceText = preferredText(record);
        if (sourceText.isBlank()) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "record text must not be empty for AI processing");
        }
        membershipService.consume(userId, "AI");
        AiProviderRequest providerRequest = new AiProviderRequest(
                userId,
                record.id(),
                request.action(),
                sourceText,
                request.targetLanguage());
        if (aiProviderConfigService != null) {
            return aiProviderConfigService.processWithDefaultProvider(userId, providerRequest)
                    .orElseGet(() -> aiProvider.process(providerRequest));
        }
        return aiProvider.process(providerRequest);
    }

    private String preferredText(RecordResponse record) {
        if (record.editedText() != null && !record.editedText().isBlank()) {
            return record.editedText();
        }
        return record.rawText() == null ? "" : record.rawText();
    }

    /**
     * 根据运行时配置选择 AI Provider。
     * 参数 aiProviders 来自 Spring 容器；当 app.ai.failover-enabled=true 时包装为顺序 failover，否则沿用单 provider 行为。
     */
    private AiProvider selectProvider(List<AiProvider> aiProviders, Environment environment) {
        if (aiProviders == null || aiProviders.isEmpty()) {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "AI provider is not configured");
        }
        boolean failoverEnabled = environment != null
                && environment.getProperty("app.ai.failover-enabled", Boolean.class, false);
        if (failoverEnabled && aiProviders.size() > 1) {
            return new AiFailoverProvider(aiProviders);
        }
        return aiProviders.getFirst();
    }
}
