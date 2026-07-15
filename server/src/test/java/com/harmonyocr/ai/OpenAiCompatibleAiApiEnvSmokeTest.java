package com.harmonyocr.ai;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
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
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * OpenAI-compatible AI API 本地环境 smoke test，属于 ai 模块。
 * 维护说明：仅在当前进程提供 OPENAI_* 临时环境变量时运行，覆盖真实 API provider 经过 controller/service 的闭环；不得输出 API Key 或完整响应。
 */
@ActiveProfiles("test")
@TestPropertySource(properties = "app.ai.provider=openai-compatible")
@AutoConfigureMockMvc
@SpringBootTest
@EnabledIfEnvironmentVariable(named = "OPENAI_BASE_URL", matches = ".+")
@EnabledIfEnvironmentVariable(named = "OPENAI_API_KEY", matches = ".+")
@EnabledIfEnvironmentVariable(named = "OPENAI_MODEL", matches = ".+")
class OpenAiCompatibleAiApiEnvSmokeTest {

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
    void aiApiUsesOpenAiCompatibleProviderForAllV20ActionsWhenTemporaryEnvIsPresent() throws Exception {
        String password = testPassword();
        register("alice", password);
        Long recordId = insertRecord(userId("alice"), "Smoke", "camera", "Harmony OCR local AI smoke input.", null);
        String token = accessToken("alice", password);
        acceptAiConsent(bearer(token));

        List<String> actions = List.of(
                "CORRECTION",
                "SUMMARY",
                "TRANSLATION",
                "TITLE",
                "KEY_POINTS",
                "SMART_FORMAT",
                "MARKDOWN");
        for (String action : actions) {
            MvcResult result = mockMvc.perform(post("/api/v1/ai/actions")
                            .header(HttpHeaders.AUTHORIZATION, bearer(token))
                            .contentType(MediaType.APPLICATION_JSON)
                            .content(json(Map.of(
                                    "recordId", recordId,
                                    "action", action,
                                    "targetLanguage", "en",
                                    "consentAccepted", true))))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.data.action").value(action))
                    .andExpect(jsonPath("$.data.providerName").value("openai-compatible"))
                    .andExpect(jsonPath("$.data.degraded").value(false))
                    .andReturn();

            JsonNode data = jsonNode(result).path("data");
            assertThat(data.path("modelName").asText()).isEqualTo(System.getenv("OPENAI_MODEL"));
            assertThat(data.path("outputText").asText()).isNotBlank();
            assertThat(data.path("outputText").asText().length()).isLessThan(4000);
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

    private void acceptAiConsent(String token) throws Exception {
        mockMvc.perform(post("/api/v1/ai/consent")
                        .header(HttpHeaders.AUTHORIZATION, token)
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
