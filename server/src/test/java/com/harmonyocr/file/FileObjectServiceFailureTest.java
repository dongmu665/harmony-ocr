package com.harmonyocr.file;

import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.config.MinioProperties;
import com.harmonyocr.file.config.FileUploadProperties;
import com.harmonyocr.file.entity.FileObjectEntity;
import com.harmonyocr.file.mapper.FileObjectMapper;
import com.harmonyocr.file.service.FileObjectService;
import com.harmonyocr.storage.ObjectStorageCleanupTaskService;
import com.harmonyocr.storage.ObjectStorageService;
import com.harmonyocr.storage.StoredObject;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.dao.DataAccessResourceFailureException;
import org.springframework.mock.web.MockMultipartFile;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.contains;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 文件对象服务失败补偿单元测试。
 * 维护说明：使用内存 TrackingStorage 验证上传元数据写库失败后的对象删除和待清理任务记录，不访问真实 MinIO。
 */
class FileObjectServiceFailureTest {

    @Test
    void uploadDeletesObjectWhenDatabaseInsertFailsAfterStoragePut() {
        FileObjectMapper mapper = mock(FileObjectMapper.class);
        ObjectStorageCleanupTaskService cleanupTaskService = mock(ObjectStorageCleanupTaskService.class);
        TrackingStorage storage = new TrackingStorage(false);
        FileObjectService service = service(mapper, storage, cleanupTaskService);
        when(mapper.insert(any(FileObjectEntity.class))).thenThrow(new DataAccessResourceFailureException("db down"));

        assertThatThrownBy(() -> service.upload(10L, pngFile()))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("File upload failed");

        assertThat(storage.putKeys).hasSize(1);
        assertThat(storage.deletedKeys).containsExactly(storage.putKeys.getFirst());
        verify(cleanupTaskService, never()).recordPendingDelete(any(), any(), any());
    }

    @Test
    void uploadRecordsPendingCleanupWhenDatabaseInsertAndCompensationDeleteBothFail() {
        FileObjectMapper mapper = mock(FileObjectMapper.class);
        ObjectStorageCleanupTaskService cleanupTaskService = mock(ObjectStorageCleanupTaskService.class);
        TrackingStorage storage = new TrackingStorage(true);
        FileObjectService service = service(mapper, storage, cleanupTaskService);
        when(mapper.insert(any(FileObjectEntity.class))).thenThrow(new DataAccessResourceFailureException("db down"));

        assertThatThrownBy(() -> service.upload(10L, pngFile()))
                .isInstanceOf(BusinessException.class)
                .hasMessageContaining("File upload failed");

        assertThat(storage.putKeys).hasSize(1);
        assertThat(storage.deletedKeys).containsExactly(storage.putKeys.getFirst());
        verify(cleanupTaskService).recordPendingDelete(eq("harmony-ocr-test"), eq(storage.putKeys.getFirst()), contains("upload metadata save failed"));
    }

    private FileObjectService service(
            FileObjectMapper mapper,
            ObjectStorageService storage,
            ObjectStorageCleanupTaskService cleanupTaskService) {
        return new FileObjectService(
                mapper,
                storage,
                new FileUploadProperties(1024),
                new MinioProperties("http://localhost:9000", "test", "test", "harmony-ocr-test"),
                cleanupTaskService);
    }

    private MockMultipartFile pngFile() {
        return new MockMultipartFile("file", "receipt.png", "image/png", new byte[]{
                (byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
                0x00, 0x00, 0x00, 0x0D
        });
    }

    private static final class TrackingStorage implements ObjectStorageService {
        private final boolean failDelete;
        private final List<String> putKeys = new ArrayList<>();
        private final List<String> deletedKeys = new ArrayList<>();

        private TrackingStorage(boolean failDelete) {
            this.failDelete = failDelete;
        }

        /**
         * 记录模拟上传对象并消费输入流。
         * 参数 objectKey 为测试生成 key；返回值只用于验证补偿删除链路。
         */
        @Override
        public StoredObject putObject(String objectKey, InputStream inputStream, long size, String contentType) {
            try {
                inputStream.readAllBytes();
            } catch (IOException ex) {
                throw new IllegalStateException(ex);
            }
            putKeys.add(objectKey);
            return new StoredObject(objectKey, size, contentType);
        }

        /**
         * 模拟对象存储删除行为。
         * failDelete 为 true 时故意抛异常，用于验证服务层会登记待清理任务。
         */
        @Override
        public void deleteObject(String objectKey) {
            deletedKeys.add(objectKey);
            if (failDelete) {
                throw new IllegalStateException("delete failed");
            }
        }
    }
}
