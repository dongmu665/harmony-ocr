package com.harmonyocr.file.service;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.LambdaUpdateWrapper;
import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.config.MinioProperties;
import com.harmonyocr.file.config.FileUploadProperties;
import com.harmonyocr.file.dto.FileObjectResponse;
import com.harmonyocr.file.entity.FileObjectEntity;
import com.harmonyocr.file.entity.StorageDeleteStatus;
import com.harmonyocr.file.mapper.FileObjectMapper;
import com.harmonyocr.file.validation.FileTypeDetector;
import com.harmonyocr.storage.ObjectStorageCleanupTaskService;
import com.harmonyocr.storage.ObjectStorageService;
import java.io.ByteArrayInputStream;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.HexFormat;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

/**
 * 文件对象业务服务，属于 file 模块。
 * 维护说明：集中处理上传校验、object_key 生成、对象存储写入、元数据保存、ownership check 和软删除，确保文件二进制不进入 MySQL。
 */
@Service
public class FileObjectService {

    private static final String STORAGE_PROVIDER = "minio";
    private static final int MAX_STORAGE_ERROR_LENGTH = 512;
    private static final Set<String> ALLOWED_CONTENT_TYPES = Set.of(
            "image/jpeg",
            "image/png",
            "image/webp",
            "text/plain",
            "application/pdf");

    private final FileObjectMapper fileObjectMapper;
    private final ObjectStorageService objectStorageService;
    private final FileUploadProperties fileUploadProperties;
    private final MinioProperties minioProperties;
    private final ObjectStorageCleanupTaskService cleanupTaskService;

    public FileObjectService(
            FileObjectMapper fileObjectMapper,
            ObjectStorageService objectStorageService,
            FileUploadProperties fileUploadProperties,
            MinioProperties minioProperties,
            ObjectStorageCleanupTaskService cleanupTaskService) {
        this.fileObjectMapper = fileObjectMapper;
        this.objectStorageService = objectStorageService;
        this.fileUploadProperties = fileUploadProperties;
        this.minioProperties = minioProperties;
        this.cleanupTaskService = cleanupTaskService;
    }

    /**
     * 上传当前用户的文件对象。
     * 参数为认证用户 ID 和 multipart 文件；返回保存后的文件元数据。可能抛出 VALIDATION_ERROR、FILE_TYPE_NOT_ALLOWED、FILE_TOO_LARGE 或 UPLOAD_FAILED。
     * 安全注意：objectKey 由服务端生成且不包含 userId 或原始文件名，不能信任客户端路径或把文件内容写入日志。
     */
    @Transactional
    public FileObjectResponse upload(Long userId, MultipartFile file) {
        byte[] content = validateAndRead(file);
        String contentType = normalizedContentType(file.getContentType());
        String safeFilename = safeFilename(file.getOriginalFilename(), contentType);
        String objectKey = objectKey(contentType);

        try {
            objectStorageService.putObject(objectKey, new ByteArrayInputStream(content), content.length, contentType);
        } catch (RuntimeException ex) {
            throw new BusinessException(ErrorCode.UPLOAD_FAILED);
        }

        LocalDateTime now = LocalDateTime.now();
        FileObjectEntity entity = new FileObjectEntity();
        entity.setUserId(userId);
        entity.setObjectKey(objectKey);
        entity.setOriginalFilename(safeFilename);
        entity.setContentType(contentType);
        entity.setFileSize((long) content.length);
        entity.setFileHash(sha256(content));
        entity.setStorageProvider(STORAGE_PROVIDER);
        entity.setBucketName(minioProperties.bucket());
        entity.setDeleted(false);
        entity.setCreatedAt(now);
        entity.setStorageDeleteStatus(StorageDeleteStatus.ACTIVE.name());
        entity.setStorageDeleteAttempts(0);
        try {
            int inserted = fileObjectMapper.insert(entity);
            if (inserted != 1) {
                throw new IllegalStateException("file object metadata insert returned " + inserted);
            }
        } catch (RuntimeException ex) {
            compensateUploadedObject(minioProperties.bucket(), objectKey, ex);
            throw new BusinessException(ErrorCode.UPLOAD_FAILED);
        }
        return toResponse(entity);
    }

    /**
     * 查询当前用户拥有且未删除的文件对象。
     * 参数为认证用户 ID 和文件对象 ID；返回文件元数据。不存在、已删除或不归属当前用户时统一抛出 NOT_FOUND。
     */
    public FileObjectResponse detail(Long userId, Long id) {
        return toResponse(ownedActiveFile(userId, id));
    }

    /**
     * 校验 imageObjectKey 是否属于当前用户且仍处于有效状态。
     * 参数为当前用户 ID 和记录请求中的 imageObjectKey；返回匹配到的文件对象。安全注意：记录模块只能引用当前用户未删除文件，不能通过 objectKey 推断归属。
     */
    public FileObjectEntity requireOwnedActiveObjectKey(Long userId, String objectKey) {
        if (objectKey == null || objectKey.isBlank()) {
            return null;
        }
        FileObjectEntity fileObject = fileObjectMapper.selectOne(new LambdaQueryWrapper<FileObjectEntity>()
                .eq(FileObjectEntity::getUserId, userId)
                .eq(FileObjectEntity::getObjectKey, objectKey)
                .eq(FileObjectEntity::getDeleted, false));
        if (fileObject == null) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "imageObjectKey is not available for current user");
        }
        return fileObject;
    }

    /**
     * 软删除当前用户拥有的文件对象，并尝试删除对象存储文件。
     * 参数为认证用户 ID 和文件对象 ID；无返回值。安全注意：MinIO 删除失败不影响已完成的元数据软删除，也不向客户端泄露底层异常。
     */
    @Transactional
    public void softDelete(Long userId, Long id) {
        FileObjectEntity fileObject = ownedActiveFile(userId, id);
        softDeleteEntity(fileObject);
        tryDeleteObjectAndUpdateState(fileObject);
    }

    /**
     * 软删除指定用户全部文件对象，用于账号注销数据删除流程。
     * 参数为已认证用户 ID；无返回值。安全注意：只处理该 userId 范围内的文件对象，存储删除失败不阻断账号注销主流程。
     */
    @Transactional
    public void softDeleteByUserId(Long userId) {
        fileObjectMapper.selectList(new LambdaQueryWrapper<FileObjectEntity>()
                        .eq(FileObjectEntity::getUserId, userId)
                        .eq(FileObjectEntity::getDeleted, false))
                .forEach(fileObject -> {
                    softDeleteEntity(fileObject);
                    tryDeleteObjectAndUpdateState(fileObject);
                });
    }

    /**
     * 校验并读取上传文件内容。
     * 参数为 multipart 文件；返回完整字节数组。安全注意：Content-Type 只作为声明值，必须结合文件魔数或文本特征校验。
     */
    private byte[] validateAndRead(MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "file must not be empty");
        }
        String contentType = normalizedContentType(file.getContentType());
        if (!ALLOWED_CONTENT_TYPES.contains(contentType)) {
            throw new BusinessException(ErrorCode.FILE_TYPE_NOT_ALLOWED);
        }
        if (file.getSize() > fileUploadProperties.maxSizeBytes()) {
            throw new BusinessException(ErrorCode.FILE_TOO_LARGE);
        }
        try {
            byte[] content = file.getBytes();
            FileTypeDetector.requireContentMatches(contentType, content);
            return content;
        } catch (Exception ex) {
            if (ex instanceof BusinessException businessException) {
                throw businessException;
            }
            throw new BusinessException(ErrorCode.UPLOAD_FAILED);
        }
    }

    private String normalizedContentType(String contentType) {
        if (contentType == null || contentType.isBlank()) {
            throw new BusinessException(ErrorCode.FILE_TYPE_NOT_ALLOWED);
        }
        return contentType.trim().toLowerCase(Locale.ROOT);
    }

    private String safeFilename(String originalFilename, String contentType) {
        String candidate = originalFilename == null || originalFilename.isBlank()
                ? "file" + defaultExtension(contentType)
                : originalFilename.replace('\\', '/');
        int lastSlash = candidate.lastIndexOf('/');
        if (lastSlash >= 0) {
            candidate = candidate.substring(lastSlash + 1);
        }
        candidate = candidate.replaceAll("[^A-Za-z0-9._-]", "_");
        while (candidate.startsWith(".")) {
            candidate = candidate.substring(1);
        }
        if (candidate.isBlank()) {
            return "file" + defaultExtension(contentType);
        }
        return candidate.length() > 128 ? candidate.substring(candidate.length() - 128) : candidate;
    }

    private String defaultExtension(String contentType) {
        return switch (contentType) {
            case "image/jpeg" -> ".jpg";
            case "image/png" -> ".png";
            case "image/webp" -> ".webp";
            case "text/plain" -> ".txt";
            case "application/pdf" -> ".pdf";
            default -> "";
        };
    }

    /**
     * 生成不可预测的对象存储 key。
     * 参数为已通过白名单的内容类型；返回不包含 userId 和原始文件名的 key，避免响应或日志间接暴露用户身份和路径布局。
     */
    private String objectKey(String contentType) {
        LocalDate today = LocalDate.now();
        return "files/%04d/%02d/%02d/%s%s".formatted(
                today.getYear(),
                today.getMonthValue(),
                today.getDayOfMonth(),
                UUID.randomUUID(),
                defaultExtension(contentType));
    }

    private String sha256(byte[] content) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            return HexFormat.of().formatHex(digest.digest(content));
        } catch (NoSuchAlgorithmException ex) {
            throw new BusinessException(ErrorCode.UPLOAD_FAILED);
        }
    }

    private FileObjectEntity ownedActiveFile(Long userId, Long id) {
        FileObjectEntity fileObject = fileObjectMapper.selectOne(new LambdaQueryWrapper<FileObjectEntity>()
                .eq(FileObjectEntity::getId, id)
                .eq(FileObjectEntity::getUserId, userId)
                .eq(FileObjectEntity::getDeleted, false));
        if (fileObject == null) {
            throw new BusinessException(ErrorCode.NOT_FOUND);
        }
        return fileObject;
    }

    private void softDeleteEntity(FileObjectEntity fileObject) {
        LocalDateTime now = LocalDateTime.now();
        int updated = fileObjectMapper.update(null, new LambdaUpdateWrapper<FileObjectEntity>()
                .eq(FileObjectEntity::getId, fileObject.getId())
                .eq(FileObjectEntity::getUserId, fileObject.getUserId())
                .eq(FileObjectEntity::getDeleted, false)
                .set(FileObjectEntity::getDeleted, true)
                .set(FileObjectEntity::getDeletedAt, now)
                .set(FileObjectEntity::getOriginalFilename, null)
                .set(FileObjectEntity::getFileHash, null));
        if (updated == 0) {
            throw new BusinessException(ErrorCode.NOT_FOUND);
        }
        fileObject.setDeleted(true);
        fileObject.setDeletedAt(now);
    }

    /**
     * 尝试删除对象存储文件并写入删除状态。
     * 参数为已完成业务软删除的文件对象；返回值为空。安全注意：删除失败只记录脱敏错误摘要，用户侧仍不可访问该文件。
     */
    private void tryDeleteObjectAndUpdateState(FileObjectEntity fileObject) {
        LocalDateTime now = LocalDateTime.now();
        try {
            objectStorageService.deleteObject(fileObject.getObjectKey());
            fileObjectMapper.update(null, new LambdaUpdateWrapper<FileObjectEntity>()
                    .eq(FileObjectEntity::getId, fileObject.getId())
                    .set(FileObjectEntity::getObjectKey, "deleted/file/" + fileObject.getId())
                    .set(FileObjectEntity::getStorageDeleteStatus, StorageDeleteStatus.DELETED.name())
                    .set(FileObjectEntity::getStorageDeletedAt, now)
                    .set(FileObjectEntity::getLastStorageDeleteAttemptAt, now)
                    .set(FileObjectEntity::getLastStorageDeleteError, null)
                    .setSql("storage_delete_attempts = storage_delete_attempts + 1"));
        } catch (RuntimeException ex) {
            fileObjectMapper.update(null, new LambdaUpdateWrapper<FileObjectEntity>()
                    .eq(FileObjectEntity::getId, fileObject.getId())
                    .set(FileObjectEntity::getStorageDeleteStatus, StorageDeleteStatus.DELETE_FAILED.name())
                    .set(FileObjectEntity::getLastStorageDeleteAttemptAt, now)
                    .set(FileObjectEntity::getLastStorageDeleteError, safeError(ex))
                    .setSql("storage_delete_attempts = storage_delete_attempts + 1"));
        }
    }

    /**
     * 处理“对象已上传但数据库元数据保存失败”的补偿删除。
     * 参数为 bucket、objectKey 和保存异常；返回值为空。安全注意：补偿删除失败时只记录待清理线索，不写文件内容或密钥。
     */
    private void compensateUploadedObject(String bucketName, String objectKey, RuntimeException saveFailure) {
        try {
            objectStorageService.deleteObject(objectKey);
        } catch (RuntimeException deleteFailure) {
            cleanupTaskService.recordPendingDelete(
                    bucketName,
                    objectKey,
                    "upload metadata save failed: " + saveFailure.getClass().getSimpleName());
        }
    }

    private String safeError(RuntimeException ex) {
        String value = ex.getClass().getSimpleName();
        if (ex.getMessage() != null && !ex.getMessage().isBlank()) {
            value = value + ": " + ex.getMessage();
        }
        return value.length() <= MAX_STORAGE_ERROR_LENGTH ? value : value.substring(0, MAX_STORAGE_ERROR_LENGTH);
    }

    /**
     * 构造文件对象响应。
     * 参数为已通过归属校验的文件实体；返回给前端的 objectKey 只能来自服务端记录。
     * 安全注意：本阶段不生成签名 URL，因此 accessUrl 和 expiresAt 固定为空。
     */
    private FileObjectResponse toResponse(FileObjectEntity entity) {
        return new FileObjectResponse(
                entity.getId(),
                entity.getObjectKey(),
                entity.getOriginalFilename(),
                entity.getContentType(),
                entity.getFileSize(),
                null,
                null,
                entity.getOriginalFilename(),
                entity.getContentType(),
                entity.getFileSize(),
                entity.getFileHash(),
                entity.getStorageProvider(),
                entity.getCreatedAt());
    }
}
