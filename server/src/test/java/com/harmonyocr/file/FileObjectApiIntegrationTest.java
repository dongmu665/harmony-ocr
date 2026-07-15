package com.harmonyocr.file;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import static org.hamcrest.Matchers.nullValue;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 文件对象 API 集成测试。
 * 维护说明：覆盖上传类型/大小校验、对象存储 key 持久化、用户归属校验和统一错误响应。
 */
@ActiveProfiles("test")
@AutoConfigureMockMvc
@SpringBootTest
class FileObjectApiIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private JdbcTemplate jdbcTemplate;

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
    void uploadWithoutAccessTokenReturnsUnauthorizedUnifiedResponse() throws Exception {
        mockMvc.perform(multipart("/api/v1/files/upload")
                        .file(textFile("note.txt", "hello")))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"))
                .andExpect(jsonPath("$.timestamp").exists());
    }

    @Test
    void uploadValidFileStoresCurrentUserMetadataAndReturnsResponse() throws Exception {
        register("alice", "password123");
        Long userId = userId("alice");

        MvcResult result = upload(accessToken("alice"), imageFile("receipt.png", validPng()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.code").value("OK"))
                .andExpect(jsonPath("$.data.id").isNumber())
                .andExpect(jsonPath("$.data.objectKey").isNotEmpty())
                .andExpect(jsonPath("$.data.fileName").value("receipt.png"))
                .andExpect(jsonPath("$.data.mimeType").value("image/png"))
                .andExpect(jsonPath("$.data.size").value(validPng().length))
                .andExpect(jsonPath("$.data.accessUrl").value(nullValue()))
                .andExpect(jsonPath("$.data.expiresAt").value(nullValue()))
                .andExpect(jsonPath("$.data.originalFilename").value("receipt.png"))
                .andExpect(jsonPath("$.data.contentType").value("image/png"))
                .andExpect(jsonPath("$.data.fileSize").value(validPng().length))
                .andExpect(jsonPath("$.data.fileHash").isNotEmpty())
                .andExpect(jsonPath("$.data.storageProvider").value("minio"))
                .andReturn();

        Long fileId = jsonNode(result).path("data").path("id").asLong();
        String responseObjectKey = jsonNode(result).path("data").path("objectKey").asText();
        assertThat(responseObjectKey).startsWith("files/");
        assertThat(responseObjectKey).matches("files/\\d{4}/\\d{2}/\\d{2}/[0-9a-f-]{36}\\.png");
        assertThat(responseObjectKey).doesNotContain("alice");
        assertThat(responseObjectKey).doesNotContain("receipt.png");
        assertThat(responseObjectKey).doesNotContain("..");
        Map<String, Object> row = jdbcTemplate.queryForMap(
                "SELECT user_id, object_key, original_filename, content_type, file_size, file_hash, deleted FROM file_objects WHERE id = ?",
                fileId);
        assertThat(row.get("user_id")).isEqualTo(userId);
        assertThat(row.get("object_key")).isEqualTo(responseObjectKey);
        assertThat(row.get("object_key")).asString().startsWith("files/");
        assertThat(row.get("object_key")).asString().matches("files/\\d{4}/\\d{2}/\\d{2}/[0-9a-f-]{36}\\.png");
        assertThat(row.get("object_key")).asString().doesNotContain("receipt.png");
        assertThat(row.get("original_filename")).isEqualTo("receipt.png");
        assertThat(row.get("content_type")).isEqualTo("image/png");
        assertThat(((Number) row.get("file_size")).longValue()).isEqualTo(validPng().length);
        assertThat(row.get("file_hash")).asString().hasSize(64);
        assertThat(((Number) row.get("deleted")).intValue()).isZero();
    }

    @Test
    void uploadRejectsEmptyFileIllegalContentTypeMismatchedMagicAndOversizedFile() throws Exception {
        register("alice", "password123");
        String token = accessToken("alice");

        upload(token, new MockMultipartFile("file", "empty.png", "image/png", new byte[0]))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));

        upload(token, new MockMultipartFile("file", "run.exe", "application/x-msdownload", new byte[]{1}))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("FILE_TYPE_NOT_ALLOWED"));

        upload(token, imageFile("fake.png", "not a png".getBytes(java.nio.charset.StandardCharsets.UTF_8)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("FILE_TYPE_NOT_ALLOWED"));

        upload(token, new MockMultipartFile("file", "fake.pdf", "application/pdf",
                        "plain text".getBytes(java.nio.charset.StandardCharsets.UTF_8)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("FILE_TYPE_NOT_ALLOWED"));

        upload(token, new MockMultipartFile("file", "huge.txt", "text/plain", new byte[10 * 1024 * 1024 + 1]))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("FILE_TOO_LARGE"));
    }

    @Test
    void uploadAcceptsAllowedTypesOnlyWhenDeclaredTypeMatchesContentSignature() throws Exception {
        register("alice", "password123");
        String token = accessToken("alice");

        upload(token, imageFile("ok.png", validPng()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.contentType").value("image/png"));
        upload(token, new MockMultipartFile("file", "ok.jpg", "image/jpeg", validJpeg()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.contentType").value("image/jpeg"));
        upload(token, new MockMultipartFile("file", "ok.webp", "image/webp", validWebp()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.contentType").value("image/webp"));
        upload(token, new MockMultipartFile("file", "ok.pdf", "application/pdf", validPdf()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.contentType").value("application/pdf"));
        upload(token, textFile("ok.txt", "plain text"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.contentType").value("text/plain"));

        upload(token, new MockMultipartFile("file", "mismatch.png", "image/png", validJpeg()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("FILE_TYPE_NOT_ALLOWED"));
        upload(token, new MockMultipartFile("file", "binary.txt", "text/plain", new byte[]{0, 1, 2, 3}))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("FILE_TYPE_NOT_ALLOWED"));
    }

    @Test
    void getOwnedFileAndDenyOtherUsersFile() throws Exception {
        register("alice", "password123");
        register("bob", "password123");
        Long bobFileId = insertFile(userId("bob"), "users/bob/2026/05/25/file.txt", "bob.txt", "text/plain");

        mockMvc.perform(get("/api/v1/files/{id}", bobFileId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice"))))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));

        mockMvc.perform(get("/api/v1/files/{id}", bobFileId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("bob"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.id").value(bobFileId))
                .andExpect(jsonPath("$.data.objectKey").value("users/bob/2026/05/25/file.txt"))
                .andExpect(jsonPath("$.data.fileName").value("bob.txt"))
                .andExpect(jsonPath("$.data.mimeType").value("text/plain"))
                .andExpect(jsonPath("$.data.size").value(4))
                .andExpect(jsonPath("$.data.accessUrl").value(nullValue()))
                .andExpect(jsonPath("$.data.expiresAt").value(nullValue()))
                .andExpect(jsonPath("$.data.contentType").value("text/plain"));
    }

    @Test
    void deleteOwnedFileSoftDeletesAndRepeatedDeleteDoesNotReturnInternalError() throws Exception {
        register("alice", "password123");
        String token = accessToken("alice");
        Long fileId = insertFile(userId("alice"), "users/alice/2026/05/25/file.txt", "file.txt", "text/plain");

        mockMvc.perform(delete("/api/v1/files/{id}", fileId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(token)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value("OK"));

        Integer deletedCount = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM file_objects WHERE id = ? AND deleted = 1 AND deleted_at IS NOT NULL AND storage_delete_status = 'DELETED'",
                Integer.class,
                fileId);
        assertThat(deletedCount).isEqualTo(1);

        mockMvc.perform(get("/api/v1/files/{id}", fileId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(token)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));

        mockMvc.perform(delete("/api/v1/files/{id}", fileId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(token)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));
    }

    @Test
    void deleteOtherUsersFileReturnsNotFoundAndDoesNotMutateRow() throws Exception {
        register("alice", "password123");
        register("bob", "password123");
        Long bobFileId = insertFile(userId("bob"), "users/bob/2026/05/25/file.txt", "file.txt", "text/plain");

        mockMvc.perform(delete("/api/v1/files/{id}", bobFileId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice"))))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));

        Integer deleted = jdbcTemplate.queryForObject(
                "SELECT deleted FROM file_objects WHERE id = ?",
                Integer.class,
                bobFileId);
        assertThat(deleted).isZero();
    }

    @Test
    void accountDeletionSoftDeletesUsersFileObjectsWithoutAffectingOtherUsers() throws Exception {
        register("alice", "password123");
        register("bob", "password123");
        String aliceToken = accessToken("alice");
        Long aliceFileId = insertFile(userId("alice"), "users/alice/2026/05/25/file.txt", "alice.txt", "text/plain");
        Long bobFileId = insertFile(userId("bob"), "users/bob/2026/05/25/file.txt", "bob.txt", "text/plain");

        mockMvc.perform(delete("/api/v1/users/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value("OK"));

        Integer aliceDeleted = jdbcTemplate.queryForObject(
                "SELECT deleted FROM file_objects WHERE id = ?",
                Integer.class,
                aliceFileId);
        String aliceStorageStatus = jdbcTemplate.queryForObject(
                "SELECT storage_delete_status FROM file_objects WHERE id = ?",
                String.class,
                aliceFileId);
        Integer bobDeleted = jdbcTemplate.queryForObject(
                "SELECT deleted FROM file_objects WHERE id = ?",
                Integer.class,
                bobFileId);
        assertThat(aliceDeleted).isEqualTo(1);
        assertThat(aliceStorageStatus).isEqualTo("DELETED");
        assertThat(bobDeleted).isZero();
    }

    @Test
    void healthEndpointStillAllowsAnonymousAccessAfterFileModule() throws Exception {
        mockMvc.perform(get("/api/v1/health")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer invalid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.code").value("OK"));
    }

    private MockMultipartFile imageFile(String filename, byte[] content) {
        return new MockMultipartFile("file", filename, "image/png", content);
    }

    private byte[] validPng() {
        return new byte[]{
                (byte) 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
                0x00, 0x00, 0x00, 0x0D
        };
    }

    private byte[] validJpeg() {
        return new byte[]{(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0, 0x00, 0x10};
    }

    private byte[] validWebp() {
        return new byte[]{'R', 'I', 'F', 'F', 0x04, 0x00, 0x00, 0x00, 'W', 'E', 'B', 'P'};
    }

    private byte[] validPdf() {
        return "%PDF-1.7\n".getBytes(java.nio.charset.StandardCharsets.US_ASCII);
    }

    private MockMultipartFile textFile(String filename, String content) {
        return new MockMultipartFile("file", filename, "text/plain", content.getBytes(java.nio.charset.StandardCharsets.UTF_8));
    }

    private org.springframework.test.web.servlet.ResultActions upload(String accessToken, MockMultipartFile file) throws Exception {
        return mockMvc.perform(multipart("/api/v1/files/upload")
                .file(file)
                .header(HttpHeaders.AUTHORIZATION, bearer(accessToken)));
    }

    private Long insertFile(Long userId, String objectKey, String filename, String contentType) {
        jdbcTemplate.update("""
                INSERT INTO file_objects
                    (user_id, object_key, original_filename, content_type, file_size, file_hash, storage_provider, bucket_name, deleted, created_at)
                VALUES (?, ?, ?, ?, 4, 'hash', 'minio', 'harmony-ocr-test', 0, CURRENT_TIMESTAMP)
                """, userId, objectKey, filename, contentType);
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
        return jsonNode(result);
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

    private JsonNode jsonNode(MvcResult result) throws Exception {
        return objectMapper.readTree(result.getResponse().getContentAsString());
    }
}
