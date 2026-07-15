package com.harmonyocr.user;

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
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@ActiveProfiles("test")
@AutoConfigureMockMvc
@SpringBootTest
/**
 * 账号注销与数据删除集成测试。
 * 维护说明：验证注销会清理或匿名化用户相关数据，并撤销会话，避免保留可识别 OCR 隐私内容。
 */
class AccountDeletionApiIntegrationTest {

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
    void deleteMeWithoutAccessTokenReturnsUnauthorizedUnifiedResponse() throws Exception {
        mockMvc.perform(delete("/api/v1/users/me"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"))
                .andExpect(jsonPath("$.timestamp").exists());
    }

    @Test
    void deleteMeWithValidAccessTokenMarksAccountDeletedAndRevokesAllRefreshTokens() throws Exception {
        register("alice", "password123");
        JsonNode firstLogin = login("alice", "password123", "device-1");
        login("alice", "password123", "device-2");
        String accessToken = firstLogin.path("data").path("accessToken").asText();
        Long userId = userId("alice");

        mockMvc.perform(delete("/api/v1/users/me")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.code").value("OK"))
                .andExpect(jsonPath("$.data").doesNotExist());

        Map<String, Object> userRow = jdbcTemplate.queryForMap(
                "SELECT username, email, phone, password_hash, nickname, avatar_url, status, deleted_at, last_login_at FROM users WHERE id = ?",
                userId);
        assertThat(userRow.get("status")).isEqualTo("DELETED");
        assertThat(userRow.get("deleted_at")).isNotNull();
        assertThat(userRow.get("username")).isNotEqualTo("alice");
        assertThat(userRow.get("email")).isNull();
        assertThat(userRow.get("phone")).isNull();
        assertThat(userRow.get("nickname")).isNull();
        assertThat(userRow.get("avatar_url")).isNull();
        assertThat(userRow.get("last_login_at")).isNull();

        Integer refreshTokenCount = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM refresh_tokens WHERE user_id = ?",
                Integer.class,
                userId);
        assertThat(refreshTokenCount).isZero();
    }

    @Test
    void deletedAccountCannotLoginRefreshOrUseOldAccessToken() throws Exception {
        register("alice", "password123");
        JsonNode login = login("alice", "password123", "device-1");
        String accessToken = login.path("data").path("accessToken").asText();
        String refreshToken = login.path("data").path("refreshToken").asText();

        mockMvc.perform(delete("/api/v1/users/me")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken))
                .andExpect(status().isOk());

        mockMvc.perform(get("/api/v1/users/me")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"));

        mockMvc.perform(post("/api/v1/auth/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("refreshToken", refreshToken))))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("AUTH_REFRESH_TOKEN_INVALID"));

        mockMvc.perform(post("/api/v1/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", "alice", "password", "password123"))))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("AUTH_INVALID_CREDENTIALS"));
    }

    @Test
    void deleteMeScrubsOcrTextBlocksDevicesAndFilesWithoutAffectingOtherUsers() throws Exception {
        register("alice", "password123");
        register("bob", "password123");
        JsonNode aliceLogin = login("alice", "password123", "device-1");
        String aliceAccessToken = aliceLogin.path("data").path("accessToken").asText();
        Long aliceId = userId("alice");
        Long bobId = userId("bob");
        jdbcTemplate.update("""
                UPDATE users
                SET email = 'alice@example.test',
                    phone = '00000000000',
                    nickname = 'Alice',
                    avatar_url = 'https://example.test/avatar.png'
                WHERE id = ?
                """, aliceId);
        Long aliceRecordId = insertRecordWithBlock(aliceId, "Alice OCR", "alice raw", "alice edited", "files/2026/05/25/alice.png");
        Long bobRecordId = insertRecordWithBlock(bobId, "Bob OCR", "bob raw", "bob edited", "files/2026/05/25/bob.png");
        Long aliceFileId = insertFile(aliceId, "files/2026/05/25/alice.png", "alice.png", "alice-hash");
        Long bobFileId = insertFile(bobId, "files/2026/05/25/bob.png", "bob.png", "bob-hash");

        mockMvc.perform(delete("/api/v1/users/me")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + aliceAccessToken))
                .andExpect(status().isOk());

        Map<String, Object> userRow = jdbcTemplate.queryForMap(
                "SELECT username, email, phone, password_hash, nickname, avatar_url, status, deleted_at, last_login_at FROM users WHERE id = ?",
                aliceId);
        assertThat(userRow.get("status")).isEqualTo("DELETED");
        assertThat(userRow.get("deleted_at")).isNotNull();
        assertThat(userRow.get("username")).asString().startsWith("deleted_user_");
        assertThat(userRow.get("email")).isNull();
        assertThat(userRow.get("phone")).isNull();
        assertThat(userRow.get("nickname")).isNull();
        assertThat(userRow.get("avatar_url")).isNull();
        assertThat(userRow.get("last_login_at")).isNull();
        assertThat(userRow.get("password_hash")).asString().doesNotContain("password123");

        Map<String, Object> recordRow = jdbcTemplate.queryForMap(
                "SELECT title, image_object_key, raw_text, edited_text, language, ocr_engine, favorite, deleted, deleted_at FROM recognition_records WHERE id = ?",
                aliceRecordId);
        assertThat(recordRow.get("title")).isNull();
        assertThat(recordRow.get("image_object_key")).isNull();
        assertThat(recordRow.get("raw_text")).isNull();
        assertThat(recordRow.get("edited_text")).isNull();
        assertThat(recordRow.get("language")).isNull();
        assertThat(recordRow.get("ocr_engine")).isNull();
        assertThat(((Number) recordRow.get("favorite")).intValue()).isZero();
        assertThat(((Number) recordRow.get("deleted")).intValue()).isEqualTo(1);
        assertThat(recordRow.get("deleted_at")).isNotNull();
        assertThat(jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM recognition_blocks WHERE record_id = ?",
                Integer.class,
                aliceRecordId)).isZero();

        Map<String, Object> fileRow = jdbcTemplate.queryForMap(
                "SELECT object_key, original_filename, file_hash, deleted, deleted_at, storage_delete_status FROM file_objects WHERE id = ?",
                aliceFileId);
        assertThat(fileRow.get("object_key")).asString().startsWith("deleted/file/");
        assertThat(fileRow.get("original_filename")).isNull();
        assertThat(fileRow.get("file_hash")).isNull();
        assertThat(((Number) fileRow.get("deleted")).intValue()).isEqualTo(1);
        assertThat(fileRow.get("deleted_at")).isNotNull();
        assertThat(fileRow.get("storage_delete_status")).isEqualTo("DELETED");

        assertThat(jdbcTemplate.queryForObject("SELECT COUNT(*) FROM user_devices WHERE user_id = ?", Integer.class, aliceId)).isZero();
        assertThat(jdbcTemplate.queryForObject("SELECT COUNT(*) FROM refresh_tokens WHERE user_id = ?", Integer.class, aliceId)).isZero();
        assertThat(jdbcTemplate.queryForObject("SELECT deleted FROM recognition_records WHERE id = ?", Integer.class, bobRecordId)).isZero();
        assertThat(jdbcTemplate.queryForObject("SELECT deleted FROM file_objects WHERE id = ?", Integer.class, bobFileId)).isZero();

        mockMvc.perform(get("/api/v1/records/{id}", aliceRecordId)
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + aliceAccessToken))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(get("/api/v1/files/{id}", aliceFileId)
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + aliceAccessToken))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void repeatedDeleteWithOldAccessTokenReturnsUnauthorizedWithoutInternalError() throws Exception {
        register("alice", "password123");
        String accessToken = login("alice", "password123", "device-1")
                .path("data")
                .path("accessToken")
                .asText();

        mockMvc.perform(delete("/api/v1/users/me")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken))
                .andExpect(status().isOk());

        mockMvc.perform(delete("/api/v1/users/me")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + accessToken))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"));
    }

    @Test
    void deleteMeDoesNotAffectOtherUsersRefreshTokens() throws Exception {
        register("alice", "password123");
        register("bob", "password123");
        JsonNode aliceLogin = login("alice", "password123", "alice-device");
        JsonNode bobLogin = login("bob", "password123", "bob-device");
        String aliceAccessToken = aliceLogin.path("data").path("accessToken").asText();
        String bobAccessToken = bobLogin.path("data").path("accessToken").asText();
        Long bobUserId = userId("bob");

        mockMvc.perform(delete("/api/v1/users/me")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + aliceAccessToken))
                .andExpect(status().isOk());

        String bobStatus = jdbcTemplate.queryForObject(
                "SELECT status FROM users WHERE id = ?",
                String.class,
                bobUserId);
        assertThat(bobStatus).isEqualTo("ACTIVE");

        Integer bobActiveRefreshTokenCount = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM refresh_tokens WHERE user_id = ? AND revoked_at IS NULL",
                Integer.class,
                bobUserId);
        assertThat(bobActiveRefreshTokenCount).isEqualTo(1);

        mockMvc.perform(get("/api/v1/users/me")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer " + bobAccessToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.username").value("bob"));
    }

    @Test
    void healthEndpointStillAllowsAnonymousAccessAfterAccountDeletionFeature() throws Exception {
        mockMvc.perform(get("/api/v1/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.code").value("OK"));
    }

    private void register(String username, String password) throws Exception {
        mockMvc.perform(post("/api/v1/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", password))))
                .andExpect(status().isOk());
    }

    private JsonNode login(String username, String password, String deviceId) throws Exception {
        MvcResult result = mockMvc.perform(post("/api/v1/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "username", username,
                                "password", password,
                                "deviceId", deviceId,
                                "deviceName", "test device"))))
                .andExpect(status().isOk())
                .andReturn();
        return jsonNode(result);
    }

    private Long userId(String username) {
        return jdbcTemplate.queryForObject(
                "SELECT id FROM users WHERE username = ?",
                Long.class,
                username);
    }

    private Long insertRecordWithBlock(Long userId, String title, String rawText, String editedText, String imageObjectKey) {
        jdbcTemplate.update("""
                INSERT INTO recognition_records
                    (user_id, title, source_type, image_object_key, raw_text, edited_text, language, ocr_engine,
                     favorite, deleted, created_at, updated_at)
                VALUES (?, ?, 'camera', ?, ?, ?, 'zh-CN', 'device-ocr', 1, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """, userId, title, imageObjectKey, rawText, editedText);
        Long recordId = jdbcTemplate.queryForObject("SELECT MAX(id) FROM recognition_records", Long.class);
        jdbcTemplate.update("""
                INSERT INTO recognition_blocks (record_id, block_index, text, confidence, bounding_box, created_at)
                VALUES (?, 0, ?, 0.9800, '{"x":1,"y":2}', CURRENT_TIMESTAMP)
                """, recordId, rawText);
        return recordId;
    }

    private Long insertFile(Long userId, String objectKey, String filename, String fileHash) {
        jdbcTemplate.update("""
                INSERT INTO file_objects
                    (user_id, object_key, original_filename, content_type, file_size, file_hash, storage_provider, bucket_name,
                     deleted, created_at, storage_delete_status)
                VALUES (?, ?, ?, 'image/png', 12, ?, 'minio', 'harmony-ocr-test', 0, CURRENT_TIMESTAMP, 'ACTIVE')
                """, userId, objectKey, filename, fileHash);
        return jdbcTemplate.queryForObject("SELECT MAX(id) FROM file_objects", Long.class);
    }

    private String json(Object value) throws Exception {
        return objectMapper.writeValueAsString(value);
    }

    private JsonNode jsonNode(MvcResult result) throws Exception {
        return objectMapper.readTree(result.getResponse().getContentAsString());
    }
}
