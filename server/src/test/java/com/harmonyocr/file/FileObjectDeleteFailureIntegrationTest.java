package com.harmonyocr.file;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.harmonyocr.storage.ObjectStorageService;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doThrow;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@ActiveProfiles("test")
@AutoConfigureMockMvc
@SpringBootTest
/**
 * 文件对象删除失败补偿集成测试。
 * 维护说明：验证数据库删除和对象存储删除失败时会记录待清理任务，不泄露 objectKey 以外的文件内容。
 */
class FileObjectDeleteFailureIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @MockBean
    private ObjectStorageService objectStorageService;

    @BeforeEach
    void cleanDatabase() {
        jdbcTemplate.update("DELETE FROM object_storage_cleanup_tasks");
        jdbcTemplate.update("DELETE FROM file_objects");
        jdbcTemplate.update("DELETE FROM recognition_blocks");
        jdbcTemplate.update("DELETE FROM recognition_records");
        jdbcTemplate.update("DELETE FROM refresh_tokens");
        jdbcTemplate.update("DELETE FROM user_devices");
        jdbcTemplate.update("DELETE FROM export_jobs");
        jdbcTemplate.update("DELETE FROM batch_ocr_items");
        jdbcTemplate.update("DELETE FROM batch_ocr_jobs");
        jdbcTemplate.update("DELETE FROM users");
    }

    @Test
    void deleteFileMarksMetadataDeletedAndStorageDeleteFailedWhenObjectStorageDeleteFails() throws Exception {
        register("alice", "password123");
        Long fileId = insertFile(userId("alice"), "files/2026/05/25/delete-failure.png");
        doThrow(new IllegalStateException("storage unavailable")).when(objectStorageService).deleteObject(anyString());

        mockMvc.perform(delete("/api/v1/files/{id}", fileId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value("OK"));

        Map<String, Object> row = jdbcTemplate.queryForMap("""
                SELECT deleted, deleted_at, storage_delete_status, storage_delete_attempts, last_storage_delete_error
                FROM file_objects WHERE id = ?
                """, fileId);
        assertThat(((Number) row.get("deleted")).intValue()).isEqualTo(1);
        assertThat(row.get("deleted_at")).isNotNull();
        assertThat(row.get("storage_delete_status")).isEqualTo("DELETE_FAILED");
        assertThat(((Number) row.get("storage_delete_attempts")).intValue()).isEqualTo(1);
        assertThat(row.get("last_storage_delete_error")).asString().contains("IllegalStateException");

        mockMvc.perform(get("/api/v1/files/{id}", fileId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice"))))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));
    }

    private Long insertFile(Long userId, String objectKey) {
        jdbcTemplate.update("""
                INSERT INTO file_objects
                    (user_id, object_key, original_filename, content_type, file_size, file_hash, storage_provider, bucket_name,
                     deleted, created_at, storage_delete_status)
                VALUES (?, ?, 'image.png', 'image/png', 12, 'hash', 'minio', 'harmony-ocr-test', 0, CURRENT_TIMESTAMP, 'ACTIVE')
                """, userId, objectKey);
        return jdbcTemplate.queryForObject("SELECT MAX(id) FROM file_objects", Long.class);
    }

    private void register(String username, String password) throws Exception {
        mockMvc.perform(post("/api/v1/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", password))))
                .andExpect(status().isOk());
    }

    private String accessToken(String username) throws Exception {
        return login(username, "password123").path("data").path("accessToken").asText();
    }

    private JsonNode login(String username, String password) throws Exception {
        MvcResult result = mockMvc.perform(post("/api/v1/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", password))))
                .andExpect(status().isOk())
                .andReturn();
        return objectMapper.readTree(result.getResponse().getContentAsString());
    }

    private Long userId(String username) {
        return jdbcTemplate.queryForObject("SELECT id FROM users WHERE username = ?", Long.class, username);
    }

    private String bearer(String accessToken) {
        return "Bearer " + accessToken;
    }

    private String json(Object value) throws Exception {
        return objectMapper.writeValueAsString(value);
    }
}
