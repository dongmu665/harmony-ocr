package com.harmonyocr.ai;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.hasKey;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * AI 能力 API 集成测试，属于 ai 模块。
 * 维护说明：默认 profile 只验证用户同意、记录归属和 mock provider fallback；真实 OpenAI-compatible 协议由独立 provider contract test 覆盖。
 */
@ActiveProfiles("test")
@TestPropertySource(properties = "app.ai.provider=mock")
@AutoConfigureMockMvc
@SpringBootTest
class AiApiIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @BeforeEach
    void cleanDatabase() {
        jdbcTemplate.update("DELETE FROM ai_runtime_consents");
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
    void aiActionRequiresConsentBeforeSendingSensitiveOcrText() throws Exception {
        String password = testPassword();
        register("alice", password);
        Long recordId = insertRecord(userId("alice"), "Invoice", "camera", "raw ocr txt", "edited ocr text");

        mockMvc.perform(post("/api/v1/ai/actions")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice", password)))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "recordId", recordId,
                                "action", "SUMMARY",
                                "consentAccepted", false))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"))
                .andExpect(jsonPath("$.message", containsString("consentAccepted")));
    }

    @Test
    void aiActionRequiresPersistedRuntimeConsentAndConsentApiDoesNotStoreSensitiveText() throws Exception {
        String password = testPassword();
        register("alice", password);
        Long userId = userId("alice");
        Long recordId = insertRecord(userId, "Contract", "album", "raw confidential ocr text", "edited confidential ocr text");
        String token = bearer(accessToken("alice", password));

        mockMvc.perform(get("/api/v1/ai/consent").header(HttpHeaders.AUTHORIZATION, token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.accepted").value(false))
                .andExpect(jsonPath("$.data.scope").value("AI_OCR_TEXT_PROCESSING"))
                .andExpect(jsonPath("$.data", not(hasKey("sourceText"))))
                .andExpect(jsonPath("$.data", not(hasKey("prompt"))));

        mockMvc.perform(post("/api/v1/ai/actions")
                        .header(HttpHeaders.AUTHORIZATION, token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "recordId", recordId,
                                "action", "SUMMARY",
                                "consentAccepted", true))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"))
                .andExpect(jsonPath("$.message", containsString("runtime AI consent")));

        mockMvc.perform(post("/api/v1/ai/consent")
                        .header(HttpHeaders.AUTHORIZATION, token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("accepted", true))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.accepted").value(true))
                .andExpect(jsonPath("$.data.scope").value("AI_OCR_TEXT_PROCESSING"))
                .andExpect(jsonPath("$.data", not(hasKey("sourceText"))))
                .andExpect(jsonPath("$.data", not(hasKey("prompt"))));

        mockMvc.perform(post("/api/v1/ai/actions")
                        .header(HttpHeaders.AUTHORIZATION, token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "recordId", recordId,
                                "action", "SUMMARY",
                                "consentAccepted", true))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.action").value("SUMMARY"))
                .andExpect(jsonPath("$.data.outputText").value(not(containsString("confidential ocr text"))));

        String persisted = jdbcTemplate.queryForObject("""
                SELECT CAST(user_id AS VARCHAR) || '|' || scope
                FROM ai_runtime_consents
                WHERE user_id = ?
                """, String.class, userId);
        assertThat(persisted).contains("AI_OCR_TEXT_PROCESSING");
        assertThat(persisted).doesNotContain("confidential ocr text");
    }

    @Test
    void aiActionUsesOwnedRecordAndReturnsMockProviderContractForAllV20Actions() throws Exception {
        String alicePassword = testPassword();
        String bobPassword = testPassword();
        register("alice", alicePassword);
        register("bob", bobPassword);
        Long aliceRecord = insertRecord(userId("alice"), "Notice", "album", "raw notice", "edited notice");
        acceptAiConsent("alice", alicePassword);
        acceptAiConsent("bob", bobPassword);

        mockMvc.perform(post("/api/v1/ai/actions")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("bob", bobPassword)))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "recordId", aliceRecord,
                                "action", "CORRECTION",
                                "consentAccepted", true))))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));

        List<String> actions = List.of(
                "CORRECTION",
                "SUMMARY",
                "TRANSLATION",
                "TITLE",
                "KEY_POINTS",
                "FIELD_EXTRACTION",
                "SMART_FORMAT",
                "MARKDOWN");
        for (String action : actions) {
            MvcResult result = mockMvc.perform(post("/api/v1/ai/actions")
                            .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice", alicePassword)))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(json(Map.of(
                                    "recordId", aliceRecord,
                                    "action", action,
                                    "targetLanguage", "en",
                                    "consentAccepted", true))))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.data.action").value(action))
                    .andExpect(jsonPath("$.data.providerName").value("mock-ai-provider"))
                    .andExpect(jsonPath("$.data.modelName").value("contract-mock-v2"))
                    .andExpect(jsonPath("$.data.degraded").value(true))
                    .andExpect(jsonPath("$.data.consentRequired").value(true))
                    .andExpect(jsonPath("$.data.outputText", containsString(action)))
                    .andReturn();

            JsonNode data = jsonNode(result).path("data");
            assertThat(data.path("inputLength").asInt()).isGreaterThan(0);
            assertThat(data.path("outputText").asText()).doesNotContain("raw notice");
            assertThat(data.path("outputText").asText()).doesNotContain("edited notice");
        }
    }

    private Long insertRecord(Long userId, String title, String sourceType, String rawText, String editedText) {
        jdbcTemplate.update("""
                INSERT INTO recognition_records
                    (user_id, title, source_type, raw_text, edited_text, favorite, deleted, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, 0, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """, userId, title, sourceType, rawText, editedText);
        return jdbcTemplate.queryForObject("SELECT MAX(id) FROM recognition_records", Long.class);
    }

    private void register(String username, String password) throws Exception {
        mockMvc.perform(post("/api/v1/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", password))))
                .andExpect(status().isOk());
    }

    private void acceptAiConsent(String username, String password) throws Exception {
        mockMvc.perform(post("/api/v1/ai/consent")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken(username, password)))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("accepted", true))))
                .andExpect(status().isOk());
    }

    private String accessToken(String username, String password) throws Exception {
        MvcResult result = mockMvc.perform(post("/api/v1/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", password))))
                .andExpect(status().isOk())
                .andReturn();
        return jsonNode(result).path("data").path("accessToken").asText();
    }

    private Long userId(String username) {
        return jdbcTemplate.queryForObject("SELECT id FROM users WHERE username = ?", Long.class, username);
    }

    private String testPassword() {
        return "test-" + UUID.randomUUID();
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
