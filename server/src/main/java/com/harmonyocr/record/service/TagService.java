package com.harmonyocr.record.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.record.dto.CreateTagRequest;
import com.harmonyocr.record.dto.TagResponse;
import com.harmonyocr.record.dto.UpdateTagRequest;
import com.harmonyocr.record.entity.RecognitionRecordTagEntity;
import com.harmonyocr.record.entity.RecognitionTagEntity;
import com.harmonyocr.record.mapper.RecognitionRecordTagMapper;
import com.harmonyocr.record.mapper.RecognitionTagMapper;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Locale;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * OCR 历史标签业务服务，属于 record 模块。
 * 维护说明：所有标签操作都按当前登录用户隔离，标签名称和颜色不得承载 OCR 全文或敏感路径。
 */
@Service
public class TagService {

    private static final int MAX_TAG_NAME_LENGTH = 64;

    private final RecognitionTagMapper tagMapper;
    private final RecognitionRecordTagMapper recordTagMapper;

    public TagService(RecognitionTagMapper tagMapper, RecognitionRecordTagMapper recordTagMapper) {
        this.tagMapper = tagMapper;
        this.recordTagMapper = recordTagMapper;
    }

    /**
     * 创建当前用户的历史标签。
     * 参数包含标签名和可选颜色；返回标签元信息。可能抛出 VALIDATION_ERROR。
     */
    @Transactional
    public TagResponse create(Long userId, CreateTagRequest request) {
        String name = normalizeDisplayName(request.name());
        String normalizedName = normalizeNameForUniqueness(name);
        requireNameAvailable(userId, normalizedName, null);
        LocalDateTime now = LocalDateTime.now();
        RecognitionTagEntity entity = new RecognitionTagEntity();
        entity.setUserId(userId);
        entity.setName(name);
        entity.setNormalizedName(normalizedName);
        entity.setColor(blankToNull(request.color()));
        entity.setCreatedAt(now);
        entity.setUpdatedAt(now);
        try {
            tagMapper.insert(entity);
        } catch (DuplicateKeyException ex) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "tag name already exists");
        }
        return toResponse(entity);
    }

    /**
     * 查询当前用户的历史标签列表。
     * 参数为当前登录用户 ID；返回按创建时间排序的标签列表，不包含其他用户标签。
     */
    public List<TagResponse> list(Long userId) {
        return tagMapper.selectList(new LambdaQueryWrapper<RecognitionTagEntity>()
                        .eq(RecognitionTagEntity::getUserId, userId)
                        .orderByAsc(RecognitionTagEntity::getCreatedAt)
                        .orderByAsc(RecognitionTagEntity::getId))
                .stream()
                .map(this::toResponse)
                .toList();
    }

    /**
     * 更新当前用户拥有的标签。
     * 参数为当前用户 ID、标签 ID 和允许修改字段；返回更新后的标签。不存在或非本人标签统一返回 NOT_FOUND。
     */
    @Transactional
    public TagResponse update(Long userId, Long id, UpdateTagRequest request) {
        RecognitionTagEntity entity = ownedTag(userId, id);
        if (request.name() != null) {
            String name = normalizeDisplayName(request.name());
            String normalizedName = normalizeNameForUniqueness(name);
            requireNameAvailable(userId, normalizedName, id);
            entity.setName(name);
            entity.setNormalizedName(normalizedName);
        }
        if (request.color() != null) {
            entity.setColor(blankToNull(request.color()));
        }
        entity.setUpdatedAt(LocalDateTime.now());
        try {
            tagMapper.updateById(entity);
        } catch (DuplicateKeyException ex) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "tag name already exists");
        }
        return toResponse(entity);
    }

    /**
     * 删除当前用户拥有的标签及其绑定关系。
     * 参数为当前用户 ID 和标签 ID；返回值为空。安全注意：删除标签不删除 OCR 记录文本。
     */
    @Transactional
    public void delete(Long userId, Long id) {
        ownedTag(userId, id);
        recordTagMapper.delete(new LambdaQueryWrapper<RecognitionRecordTagEntity>()
                .eq(RecognitionRecordTagEntity::getUserId, userId)
                .eq(RecognitionRecordTagEntity::getTagId, id));
        tagMapper.deleteById(id);
    }

    /**
     * 删除指定用户的全部标签和绑定关系。
     * 参数为已通过认证流程确认的用户 ID；用于账号注销时清理标签元数据，不读取或记录 OCR 文本。
     */
    @Transactional
    public void deleteByUserId(Long userId) {
        recordTagMapper.delete(new LambdaQueryWrapper<RecognitionRecordTagEntity>()
                .eq(RecognitionRecordTagEntity::getUserId, userId));
        tagMapper.delete(new LambdaQueryWrapper<RecognitionTagEntity>()
                .eq(RecognitionTagEntity::getUserId, userId));
    }

    /**
     * 校验并返回当前用户拥有的标签。
     * 参数为当前用户 ID 和标签 ID；不存在或不属于当前用户时抛出 NOT_FOUND。
     */
    public RecognitionTagEntity ownedTag(Long userId, Long id) {
        if (id == null || id <= 0) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "tagId must be positive");
        }
        RecognitionTagEntity entity = tagMapper.selectOne(new LambdaQueryWrapper<RecognitionTagEntity>()
                .eq(RecognitionTagEntity::getId, id)
                .eq(RecognitionTagEntity::getUserId, userId));
        if (entity == null) {
            throw new BusinessException(ErrorCode.NOT_FOUND);
        }
        return entity;
    }

    /**
     * 查询指定记录已绑定的标签。
     * 参数为当前用户 ID 和记录 ID；返回标签响应列表。安全注意：调用方必须已校验记录归属。
     */
    public List<TagResponse> tagsForRecord(Long userId, Long recordId) {
        List<Long> tagIds = recordTagMapper.selectList(new LambdaQueryWrapper<RecognitionRecordTagEntity>()
                        .eq(RecognitionRecordTagEntity::getUserId, userId)
                        .eq(RecognitionRecordTagEntity::getRecordId, recordId))
                .stream()
                .map(RecognitionRecordTagEntity::getTagId)
                .toList();
        if (tagIds.isEmpty()) {
            return List.of();
        }
        return tagMapper.selectList(new LambdaQueryWrapper<RecognitionTagEntity>()
                        .eq(RecognitionTagEntity::getUserId, userId)
                        .in(RecognitionTagEntity::getId, tagIds)
                        .orderByAsc(RecognitionTagEntity::getCreatedAt)
                        .orderByAsc(RecognitionTagEntity::getId))
                .stream()
                .map(this::toResponse)
                .toList();
    }

    private void requireNameAvailable(Long userId, String normalizedName, Long currentTagId) {
        LambdaQueryWrapper<RecognitionTagEntity> wrapper = new LambdaQueryWrapper<RecognitionTagEntity>()
                .eq(RecognitionTagEntity::getUserId, userId)
                .eq(RecognitionTagEntity::getNormalizedName, normalizedName);
        if (currentTagId != null) {
            wrapper.ne(RecognitionTagEntity::getId, currentTagId);
        }
        if (tagMapper.selectCount(wrapper) > 0) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "tag name already exists");
        }
    }

    private TagResponse toResponse(RecognitionTagEntity entity) {
        return new TagResponse(
                entity.getId(),
                entity.getName(),
                entity.getColor(),
                entity.getCreatedAt(),
                entity.getUpdatedAt());
    }

    private String normalizeDisplayName(String value) {
        if (value == null || value.isBlank()) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "tag name is required");
        }
        String normalized = value.trim().replaceAll("\\s+", " ");
        if (normalized.length() > MAX_TAG_NAME_LENGTH) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "tag name must be at most 64 characters");
        }
        return normalized;
    }

    private String normalizeNameForUniqueness(String value) {
        return value.toLowerCase(Locale.ROOT);
    }

    private String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.trim();
    }
}
