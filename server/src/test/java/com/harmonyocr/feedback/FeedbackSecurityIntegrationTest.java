package com.harmonyocr.feedback;

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

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 反馈安全边界集成测试。
 * 维护说明：覆盖反馈查询和管理入口权限隔离，确保普通用户不能读取他人反馈或管理元数据。
 */
@ActiveProfiles("test")
@AutoConfigureMockMvc
@SpringBootTest
class FeedbackSecurityIntegrationTest {

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
    void invalidAuthorizationHeaderOnFeedbackReturnsUnauthorizedInsteadOfAnonymousFallback() throws Exception {
        mockMvc.perform(post("/api/v1/feedback")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer invalid-token")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "feedbackType", "bug",
                                "content", "The OCR result misses two words."))))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"));
    }

    @Test
    void healthEndpointStillAllowsAnonymousAccessWithInvalidBearer() throws Exception {
        mockMvc.perform(get("/api/v1/health")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer invalid-token"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.code").value("OK"));
    }

    @Test
    void protectedUserRecordAndFileEndpointsStillRequireAuthentication() throws Exception {
        mockMvc.perform(get("/api/v1/users/me"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"));

        mockMvc.perform(post("/api/v1/records")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("sourceType", "camera", "rawText", "hello"))))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"));

        mockMvc.perform(multipart("/api/v1/files/upload"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"));
    }

    @Test
    void feedbackGetEndpointIsNotExposedAsAnonymousManagementApi() throws Exception {
        mockMvc.perform(get("/api/v1/feedback"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"));
    }

    private String json(Object value) throws Exception {
        return objectMapper.writeValueAsString(value);
    }
}
