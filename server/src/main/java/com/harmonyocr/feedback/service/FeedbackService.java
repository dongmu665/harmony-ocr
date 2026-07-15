package com.harmonyocr.feedback.service;

import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.feedback.dto.CreateFeedbackRequest;
import com.harmonyocr.feedback.dto.FeedbackResponse;
import com.harmonyocr.feedback.entity.FeedbackEntity;
import com.harmonyocr.feedback.entity.FeedbackStatus;
import com.harmonyocr.feedback.entity.FeedbackType;
import com.harmonyocr.feedback.mapper.FeedbackMapper;
import java.time.LocalDateTime;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 用户反馈业务服务，属于 feedback 模块。
 * 维护说明：负责反馈类型白名单、内容长度和归属绑定；反馈正文、联系方式和设备信息不得写入日志或对外回显。
 */
@Service
public class FeedbackService {

    private final FeedbackMapper feedbackMapper;

    public FeedbackService(FeedbackMapper feedbackMapper) {
        this.feedbackMapper = feedbackMapper;
    }

    /**
     * 创建匿名或登录用户反馈。
     * 参数为可为空的当前用户 ID 和创建请求；返回最小确认响应。可能抛出 VALIDATION_ERROR。
     * 安全注意：userId 只能来自认证上下文，客户端即使提交 userId/status 也不会被使用；正文不记录日志。
     */
    @Transactional
    public FeedbackResponse create(Long userId, CreateFeedbackRequest request) {
        String feedbackType = normalizeFeedbackType(request.feedbackType());
        LocalDateTime now = LocalDateTime.now();

        FeedbackEntity entity = new FeedbackEntity();
        entity.setUserId(userId);
        entity.setFeedbackType(feedbackType);
        entity.setContent(request.content().trim());
        entity.setContact(blankToNull(request.contact()));
        entity.setDeviceInfo(blankToNull(request.deviceInfo()));
        entity.setAppVersion(blankToNull(request.appVersion()));
        entity.setStatus(FeedbackStatus.PENDING.name());
        entity.setCreatedAt(now);
        entity.setUpdatedAt(now);
        entity.setDeleted(false);
        feedbackMapper.insert(entity);
        return toResponse(entity);
    }

    /**
     * 匿名化指定用户已提交的反馈，用于账号注销数据删除流程。
     * 参数为已认证用户 ID；返回值为空。安全注意：只处理该用户实名反馈，清空联系方式、设备信息、正文和 userId，匿名反馈不受影响。
     */
    @Transactional
    public void anonymizeByUserId(Long userId) {
        feedbackMapper.update(null, new LambdaUpdateWrapper<FeedbackEntity>()
                .eq(FeedbackEntity::getUserId, userId)
                .set(FeedbackEntity::getUserId, null)
                .set(FeedbackEntity::getContent, "[deleted by account deletion]")
                .set(FeedbackEntity::getContact, null)
                .set(FeedbackEntity::getDeviceInfo, null)
                .set(FeedbackEntity::getAppVersion, null)
                .set(FeedbackEntity::getUpdatedAt, LocalDateTime.now()));
    }

    private String normalizeFeedbackType(String value) {
        String normalized = FeedbackType.normalize(value);
        if (normalized == null) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "feedbackType must be bug, suggestion, complaint or other");
        }
        return normalized;
    }

    private String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.trim();
    }

    private FeedbackResponse toResponse(FeedbackEntity entity) {
        return new FeedbackResponse(
                entity.getId(),
                entity.getFeedbackType(),
                entity.getStatus(),
                entity.getCreatedAt());
    }
}
