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

/**
 * OCR 历史标签接口集成测试，属于 record 模块。
 * 维护说明：测试只使用本地 test profile，不输出 Token、OCR 全文、objectKey 或真实用户图片。
 */
@ActiveProfiles("test")
@AutoConfigureMockMvc
@SpringBootTest
class RecordTagApiIntegrationTest {

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
        jdbcTemplate.update("DELETE FROM recognition_record_tags");
        jdbcTemplate.update("DELETE FROM recognition_tags");
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
    void tagCrudRejectsDuplicateNameWithinSameUserAndAllowsCrossUserSameName() throws Exception {
        register("alice");
        register("bob");
        String aliceToken = accessToken("alice");
        String bobToken = accessToken("bob");

        MvcResult created = mockMvc.perform(post("/api/v1/tags")
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("name", " 学习资料 ", "color", "#2F80ED"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.id").isNumber())
                .andExpect(jsonPath("$.data.name").value("学习资料"))
                .andExpect(jsonPath("$.data.color").value("#2F80ED"))
                .andReturn();
        Long tagId = jsonNode(created).path("data").path("id").asLong();

        mockMvc.perform(post("/api/v1/tags")
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("name", "学习资料"))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));

        mockMvc.perform(post("/api/v1/tags")
                        .header(HttpHeaders.AUTHORIZATION, bearer(bobToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("name", "学习资料"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.name").value("学习资料"));

        mockMvc.perform(patch("/api/v1/tags/{id}", tagId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("name", "课堂截图", "color", "#27AE60"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.name").value("课堂截图"))
                .andExpect(jsonPath("$.data.color").value("#27AE60"));

        mockMvc.perform(get("/api/v1/tags")
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.length()").value(1))
                .andExpect(jsonPath("$.data[0].name").value("课堂截图"));

        mockMvc.perform(delete("/api/v1/tags/{id}", tagId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true));

        Integer remaining = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM recognition_tags WHERE id = ?",
                Integer.class,
                tagId);
        assertThat(remaining).isZero();
    }

    @Test
    void recordTagBindingIsOwnedIdempotentAndCanFilterRecordsByTag() throws Exception {
        register("alice");
        register("bob");
        String aliceToken = accessToken("alice");
        String bobToken = accessToken("bob");
        Long aliceId = userId("alice");
        Long bobId = userId("bob");
        Long aliceRecord = insertRecord(aliceId, "Notice", "album", "course notice", "course edited", false, false, "device-ocr");
        Long deletedRecord = insertRecord(aliceId, "Deleted", "album", "course notice", null, false, true, "device-ocr");
        Long bobRecord = insertRecord(bobId, "Bob", "album", "course notice", null, false, false, "device-ocr");
        Long studyTag = createTag(aliceToken, "通知公告");
        Long bobTag = createTag(bobToken, "通知公告");

        mockMvc.perform(post("/api/v1/records/{id}/tags/{tagId}", aliceRecord, studyTag)
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.tags[0].id").value(studyTag))
                .andExpect(jsonPath("$.data.tags[0].name").value("通知公告"));

        mockMvc.perform(post("/api/v1/records/{id}/tags/{tagId}", aliceRecord, studyTag)
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.tags.length()").value(1));

        mockMvc.perform(post("/api/v1/records/{id}/tags/{tagId}", aliceRecord, bobTag)
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));

        mockMvc.perform(post("/api/v1/records/{id}/tags/{tagId}", bobRecord, studyTag)
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));

        mockMvc.perform(get("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken))
                        .param("tagId", String.valueOf(studyTag))
                        .param("keyword", "course")
                        .param("ocrEngine", "device-ocr"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.total").value(1))
                .andExpect(jsonPath("$.data.items[0].id").value(aliceRecord));

        mockMvc.perform(post("/api/v1/records/{id}/tags/{tagId}", deletedRecord, studyTag)
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));

        mockMvc.perform(delete("/api/v1/records/{id}/tags/{tagId}", aliceRecord, studyTag)
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.tags.length()").value(0));

        mockMvc.perform(get("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken))
                        .param("tagId", String.valueOf(studyTag)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.total").value(0));
    }

    private Long createTag(String accessToken, String name) throws Exception {
        MvcResult result = mockMvc.perform(post("/api/v1/tags")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("name", name))))
                .andExpect(status().isOk())
                .andReturn();
        return jsonNode(result).path("data").path("id").asLong();
    }

    private Long insertRecord(Long userId, String title, String sourceType, String rawText,
                              String editedText, boolean favorite, boolean deleted, String ocrEngine) {
        jdbcTemplate.update("""
                INSERT INTO recognition_records
                    (user_id, title, source_type, raw_text, edited_text, favorite, deleted, ocr_engine,
                     created_at, updated_at, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
                        CASE WHEN ? THEN CURRENT_TIMESTAMP ELSE NULL END)
                """, userId, title, sourceType, rawText, editedText, favorite ? 1 : 0,
                deleted ? 1 : 0, ocrEngine, deleted);
        return jdbcTemplate.queryForObject("SELECT MAX(id) FROM recognition_records", Long.class);
    }

    /**
     * 注册本地测试用户。
     * 参数为测试用户名；测试口令由用户名派生，只用于本地 test profile，不写入日志或报告。
     */
    private void register(String username) throws Exception {
        mockMvc.perform(post("/api/v1/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", testPassword(username)))))
                .andExpect(status().isOk());
    }

    /**
     * 读取本地测试用户的 accessToken。
     * 参数为测试用户名；返回值只用于构造 MockMvc Header，不打印或记录 Token 内容。
     */
    private String accessToken(String username) throws Exception {
        return login(username, testPassword(username)).path("data").path("accessToken").asText();
    }

    private JsonNode login(String username, String password) throws Exception {
        MvcResult result = mockMvc.perform(post("/api/v1/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", password))))
                .andExpect(status().isOk())
                .andReturn();
        return jsonNode(result);
    }

    /**
     * 生成本地测试口令。
     * 参数为测试用户名；返回满足注册策略的固定测试值，不代表真实用户密码。
     */
    private String testPassword(String username) {
        return username + "-local-test-credential";
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
