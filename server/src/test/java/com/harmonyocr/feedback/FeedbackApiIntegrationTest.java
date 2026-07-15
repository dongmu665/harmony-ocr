package com.harmonyocr.feedback;

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
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@ActiveProfiles("test")
@AutoConfigureMockMvc
@SpringBootTest
/**
 * 反馈 API 集成测试。
 * 维护说明：验证匿名和登录用户反馈提交路径、字段校验和统一响应格式，不把反馈正文写入测试日志。
 */
class FeedbackApiIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @BeforeEach
    void cleanDatabase() {
        jdbcTemplate.update("DELETE FROM feedback");
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
    void anonymousUserCanSubmitFeedbackWithoutUserIdAndReceivesMinimalResult() throws Exception {
        MvcResult result = mockMvc.perform(post("/api/v1/feedback")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "feedbackType", "bug",
                                "content", "The OCR result misses two words.",
                                "contact", "user@example.com",
                                "deviceInfo", "HarmonyOS test device",
                                "appVersion", "1.0.0"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.code").value("OK"))
                .andExpect(jsonPath("$.data.id").isNumber())
                .andExpect(jsonPath("$.data.feedbackType").value("bug"))
                .andExpect(jsonPath("$.data.status").value("PENDING"))
                .andExpect(jsonPath("$.data.createdAt").exists())
                .andExpect(jsonPath("$.data.content").doesNotExist())
                .andExpect(jsonPath("$.data.contact").doesNotExist())
                .andReturn();

        Long feedbackId = jsonNode(result).path("data").path("id").asLong();
        Map<String, Object> row = jdbcTemplate.queryForMap(
                "SELECT user_id, feedback_type, content, contact, device_info, app_version, status, deleted FROM feedback WHERE id = ?",
                feedbackId);
        assertThat(row.get("user_id")).isNull();
        assertThat(row.get("feedback_type")).isEqualTo("bug");
        assertThat(row.get("content")).isEqualTo("The OCR result misses two words.");
        assertThat(row.get("contact")).isEqualTo("user@example.com");
        assertThat(row.get("device_info")).isEqualTo("HarmonyOS test device");
        assertThat(row.get("app_version")).isEqualTo("1.0.0");
        assertThat(row.get("status")).isEqualTo("PENDING");
        assertThat(((Number) row.get("deleted")).intValue()).isZero();
    }

    @Test
    void authenticatedUserCanSubmitFeedbackAndBindsCurrentUserId() throws Exception {
        register("alice", "password123");
        String accessToken = accessToken("alice");

        MvcResult result = mockMvc.perform(post("/api/v1/feedback")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "userId", 9999,
                                "status", "RESOLVED",
                                "feedbackType", "suggestion",
                                "content", "Please add batch export for recognized text."))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.feedbackType").value("suggestion"))
                .andExpect(jsonPath("$.data.status").value("PENDING"))
                .andReturn();

        Long feedbackId = jsonNode(result).path("data").path("id").asLong();
        Long ownerId = jdbcTemplate.queryForObject(
                "SELECT user_id FROM feedback WHERE id = ?",
                Long.class,
                feedbackId);
        assertThat(ownerId).isEqualTo(userId("alice"));
    }

    @Test
    void feedbackStatusDefaultsToPending() throws Exception {
        MvcResult result = submitAnonymous("complaint", "Recognition is too slow on my device.");

        Long feedbackId = jsonNode(result).path("data").path("id").asLong();
        String status = jdbcTemplate.queryForObject(
                "SELECT status FROM feedback WHERE id = ?",
                String.class,
                feedbackId);
        assertThat(status).isEqualTo("PENDING");
    }

    @Test
    void rejectMissingOrInvalidFeedbackType() throws Exception {
        mockMvc.perform(post("/api/v1/feedback")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("content", "A valid content body."))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));

        mockMvc.perform(post("/api/v1/feedback")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "feedbackType", "feature",
                                "content", "A valid content body."))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
    }

    @Test
    void rejectBlankTooShortAndTooLongContent() throws Exception {
        mockMvc.perform(post("/api/v1/feedback")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("feedbackType", "bug", "content", " "))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));

        mockMvc.perform(post("/api/v1/feedback")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("feedbackType", "bug", "content", "abcd"))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));

        mockMvc.perform(post("/api/v1/feedback")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("feedbackType", "bug", "content", "x".repeat(2001)))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
    }

    @Test
    void rejectOptionalFieldsThatExceedLengthLimits() throws Exception {
        expectValidationError(Map.of(
                "feedbackType", "other",
                "content", "A valid content body.",
                "contact", "c".repeat(129)));

        expectValidationError(Map.of(
                "feedbackType", "other",
                "content", "A valid content body.",
                "deviceInfo", "d".repeat(513)));

        expectValidationError(Map.of(
                "feedbackType", "other",
                "content", "A valid content body.",
                "appVersion", "v".repeat(65)));
    }

    private void expectValidationError(Map<String, String> body) throws Exception {
        mockMvc.perform(post("/api/v1/feedback")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(body)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
    }

    private MvcResult submitAnonymous(String feedbackType, String content) throws Exception {
        return mockMvc.perform(post("/api/v1/feedback")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("feedbackType", feedbackType, "content", content))))
                .andExpect(status().isOk())
                .andReturn();
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
