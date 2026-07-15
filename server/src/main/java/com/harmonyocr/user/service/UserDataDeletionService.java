package com.harmonyocr.user.service;

import com.harmonyocr.ai.service.AiProviderConfigService;
import com.harmonyocr.auth.security.RefreshTokenService;
import com.harmonyocr.device.service.UserDeviceService;
import com.harmonyocr.feedback.service.FeedbackService;
import com.harmonyocr.file.service.FileObjectService;
import com.harmonyocr.record.service.RecordService;
import org.springframework.stereotype.Service;

/**
 * 用户数据删除扩展点服务，属于 user 模块。
 * 维护说明：账号注销时在这里编排当前用户拥有的业务数据清理；新增模块必须只处理传入 userId 归属的数据。
 */
@Service
public class UserDataDeletionService {

    private final RecordService recordService;
    private final FileObjectService fileObjectService;
    private final FeedbackService feedbackService;
    private final AiProviderConfigService aiProviderConfigService;
    private final RefreshTokenService refreshTokenService;
    private final UserDeviceService userDeviceService;

    public UserDataDeletionService(
            RecordService recordService,
            FileObjectService fileObjectService,
            FeedbackService feedbackService,
            AiProviderConfigService aiProviderConfigService,
            RefreshTokenService refreshTokenService,
            UserDeviceService userDeviceService) {
        this.recordService = recordService;
        this.fileObjectService = fileObjectService;
        this.feedbackService = feedbackService;
        this.aiProviderConfigService = aiProviderConfigService;
        this.refreshTokenService = refreshTokenService;
        this.userDeviceService = userDeviceService;
    }

    /**
     * 删除或匿名化指定用户拥有的业务数据。
     * 参数为已经通过认证上下文确认的用户 ID；当前返回值为空。
     * 安全注意：Refresh Token 和设备信息采用物理删除；OCR 文本、blocks、文件对象和实名反馈按隐私优先策略清理，存储删除失败会留下可追踪状态。
     */
    public void deleteUserOwnedData(Long userId) {
        refreshTokenService.deleteAllByUserId(userId);
        userDeviceService.deleteByUserId(userId);
        recordService.softDeleteByUserId(userId);
        fileObjectService.softDeleteByUserId(userId);
        feedbackService.anonymizeByUserId(userId);
        aiProviderConfigService.deleteByUserId(userId);
    }
}
