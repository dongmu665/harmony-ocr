package com.harmonyocr.record.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.harmonyocr.common.api.PageResult;
import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.file.service.FileObjectService;
import com.harmonyocr.record.dto.CreateRecordRequest;
import com.harmonyocr.record.dto.RecordBlockRequest;
import com.harmonyocr.record.dto.RecordBlockResponse;
import com.harmonyocr.record.dto.RecordPageRequest;
import com.harmonyocr.record.dto.RecordPageResponse;
import com.harmonyocr.record.dto.RecordResponse;
import com.harmonyocr.record.dto.RecordSearchQuery;
import com.harmonyocr.record.dto.TagResponse;
import com.harmonyocr.record.dto.UpdateRecordRequest;
import com.harmonyocr.record.entity.RecognitionBlockEntity;
import com.harmonyocr.record.entity.RecognitionRecordPageBlockEntity;
import com.harmonyocr.record.entity.RecognitionRecordPageEntity;
import com.harmonyocr.record.entity.RecognitionRecordTagEntity;
import com.harmonyocr.record.entity.RecognitionRecordEntity;
import com.harmonyocr.record.mapper.RecognitionBlockMapper;
import com.harmonyocr.record.mapper.RecognitionRecordPageBlockMapper;
import com.harmonyocr.record.mapper.RecognitionRecordPageMapper;
import com.harmonyocr.record.mapper.RecognitionRecordTagMapper;
import com.harmonyocr.record.mapper.RecognitionRecordMapper;
import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.format.DateTimeParseException;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * OCR 历史记录业务服务，属于 record 模块。
 * 维护说明：集中处理创建、列表、详情、更新、收藏、搜索和软删除规则；所有入口都必须使用当前登录用户 ID 做 ownership check。
 */
@Service
public class RecordService {

    private static final Set<String> ALLOWED_SOURCE_TYPES = Set.of("camera", "album", "import", "pdf", "batch");
    private static final int DEFAULT_PAGE = 0;
    private static final int DEFAULT_SIZE = 20;
    private static final int MAX_SIZE = 100;

    private final RecognitionRecordMapper recordMapper;
    private final RecognitionBlockMapper blockMapper;
    private final RecognitionRecordPageMapper pageMapper;
    private final RecognitionRecordPageBlockMapper pageBlockMapper;
    private final RecognitionRecordTagMapper recordTagMapper;
    private final FileObjectService fileObjectService;
    private final TagService tagService;

    public RecordService(
            RecognitionRecordMapper recordMapper,
            RecognitionBlockMapper blockMapper,
            RecognitionRecordPageMapper pageMapper,
            RecognitionRecordPageBlockMapper pageBlockMapper,
            RecognitionRecordTagMapper recordTagMapper,
            FileObjectService fileObjectService,
            TagService tagService) {
        this.recordMapper = recordMapper;
        this.blockMapper = blockMapper;
        this.pageMapper = pageMapper;
        this.pageBlockMapper = pageBlockMapper;
        this.recordTagMapper = recordTagMapper;
        this.fileObjectService = fileObjectService;
        this.tagService = tagService;
    }

    /**
     * 为当前登录用户创建 OCR 历史记录。
     * 参数包含来源、文本、对象存储 key 和可选文本块；返回保存后的详情。可能抛出 VALIDATION_ERROR。
     * 安全注意：userId 只能来自认证上下文，OCR 文本属于隐私敏感数据，不得写入日志或发送第三方。
     */
    @Transactional
    public RecordResponse create(Long userId, CreateRecordRequest request) {
        String sourceType = normalizeSourceType(request.sourceType());
        validateBusinessContent(request);
        fileObjectService.requireOwnedActiveObjectKey(userId, blankToNull(request.imageObjectKey()));
        LocalDateTime now = LocalDateTime.now();

        RecognitionRecordEntity record = new RecognitionRecordEntity();
        record.setUserId(userId);
        record.setTitle(blankToNull(request.title()));
        record.setSourceType(sourceType);
        record.setImageObjectKey(blankToNull(request.imageObjectKey()));
        record.setRawText(request.rawText());
        record.setEditedText(request.editedText());
        record.setLanguage(blankToNull(request.language()));
        record.setOcrEngine(blankToNull(request.ocrEngine()));
        record.setDurationMs(request.durationMs());
        record.setFavorite(Boolean.TRUE.equals(request.favorite()));
        record.setDeleted(false);
        record.setCreatedAt(now);
        record.setUpdatedAt(now);
        recordMapper.insert(record);

        saveBlocks(record.getId(), request.blocks(), now);
        savePages(record.getId(), request.pages(), now);
        return detail(userId, record.getId());
    }

    /**
     * 分页查询当前用户的未删除 OCR 历史记录。
     * 参数为当前用户 ID、分页和可选筛选条件；返回统一分页结构。安全注意：查询条件始终附加 userId 和 deleted=false。
     */
    public PageResult<RecordResponse> list(
            Long userId,
            Integer page,
            Integer size,
            Boolean favorite,
            String sourceType,
            String keyword,
            String createdFrom,
            String createdTo) {
        RecordSearchQuery query = new RecordSearchQuery(
                page, size, favorite, sourceType, keyword, createdFrom, createdTo, null, null, null, null, null);
        return list(userId, query);
    }

    /**
     * 按高级条件分页查询当前用户的 OCR 历史记录。
     * 参数包含关键词、日期、来源、收藏、标签、OCR 引擎和排序；返回当前用户未删除记录分页。
     * 安全注意：tagId 会先校验归属，sort 只接受白名单值，避免跨用户读取或 SQL 注入。
     */
    public PageResult<RecordResponse> list(Long userId, RecordSearchQuery query) {
        String normalizedSourceType = query.sourceType() == null || query.sourceType().isBlank()
                ? null
                : normalizeSourceType(query.sourceType());
        String normalizedOcrEngine = blankToNull(query.ocrEngine());
        LocalDateTime from = resolveFilterTime(query.createdFrom(), query.dateFrom(), "dateFrom");
        LocalDateTime to = resolveFilterTime(query.createdTo(), query.dateTo(), "dateTo");
        if (from != null && to != null && from.isAfter(to)) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "dateFrom must not be after dateTo");
        }
        Long tagId = safeTagId(userId, query.tagId());
        SortSpec sortSpec = parseSort(query.sort());
        return pageRecords(
                userId,
                query.page(),
                query.size(),
                query.favorite(),
                normalizedSourceType,
                query.keyword(),
                from,
                to,
                tagId,
                normalizedOcrEngine,
                sortSpec);
    }

    /**
     * 查询当前用户拥有的单条 OCR 历史详情。
     * 参数为当前用户 ID 和记录 ID；返回包含文本块的详情。不存在、已删除或不属于当前用户时统一抛出 NOT_FOUND。
     */
    public RecordResponse detail(Long userId, Long id) {
        RecognitionRecordEntity record = ownedActiveRecord(userId, id);
        return toResponse(record, blocks(record.getId()), tagService.tagsForRecord(userId, record.getId()), pages(record.getId()));
    }

    /**
     * 修改当前用户拥有的 OCR 历史记录。
     * 参数为当前用户 ID、记录 ID 和允许修改的字段；返回更新后的详情。安全注意：不允许修改 userId、sourceType 和删除状态。
     */
    @Transactional
    public RecordResponse update(Long userId, Long id, UpdateRecordRequest request) {
        RecognitionRecordEntity record = ownedActiveRecord(userId, id);
        if (request.title() != null) {
            record.setTitle(blankToNull(request.title()));
        }
        if (request.editedText() != null) {
            record.setEditedText(request.editedText());
        }
        if (request.favorite() != null) {
            record.setFavorite(request.favorite());
        }
        record.setUpdatedAt(LocalDateTime.now());
        recordMapper.updateById(record);
        return detail(userId, id);
    }

    /**
     * 替换后端生成的 OCR 正文、块和页级结果。
     * 参数 userId 与 id 仍按当前用户归属校验；request 只能更新同 sourceType 的系统生成内容。
     * 安全注意：该方法供批量 OCR/PDF 等后端流程内部使用，不接受客户端 userId，也不记录 OCR 全文。
     */
    @Transactional
    public RecordResponse replaceGeneratedContent(Long userId, Long id, CreateRecordRequest request) {
        String sourceType = normalizeSourceType(request.sourceType());
        validateBusinessContent(request);
        fileObjectService.requireOwnedActiveObjectKey(userId, blankToNull(request.imageObjectKey()));
        RecognitionRecordEntity record = ownedActiveRecord(userId, id);
        if (!sourceType.equals(record.getSourceType())) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "sourceType cannot change");
        }
        LocalDateTime now = LocalDateTime.now();
        record.setImageObjectKey(blankToNull(request.imageObjectKey()));
        record.setRawText(request.rawText());
        record.setEditedText(request.editedText());
        record.setLanguage(blankToNull(request.language()));
        record.setOcrEngine(blankToNull(request.ocrEngine()));
        record.setDurationMs(request.durationMs());
        record.setUpdatedAt(now);
        recordMapper.updateById(record);

        blockMapper.delete(new LambdaQueryWrapper<RecognitionBlockEntity>()
                .eq(RecognitionBlockEntity::getRecordId, id));
        pageBlockMapper.delete(new LambdaQueryWrapper<RecognitionRecordPageBlockEntity>()
                .eq(RecognitionRecordPageBlockEntity::getRecordId, id));
        pageMapper.delete(new LambdaQueryWrapper<RecognitionRecordPageEntity>()
                .eq(RecognitionRecordPageEntity::getRecordId, id));
        saveBlocks(id, request.blocks(), now);
        savePages(id, request.pages(), now);
        return detail(userId, id);
    }

    /**
     * 软删除当前用户拥有的 OCR 历史记录。
     * 参数为当前用户 ID 和记录 ID；方法不返回业务数据。不存在、已删除或不属于当前用户时统一抛出 NOT_FOUND。
     * 安全注意：本阶段不删除 MinIO 对象，只标记记录删除状态供云同步和后续文件模块清理。
     */
    @Transactional
    public void softDelete(Long userId, Long id) {
        LocalDateTime now = LocalDateTime.now();
        int updated = recordMapper.update(null, new LambdaUpdateWrapper<RecognitionRecordEntity>()
                .eq(RecognitionRecordEntity::getId, id)
                .eq(RecognitionRecordEntity::getUserId, userId)
                .eq(RecognitionRecordEntity::getDeleted, false)
                .set(RecognitionRecordEntity::getDeleted, true)
                .set(RecognitionRecordEntity::getDeletedAt, now)
                .set(RecognitionRecordEntity::getUpdatedAt, now));
        if (updated == 0) {
            throw new BusinessException(ErrorCode.NOT_FOUND);
        }
        recordTagMapper.delete(new LambdaQueryWrapper<RecognitionRecordTagEntity>()
                .eq(RecognitionRecordTagEntity::getUserId, userId)
                .eq(RecognitionRecordTagEntity::getRecordId, id));
    }

    /**
     * 设置当前用户拥有记录的收藏状态。
     * 参数为当前用户 ID、记录 ID 和目标收藏值；返回更新后的详情。安全注意：已删除或非本人记录统一按 NOT_FOUND 处理。
     */
    @Transactional
    public RecordResponse favorite(Long userId, Long id, Boolean favorite) {
        RecognitionRecordEntity record = ownedActiveRecord(userId, id);
        record.setFavorite(favorite);
        record.setUpdatedAt(LocalDateTime.now());
        recordMapper.updateById(record);
        return detail(userId, id);
    }

    /**
     * 搜索当前用户的 OCR 历史记录。
     * 参数为当前用户 ID、关键词和分页；空关键词按普通列表返回。安全注意：搜索仅在当前用户未删除记录范围内匹配标题和 OCR 文本。
     */
    public PageResult<RecordResponse> search(Long userId, String keyword, Integer page, Integer size) {
        RecordSearchQuery query = new RecordSearchQuery(
                page, size, null, null, keyword, null, null, null, null, null, null, null);
        return list(userId, query);
    }

    /**
     * 为当前用户拥有的记录绑定标签。
     * 参数为当前用户 ID、记录 ID 和标签 ID；重复绑定按幂等成功处理。不存在、已删除或越权统一返回 NOT_FOUND。
     */
    @Transactional
    public RecordResponse addTag(Long userId, Long recordId, Long tagId) {
        RecognitionRecordEntity record = ownedActiveRecord(userId, recordId);
        tagService.ownedTag(userId, tagId);
        Long existing = recordTagMapper.selectCount(new LambdaQueryWrapper<RecognitionRecordTagEntity>()
                .eq(RecognitionRecordTagEntity::getUserId, userId)
                .eq(RecognitionRecordTagEntity::getRecordId, recordId)
                .eq(RecognitionRecordTagEntity::getTagId, tagId));
        if (existing == 0) {
            RecognitionRecordTagEntity binding = new RecognitionRecordTagEntity();
            binding.setUserId(userId);
            binding.setRecordId(recordId);
            binding.setTagId(tagId);
            binding.setCreatedAt(LocalDateTime.now());
            recordTagMapper.insert(binding);
        }
        touchRecord(record);
        return detail(userId, recordId);
    }

    /**
     * 移除当前用户记录上的标签绑定。
     * 参数为当前用户 ID、记录 ID 和标签 ID；未绑定按幂等成功处理。安全注意：先校验 record 和 tag 归属。
     */
    @Transactional
    public RecordResponse removeTag(Long userId, Long recordId, Long tagId) {
        RecognitionRecordEntity record = ownedActiveRecord(userId, recordId);
        tagService.ownedTag(userId, tagId);
        recordTagMapper.delete(new LambdaQueryWrapper<RecognitionRecordTagEntity>()
                .eq(RecognitionRecordTagEntity::getUserId, userId)
                .eq(RecognitionRecordTagEntity::getRecordId, recordId)
                .eq(RecognitionRecordTagEntity::getTagId, tagId));
        touchRecord(record);
        return detail(userId, recordId);
    }

    /**
     * 软删除并清空指定用户拥有的全部 OCR 历史记录，用于账号注销数据删除扩展点。
     * 参数为已认证的用户 ID；返回值为空。安全注意：会物理删除 blocks 并清空 OCR 原文、编辑文本、标题和图片 key，不能跨用户清理。
     */
    @Transactional
    public void softDeleteByUserId(Long userId) {
        LocalDateTime now = LocalDateTime.now();
        List<Long> recordIds = recordMapper.selectList(new LambdaQueryWrapper<RecognitionRecordEntity>()
                        .eq(RecognitionRecordEntity::getUserId, userId))
                .stream()
                .map(RecognitionRecordEntity::getId)
                .toList();
        if (!recordIds.isEmpty()) {
            blockMapper.delete(new LambdaQueryWrapper<RecognitionBlockEntity>()
                    .in(RecognitionBlockEntity::getRecordId, recordIds));
            pageBlockMapper.delete(new LambdaQueryWrapper<RecognitionRecordPageBlockEntity>()
                    .in(RecognitionRecordPageBlockEntity::getRecordId, recordIds));
            pageMapper.delete(new LambdaQueryWrapper<RecognitionRecordPageEntity>()
                    .in(RecognitionRecordPageEntity::getRecordId, recordIds));
            recordTagMapper.delete(new LambdaQueryWrapper<RecognitionRecordTagEntity>()
                    .eq(RecognitionRecordTagEntity::getUserId, userId));
        }
        recordMapper.update(null, new LambdaUpdateWrapper<RecognitionRecordEntity>()
                .eq(RecognitionRecordEntity::getUserId, userId)
                .set(RecognitionRecordEntity::getDeleted, true)
                .set(RecognitionRecordEntity::getDeletedAt, now)
                .set(RecognitionRecordEntity::getUpdatedAt, now)
                .set(RecognitionRecordEntity::getTitle, null)
                .set(RecognitionRecordEntity::getImageObjectKey, null)
                .set(RecognitionRecordEntity::getRawText, null)
                .set(RecognitionRecordEntity::getEditedText, null)
                .set(RecognitionRecordEntity::getLanguage, null)
                .set(RecognitionRecordEntity::getOcrEngine, null)
                .set(RecognitionRecordEntity::getFavorite, false));
        tagService.deleteByUserId(userId);
    }

    /**
     * 在数据库侧执行分页和筛选。
     * 参数包含当前用户、分页和筛选条件；返回当前页结果。安全注意：page/size 会先归一化，查询始终带 userId 与 deleted=false。
     */
    private PageResult<RecordResponse> pageRecords(
            Long userId,
            Integer page,
            Integer size,
            Boolean favorite,
            String sourceType,
            String keyword,
            LocalDateTime createdFrom,
            LocalDateTime createdTo,
            Long tagId,
            String ocrEngine,
            SortSpec sortSpec) {
        int safePage = safePage(page);
        int safeSize = safeSize(size);
        LambdaQueryWrapper<RecognitionRecordEntity> countWrapper =
                recordQuery(userId, favorite, sourceType, keyword, createdFrom, createdTo, tagId, ocrEngine);
        Long total = recordMapper.selectCount(countWrapper);
        long offset = (long) safePage * safeSize;
        LambdaQueryWrapper<RecognitionRecordEntity> wrapper =
                applySort(recordQuery(userId, favorite, sourceType, keyword, createdFrom, createdTo, tagId, ocrEngine), sortSpec)
                .last("LIMIT " + safeSize + " OFFSET " + offset);
        List<RecordResponse> items = recordMapper.selectList(wrapper)
                .stream()
                .map(record -> toResponse(
                        record,
                        blocks(record.getId()),
                        tagService.tagsForRecord(userId, record.getId()),
                        pages(record.getId())))
                .toList();
        return new PageResult<>(items, total, safePage, safeSize);
    }

    private LambdaQueryWrapper<RecognitionRecordEntity> recordQuery(
            Long userId,
            Boolean favorite,
            String sourceType,
            String keyword,
            LocalDateTime createdFrom,
            LocalDateTime createdTo,
            Long tagId,
            String ocrEngine) {
        LambdaQueryWrapper<RecognitionRecordEntity> wrapper = new LambdaQueryWrapper<RecognitionRecordEntity>()
                .eq(RecognitionRecordEntity::getUserId, userId)
                .eq(RecognitionRecordEntity::getDeleted, false);
        if (favorite != null) {
            wrapper.eq(RecognitionRecordEntity::getFavorite, favorite);
        }
        if (sourceType != null) {
            wrapper.eq(RecognitionRecordEntity::getSourceType, sourceType);
        }
        if (createdFrom != null) {
            wrapper.ge(RecognitionRecordEntity::getCreatedAt, createdFrom);
        }
        if (createdTo != null) {
            wrapper.le(RecognitionRecordEntity::getCreatedAt, createdTo);
        }
        if (ocrEngine != null) {
            wrapper.eq(RecognitionRecordEntity::getOcrEngine, ocrEngine);
        }
        if (tagId != null) {
            wrapper.exists("SELECT 1 FROM recognition_record_tags rt "
                    + "WHERE rt.record_id = recognition_records.id "
                    + "AND rt.user_id = " + userId
                    + " AND rt.tag_id = " + tagId);
        }
        if (keyword != null && !keyword.isBlank()) {
            String likeKeyword = keyword.trim();
            wrapper.and(scope -> scope
                    .like(RecognitionRecordEntity::getTitle, likeKeyword)
                    .or()
                    .like(RecognitionRecordEntity::getRawText, likeKeyword)
                    .or()
                    .like(RecognitionRecordEntity::getEditedText, likeKeyword));
        }
        return wrapper;
    }

    /**
     * 解析新旧日期筛选参数。
     * 参数 legacyValue 对应 createdFrom/createdTo，newValue 对应 dateFrom/dateTo；返回统一 LocalDateTime。
     */
    private LocalDateTime resolveFilterTime(String legacyValue, String newValue, String fieldName) {
        String selected = newValue != null && !newValue.isBlank() ? newValue : legacyValue;
        return parseFilterTime(selected, fieldName);
    }

    /**
     * 解析 V1.1 历史日期筛选参数。
     * 参数 value 为 ISO-8601 本地时间字符串；返回 null 表示未提供。安全注意：解析失败返回统一校验错误，不回显用户输入。
     */
    private LocalDateTime parseFilterTime(String value, String fieldName) {
        if (value == null || value.isBlank()) {
            return null;
        }
        try {
            return LocalDateTime.parse(value.trim());
        } catch (DateTimeParseException ex) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, fieldName + " must be ISO local date time");
        }
    }

    private RecognitionRecordEntity ownedActiveRecord(Long userId, Long id) {
        RecognitionRecordEntity record = recordMapper.selectOne(new LambdaQueryWrapper<RecognitionRecordEntity>()
                .eq(RecognitionRecordEntity::getId, id)
                .eq(RecognitionRecordEntity::getUserId, userId)
                .eq(RecognitionRecordEntity::getDeleted, false));
        if (record == null) {
            throw new BusinessException(ErrorCode.NOT_FOUND);
        }
        return record;
    }

    /**
     * 保存 OCR 文本块并检查 blockIndex 唯一性。
     * 参数为记录 ID、请求 blocks 和创建时间；返回值为空。安全注意：重复 blockIndex 会拒绝，避免覆盖或制造排序歧义。
     */
    private void saveBlocks(Long recordId, List<RecordBlockRequest> requests, LocalDateTime now) {
        if (requests == null || requests.isEmpty()) {
            return;
        }
        Set<Integer> blockIndexes = new HashSet<>();
        for (int i = 0; i < requests.size(); i++) {
            RecordBlockRequest request = requests.get(i);
            if (!hasBlockContent(request)) {
                continue;
            }
            Integer blockIndex = request.blockIndex() == null ? i : request.blockIndex();
            if (!blockIndexes.add(blockIndex)) {
                throw new BusinessException(ErrorCode.VALIDATION_ERROR, "blockIndex must be unique in one record");
            }
            RecognitionBlockEntity block = new RecognitionBlockEntity();
            block.setRecordId(recordId);
            block.setBlockIndex(blockIndex);
            block.setText(request.text());
            block.setConfidence(request.confidence());
            block.setBoundingBox(blankToNull(request.boundingBox()));
            block.setCreatedAt(now);
            blockMapper.insert(block);
        }
    }

    private List<RecordBlockResponse> blocks(Long recordId) {
        return blockMapper.selectList(new LambdaQueryWrapper<RecognitionBlockEntity>()
                        .eq(RecognitionBlockEntity::getRecordId, recordId))
                .stream()
                .sorted(Comparator.comparing(RecognitionBlockEntity::getBlockIndex, Comparator.nullsLast(Integer::compareTo)))
                .map(block -> new RecordBlockResponse(
                        block.getId(),
                        block.getBlockIndex(),
                        block.getText(),
                        block.getConfidence(),
                        block.getBoundingBox()))
                .toList();
    }

    private void savePages(Long recordId, List<RecordPageRequest> requests, LocalDateTime now) {
        if (requests == null || requests.isEmpty()) {
            return;
        }
        Set<Integer> pageIndexes = new HashSet<>();
        for (int i = 0; i < requests.size(); i++) {
            RecordPageRequest request = requests.get(i);
            if (!hasPageContent(request)) {
                continue;
            }
            int pageIndex = request.pageIndex() == null ? i : request.pageIndex();
            if (!pageIndexes.add(pageIndex)) {
                throw new BusinessException(ErrorCode.VALIDATION_ERROR, "pageIndex must be unique in one record");
            }
            RecognitionRecordPageEntity page = new RecognitionRecordPageEntity();
            page.setRecordId(recordId);
            page.setPageIndex(pageIndex);
            page.setPageNumber(request.pageNumber() == null ? pageIndex + 1 : request.pageNumber());
            page.setStatus(normalizePageStatus(request.status()));
            page.setRawText(blankToEmpty(request.rawText()));
            page.setEditedText(blankToEmpty(request.editedText()));
            page.setDurationMs(request.durationMs());
            page.setConfidence(toBigDecimal(request.confidence()));
            page.setErrorCode(blankToNull(request.errorCode()));
            page.setFailureReason(safeFailureReason(request.failureReason()));
            page.setCreatedAt(now);
            pageMapper.insert(page);
            savePageBlocks(recordId, page.getId(), request.blocks(), now);
        }
    }

    private void savePageBlocks(Long recordId, Long pageId, List<RecordBlockRequest> requests, LocalDateTime now) {
        if (requests == null || requests.isEmpty()) {
            return;
        }
        Set<Integer> blockIndexes = new HashSet<>();
        for (int i = 0; i < requests.size(); i++) {
            RecordBlockRequest request = requests.get(i);
            if (!hasBlockContent(request)) {
                continue;
            }
            Integer blockIndex = request.blockIndex() == null ? i : request.blockIndex();
            if (!blockIndexes.add(blockIndex)) {
                throw new BusinessException(ErrorCode.VALIDATION_ERROR, "page blockIndex must be unique in one page");
            }
            RecognitionRecordPageBlockEntity block = new RecognitionRecordPageBlockEntity();
            block.setRecordId(recordId);
            block.setPageId(pageId);
            block.setBlockIndex(blockIndex);
            block.setText(request.text());
            block.setConfidence(request.confidence());
            block.setBoundingBox(blankToNull(request.boundingBox()));
            block.setCreatedAt(now);
            pageBlockMapper.insert(block);
        }
    }

    private List<RecordPageResponse> pages(Long recordId) {
        return pageMapper.selectList(new LambdaQueryWrapper<RecognitionRecordPageEntity>()
                        .eq(RecognitionRecordPageEntity::getRecordId, recordId))
                .stream()
                .sorted(Comparator.comparing(RecognitionRecordPageEntity::getPageIndex, Comparator.nullsLast(Integer::compareTo)))
                .map(page -> new RecordPageResponse(
                        page.getId(),
                        page.getPageIndex(),
                        page.getPageNumber(),
                        page.getStatus(),
                        page.getRawText(),
                        page.getEditedText(),
                        page.getDurationMs(),
                        page.getConfidence() == null ? null : page.getConfidence().doubleValue(),
                        page.getErrorCode(),
                        page.getFailureReason(),
                        pageBlocks(page.getId())))
                .toList();
    }

    private List<RecordBlockResponse> pageBlocks(Long pageId) {
        return pageBlockMapper.selectList(new LambdaQueryWrapper<RecognitionRecordPageBlockEntity>()
                        .eq(RecognitionRecordPageBlockEntity::getPageId, pageId))
                .stream()
                .sorted(Comparator.comparing(RecognitionRecordPageBlockEntity::getBlockIndex, Comparator.nullsLast(Integer::compareTo)))
                .map(block -> new RecordBlockResponse(
                        block.getId(),
                        block.getBlockIndex(),
                        block.getText(),
                        block.getConfidence(),
                        block.getBoundingBox()))
                .toList();
    }

    private RecordResponse toResponse(RecognitionRecordEntity record, List<RecordBlockResponse> blocks) {
        return toResponse(record, blocks, tagService.tagsForRecord(record.getUserId(), record.getId()), pages(record.getId()));
    }

    private RecordResponse toResponse(
            RecognitionRecordEntity record,
            List<RecordBlockResponse> blocks,
            List<TagResponse> tags) {
        return toResponse(record, blocks, tags, pages(record.getId()));
    }

    private RecordResponse toResponse(
            RecognitionRecordEntity record,
            List<RecordBlockResponse> blocks,
            List<TagResponse> tags,
            List<RecordPageResponse> pages) {
        int pageCount = pages == null ? 0 : pages.size();
        int successPageCount = pages == null ? 0 : (int) pages.stream().filter(page -> "SUCCESS".equals(page.status())).count();
        int failedPageCount = pages == null ? 0 : (int) pages.stream().filter(page -> "FAILED".equals(page.status())).count();
        return new RecordResponse(
                record.getId(),
                record.getTitle(),
                record.getSourceType(),
                record.getImageObjectKey(),
                record.getRawText(),
                record.getEditedText(),
                record.getLanguage(),
                record.getOcrEngine(),
                record.getDurationMs(),
                Boolean.TRUE.equals(record.getFavorite()),
                record.getCreatedAt(),
                record.getUpdatedAt(),
                record.getDeletedAt(),
                blocks,
                tags,
                pages == null ? List.of() : pages,
                pageCount,
                successPageCount,
                failedPageCount,
                successPageCount > 0 && failedPageCount > 0);
    }

    private LambdaQueryWrapper<RecognitionRecordEntity> applySort(
            LambdaQueryWrapper<RecognitionRecordEntity> wrapper,
            SortSpec sortSpec) {
        if ("createdAt".equals(sortSpec.field())) {
            wrapper.orderBy(true, sortSpec.asc(), RecognitionRecordEntity::getCreatedAt);
        } else if ("updatedAt".equals(sortSpec.field())) {
            wrapper.orderBy(true, sortSpec.asc(), RecognitionRecordEntity::getUpdatedAt);
        } else if ("durationMs".equals(sortSpec.field())) {
            wrapper.orderBy(true, sortSpec.asc(), RecognitionRecordEntity::getDurationMs);
        }
        wrapper.orderBy(true, sortSpec.asc(), RecognitionRecordEntity::getId);
        return wrapper;
    }

    private SortSpec parseSort(String sort) {
        if (sort == null || sort.isBlank() || "createdAt_desc".equals(sort)) {
            return new SortSpec("createdAt", false);
        }
        return switch (sort) {
            case "createdAt_asc" -> new SortSpec("createdAt", true);
            case "updatedAt_desc" -> new SortSpec("updatedAt", false);
            case "updatedAt_asc" -> new SortSpec("updatedAt", true);
            case "durationMs_desc" -> new SortSpec("durationMs", false);
            case "durationMs_asc" -> new SortSpec("durationMs", true);
            default -> throw new BusinessException(ErrorCode.VALIDATION_ERROR, "sort is invalid");
        };
    }

    private Long safeTagId(Long userId, Long tagId) {
        if (tagId == null) {
            return null;
        }
        tagService.ownedTag(userId, tagId);
        return tagId;
    }

    private void touchRecord(RecognitionRecordEntity record) {
        record.setUpdatedAt(LocalDateTime.now());
        recordMapper.updateById(record);
    }

    private String normalizeSourceType(String sourceType) {
        if (sourceType == null || sourceType.isBlank()) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "sourceType is required");
        }
        String normalized = sourceType.trim().toLowerCase(Locale.ROOT);
        if (!ALLOWED_SOURCE_TYPES.contains(normalized)) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "sourceType must be camera, album, import, pdf or batch");
        }
        return normalized;
    }

    private void validateBusinessContent(CreateRecordRequest request) {
        boolean hasText = hasText(request.rawText()) || hasText(request.editedText());
        boolean hasImage = hasText(request.imageObjectKey());
        boolean hasBlocks = request.blocks() != null && request.blocks().stream().anyMatch(this::hasBlockContent);
        boolean hasPages = request.pages() != null && request.pages().stream().anyMatch(this::hasPageContent);
        if (!hasText && !hasImage && !hasBlocks && !hasPages) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "record content must not be empty");
        }
    }

    private int safePage(Integer page) {
        return page == null || page < 0 ? DEFAULT_PAGE : page;
    }

    private int safeSize(Integer size) {
        if (size == null || size <= 0) {
            return DEFAULT_SIZE;
        }
        return Math.min(size, MAX_SIZE);
    }

    private String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value;
    }

    private record SortSpec(String field, boolean asc) {
    }

    private boolean hasText(String value) {
        return value != null && !value.isBlank();
    }

    private boolean hasBlockContent(RecordBlockRequest block) {
        return block != null
                && (hasText(block.text()) || block.confidence() != null || hasText(block.boundingBox()));
    }

    private boolean hasPageContent(RecordPageRequest page) {
        return page != null
                && (hasText(page.rawText())
                || hasText(page.editedText())
                || hasText(page.errorCode())
                || hasText(page.failureReason())
                || (page.blocks() != null && page.blocks().stream().anyMatch(this::hasBlockContent)));
    }

    private String normalizePageStatus(String status) {
        String normalized = status == null ? "SUCCESS" : status.trim().toUpperCase(Locale.ROOT);
        if (!Set.of("SUCCESS", "FAILED").contains(normalized)) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "page status must be SUCCESS or FAILED");
        }
        return normalized;
    }

    private String safeFailureReason(String value) {
        String normalized = blankToNull(value);
        if (normalized == null) {
            return null;
        }
        return normalized.length() > 120 ? normalized.substring(0, 120) : normalized;
    }

    private String blankToEmpty(String value) {
        return value == null ? "" : value;
    }

    private BigDecimal toBigDecimal(Double value) {
        return value == null ? null : BigDecimal.valueOf(value);
    }
}
