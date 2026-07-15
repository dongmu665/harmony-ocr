package com.harmonyocr.record;

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
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@ActiveProfiles("test")
@AutoConfigureMockMvc
@SpringBootTest
/**
 * OCR 历史记录 ownership 集成测试。
 * 维护说明：专门验证跨用户读取、修改和删除记录时统一返回安全错误，不泄露资源存在性。
 */
class RecordOwnershipIntegrationTest {

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
    void otherUsersRecordDetailUpdateDeleteAndFavoriteReturnNotFound() throws Exception {
        register("alice", "password123");
        register("bob", "password123");
        String aliceToken = accessToken("alice");
        Long bobRecordId = insertRecord(userId("bob"), "Bob secret", "camera", "private text");

        mockMvc.perform(get("/api/v1/records/{id}", bobRecordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));

        mockMvc.perform(patch("/api/v1/records/{id}", bobRecordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("title", "stolen"))))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));

        mockMvc.perform(patch("/api/v1/records/{id}/favorite", bobRecordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("favorite", true))))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));

        mockMvc.perform(delete("/api/v1/records/{id}", bobRecordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));

        Map<String, Object> bobRow = jdbcTemplate.queryForMap(
                "SELECT title, favorite, deleted FROM recognition_records WHERE id = ?",
                bobRecordId);
        assertThat(bobRow.get("title")).isEqualTo("Bob secret");
        assertThat(((Number) bobRow.get("favorite")).intValue()).isZero();
        assertThat(((Number) bobRow.get("deleted")).intValue()).isZero();
    }

    @Test
    void searchAndListNeverReturnOtherUsersOrDeletedRecords() throws Exception {
        register("alice", "password123");
        register("bob", "password123");
        insertRecord(userId("alice"), "Alice visible", "camera", "shared keyword");
        insertDeletedRecord(userId("alice"), "Alice deleted", "camera", "shared keyword");
        insertRecord(userId("bob"), "Bob hidden", "camera", "shared keyword");

        mockMvc.perform(get("/api/v1/records/search")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice")))
                        .param("keyword", "shared"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.total").value(1))
                .andExpect(jsonPath("$.data.items[0].title").value("Alice visible"));
    }

    @Test
    void deletedAccountOldAccessTokenCannotAccessRecordApisAndRecordsAreSoftDeleted() throws Exception {
        register("alice", "password123");
        String accessToken = accessToken("alice");
        Long userId = userId("alice");
        insertRecord(userId, "Before deletion", "album", "text");

        mockMvc.perform(delete("/api/v1/users/me")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value("OK"));

        mockMvc.perform(get("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken)))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"));

        Integer deletedCount = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM recognition_records WHERE user_id = ? AND deleted = 1 AND deleted_at IS NOT NULL",
                Integer.class,
                userId);
        assertThat(deletedCount).isEqualTo(1);
    }

    private Long insertRecord(Long userId, String title, String sourceType, String rawText) {
        jdbcTemplate.update("""
                INSERT INTO recognition_records
                    (user_id, title, source_type, raw_text, favorite, deleted, created_at, updated_at)
                VALUES (?, ?, ?, ?, 0, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """, userId, title, sourceType, rawText);
        return jdbcTemplate.queryForObject("SELECT MAX(id) FROM recognition_records", Long.class);
    }

    private Long insertDeletedRecord(Long userId, String title, String sourceType, String rawText) {
        jdbcTemplate.update("""
                INSERT INTO recognition_records
                    (user_id, title, source_type, raw_text, favorite, deleted, created_at, updated_at, deleted_at)
                VALUES (?, ?, ?, ?, 0, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """, userId, title, sourceType, rawText);
        return jdbcTemplate.queryForObject("SELECT MAX(id) FROM recognition_records", Long.class);
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
