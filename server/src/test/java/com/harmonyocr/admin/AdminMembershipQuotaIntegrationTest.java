package com.harmonyocr.admin;

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
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import static org.hamcrest.Matchers.hasSize;
import static org.hamcrest.Matchers.not;
import static org.hamcrest.Matchers.hasKey;
import static org.hamcrest.Matchers.containsString;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 管理后台与会员额度集成测试，属于 admin/membership 模块。
 * 维护说明：测试通过数据库 seed 管理员身份，不写入固定测试密码、真实 API Key 或敏感业务正文。
 */
@ActiveProfiles("test")
@AutoConfigureMockMvc
@SpringBootTest
class AdminMembershipQuotaIntegrationTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @Autowired
    private JdbcTemplate jdbcTemplate;

    @BeforeEach
    void cleanDatabase() {
        jdbcTemplate.update("DELETE FROM admin_audit_logs");
        jdbcTemplate.update("DELETE FROM manual_membership_orders");
        jdbcTemplate.update("DELETE FROM usage_counters");
        jdbcTemplate.update("DELETE FROM user_memberships");
        jdbcTemplate.update("DELETE FROM admin_accounts");
        jdbcTemplate.update("DELETE FROM ai_runtime_consents");
        jdbcTemplate.update("DELETE FROM ai_provider_configs");
        jdbcTemplate.update("DELETE FROM object_storage_cleanup_tasks");
        jdbcTemplate.update("DELETE FROM file_objects");
        jdbcTemplate.update("DELETE FROM recognition_record_tags");
        jdbcTemplate.update("DELETE FROM recognition_tags");
        jdbcTemplate.update("DELETE FROM recognition_blocks");
        jdbcTemplate.update("DELETE FROM recognition_records");
        jdbcTemplate.update("DELETE FROM feedback");
        jdbcTemplate.update("DELETE FROM refresh_tokens");
        jdbcTemplate.update("DELETE FROM user_devices");
        jdbcTemplate.update("DELETE FROM export_jobs");
        jdbcTemplate.update("DELETE FROM batch_ocr_items");
        jdbcTemplate.update("DELETE FROM batch_ocr_jobs");
        jdbcTemplate.update("DELETE FROM users");
    }

    @Test
    void adminConsolePageIsAccessibleAndContainsManagementSurface() throws Exception {
        mockMvc.perform(get("/admin/console"))
                .andExpect(status().isOk())
                .andExpect(content().string(containsString("Harmony OCR Admin Console")))
                .andExpect(content().string(containsString("/api/v1/admin/users")))
                .andExpect(content().string(containsString("/api/v1/admin/usage/summary")))
                .andExpect(content().string(containsString("membershipLevel")))
                .andExpect(content().string(not(containsString("passwordHash"))))
                .andExpect(content().string(not(containsString("objectKey"))));
    }

    @Test
    void currentUserAdminCapabilityRequiresAdminAccountAndDoesNotExposeMetrics() throws Exception {
        String adminPassword = testPassword();
        String userPassword = testPassword();
        register("admin", adminPassword);
        register("alice", userPassword);
        seedAdmin(userId("admin"));
        String adminToken = bearer(accessToken("admin", adminPassword));
        String aliceToken = bearer(accessToken("alice", userPassword));

        mockMvc.perform(get("/api/v1/admin/me")
                        .header(HttpHeaders.AUTHORIZATION, aliceToken))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("FORBIDDEN"));

        mockMvc.perform(get("/api/v1/admin/me")
                        .header(HttpHeaders.AUTHORIZATION, adminToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.admin").value(true))
                .andExpect(jsonPath("$.data", not(hasKey("totalUsers"))));

        mockMvc.perform(get("/api/v1/admin/me"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"));
    }

    @Test
    void adminCanManageMembershipAndQuotaLimitsAiAndExportUsage() throws Exception {
        String adminPassword = testPassword();
        String userPassword = testPassword();
        register("admin", adminPassword);
        register("alice", userPassword);
        Long adminUserId = userId("admin");
        Long aliceUserId = userId("alice");
        seedAdmin(adminUserId);
        Long recordId = insertRecord(aliceUserId);
        String adminToken = bearer(accessToken("admin", adminPassword));
        String aliceToken = bearer(accessToken("alice", userPassword));

        mockMvc.perform(get("/api/v1/admin/users")
                        .header(HttpHeaders.AUTHORIZATION, aliceToken))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("FORBIDDEN"));

        mockMvc.perform(get("/api/v1/admin/users")
                        .header(HttpHeaders.AUTHORIZATION, adminToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items", hasSize(2)))
                .andExpect(jsonPath("$.data.total").value(2))
                .andExpect(jsonPath("$.data.items[0]", not(hasKey("passwordHash"))));

        mockMvc.perform(patch("/api/v1/admin/users/{id}/membership", aliceUserId)
                        .header(HttpHeaders.AUTHORIZATION, adminToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "membershipLevel", "FREE",
                                "ocrQuota", 2,
                                "aiQuota", 1,
                                "exportQuota", 1))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.aiQuota").value(1))
                .andExpect(jsonPath("$.data.exportQuota").value(1));

        mockMvc.perform(get("/api/v1/membership/me")
                        .header(HttpHeaders.AUTHORIZATION, aliceToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.membershipLevel").value("FREE"))
                .andExpect(jsonPath("$.data.aiQuota").value(1))
                .andExpect(jsonPath("$.data.aiUsed").value(0));

        acceptAiConsent(aliceToken);
        aiAction(aliceToken, recordId).andExpect(status().isOk());
        aiAction(aliceToken, recordId)
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.code").value("QUOTA_EXCEEDED"));

        exportPdf(aliceToken, recordId).andExpect(status().isOk());
        exportPdf(aliceToken, recordId)
                .andExpect(status().isTooManyRequests())
                .andExpect(jsonPath("$.code").value("QUOTA_EXCEEDED"));

        mockMvc.perform(get("/api/v1/admin/usage/summary")
                        .header(HttpHeaders.AUTHORIZATION, adminToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.totalUsers").value(2))
                .andExpect(jsonPath("$.data.aiUsed").value(1))
                .andExpect(jsonPath("$.data.exportUsed").value(1));

        mockMvc.perform(get("/api/v1/admin/records")
                        .header(HttpHeaders.AUTHORIZATION, adminToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items", hasSize(1)));

        mockMvc.perform(get("/api/v1/admin/feedback")
                        .header(HttpHeaders.AUTHORIZATION, adminToken))
                .andExpect(status().isOk());

        mockMvc.perform(get("/api/v1/admin/audit-logs")
                        .header(HttpHeaders.AUTHORIZATION, adminToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items", org.hamcrest.Matchers.not(org.hamcrest.Matchers.empty())))
                .andExpect(jsonPath("$.data.items[0].action").isString())
                .andExpect(jsonPath("$.data.items[0]", not(hasKey("requestBody"))));
    }

    @Test
    void adminCanCreateManualMembershipOrderWithoutPaymentSecrets() throws Exception {
        String adminPassword = testPassword();
        String userPassword = testPassword();
        register("admin", adminPassword);
        register("alice", userPassword);
        Long adminUserId = userId("admin");
        Long aliceUserId = userId("alice");
        seedAdmin(adminUserId);
        String adminToken = bearer(accessToken("admin", adminPassword));
        String aliceToken = bearer(accessToken("alice", userPassword));

        mockMvc.perform(post("/api/v1/admin/users/{id}/manual-orders", aliceUserId)
                        .header(HttpHeaders.AUTHORIZATION, adminToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "membershipLevel", "PRO",
                                "ocrQuota", 200,
                                "aiQuota", 50,
                                "exportQuota", 20,
                                "note", "course manual activation"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.userId").value(aliceUserId))
                .andExpect(jsonPath("$.data.membershipLevel").value("PRO"))
                .andExpect(jsonPath("$.data.orderStatus").value("MANUAL_ACTIVATED"))
                .andExpect(jsonPath("$.data.paymentProvider").value("MANUAL"))
                .andExpect(jsonPath("$.data", not(hasKey("paymentToken"))))
                .andExpect(jsonPath("$.data", not(hasKey("password"))));

        mockMvc.perform(get("/api/v1/membership/me")
                        .header(HttpHeaders.AUTHORIZATION, aliceToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.membershipLevel").value("PRO"))
                .andExpect(jsonPath("$.data.ocrQuota").value(200))
                .andExpect(jsonPath("$.data.aiQuota").value(50))
                .andExpect(jsonPath("$.data.exportQuota").value(20));

        Integer orders = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM manual_membership_orders WHERE user_id = ? AND admin_user_id = ? AND payment_provider = 'MANUAL'",
                Integer.class,
                aliceUserId,
                adminUserId);
        Integer audits = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM admin_audit_logs WHERE admin_user_id = ? AND action = 'ADMIN_MANUAL_MEMBERSHIP_ORDER' AND target_id = ?",
                Integer.class,
                adminUserId,
                aliceUserId);
        String storedNote = jdbcTemplate.queryForObject(
                "SELECT note FROM manual_membership_orders WHERE user_id = ?",
                String.class,
                aliceUserId);
        org.assertj.core.api.Assertions.assertThat(orders).isEqualTo(1);
        org.assertj.core.api.Assertions.assertThat(audits).isEqualTo(1);
        org.assertj.core.api.Assertions.assertThat(storedNote).doesNotContain("token").doesNotContain("secret");
    }

    @Test
    void adminCanFilterAndInspectManagementResourcesWithoutSensitiveFields() throws Exception {
        String adminPassword = testPassword();
        String alicePassword = testPassword();
        String bobPassword = testPassword();
        register("admin", adminPassword);
        register("alice", alicePassword);
        register("bob", bobPassword);
        Long adminUserId = userId("admin");
        Long aliceUserId = userId("alice");
        Long bobUserId = userId("bob");
        seedAdmin(adminUserId);
        Long aliceRecord = insertRecord(aliceUserId, "Invoice", "camera");
        Long bobRecord = insertRecord(bobUserId, "Contract", "album");
        Long bugFeedback = insertFeedback(aliceUserId, "BUG", "PENDING");
        insertFeedback(bobUserId, "ADVICE", "CLOSED");
        insertAudit(adminUserId, "ADMIN_UPDATE_MEMBERSHIP", "USER", aliceUserId);
        insertAudit(adminUserId, "ADMIN_LIST_RECORDS", "RECORD", aliceRecord);
        String adminToken = bearer(accessToken("admin", adminPassword));
        String aliceToken = bearer(accessToken("alice", alicePassword));

        mockMvc.perform(get("/api/v1/admin/users")
                        .param("keyword", "ali")
                        .param("status", "ACTIVE")
                        .param("membershipLevel", "FREE")
                        .header(HttpHeaders.AUTHORIZATION, adminToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items", hasSize(1)))
                .andExpect(jsonPath("$.data.total").value(1))
                .andExpect(jsonPath("$.data.items[0].username").value("alice"))
                .andExpect(jsonPath("$.data.items[0]", not(hasKey("passwordHash"))));

        mockMvc.perform(get("/api/v1/admin/users/{id}", aliceUserId)
                        .header(HttpHeaders.AUTHORIZATION, adminToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.username").value("alice"))
                .andExpect(jsonPath("$.data", not(hasKey("passwordHash"))))
                .andExpect(jsonPath("$.data", not(hasKey("accessToken"))));

        mockMvc.perform(get("/api/v1/admin/records")
                        .param("userId", bobUserId.toString())
                        .param("sourceType", "album")
                        .param("keyword", "contract")
                        .header(HttpHeaders.AUTHORIZATION, adminToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items", hasSize(1)))
                .andExpect(jsonPath("$.data.items[0].id").value(bobRecord))
                .andExpect(jsonPath("$.data.items[0]", not(hasKey("rawText"))))
                .andExpect(jsonPath("$.data.items[0]", not(hasKey("objectKey"))));

        mockMvc.perform(get("/api/v1/admin/records/{id}", aliceRecord)
                        .header(HttpHeaders.AUTHORIZATION, adminToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.title").value("Invoice"))
                .andExpect(jsonPath("$.data", not(hasKey("rawText"))))
                .andExpect(jsonPath("$.data", not(hasKey("editedText"))));

        mockMvc.perform(get("/api/v1/admin/feedback")
                        .param("status", "PENDING")
                        .param("feedbackType", "BUG")
                        .header(HttpHeaders.AUTHORIZATION, adminToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items", hasSize(1)))
                .andExpect(jsonPath("$.data.items[0].id").value(bugFeedback))
                .andExpect(jsonPath("$.data.items[0]", not(hasKey("content"))))
                .andExpect(jsonPath("$.data.items[0]", not(hasKey("contact"))));

        mockMvc.perform(get("/api/v1/admin/feedback/{id}", bugFeedback)
                        .header(HttpHeaders.AUTHORIZATION, adminToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.feedbackType").value("BUG"))
                .andExpect(jsonPath("$.data", not(hasKey("content"))))
                .andExpect(jsonPath("$.data", not(hasKey("contact"))));

        mockMvc.perform(patch("/api/v1/admin/feedback/{id}/status", bugFeedback)
                        .header(HttpHeaders.AUTHORIZATION, adminToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("status", "PROCESSING"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.status").value("PROCESSING"))
                .andExpect(jsonPath("$.data", not(hasKey("content"))))
                .andExpect(jsonPath("$.data", not(hasKey("contact"))));

        Integer feedbackStatusAudits = jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM admin_audit_logs WHERE action = 'ADMIN_UPDATE_FEEDBACK_STATUS' AND target_type = 'FEEDBACK' AND target_id = ?",
                Integer.class,
                bugFeedback);
        org.assertj.core.api.Assertions.assertThat(feedbackStatusAudits).isEqualTo(1);

        mockMvc.perform(get("/api/v1/admin/audit-logs")
                        .param("action", "ADMIN_UPDATE_MEMBERSHIP")
                        .param("targetType", "USER")
                        .param("targetId", aliceUserId.toString())
                        .header(HttpHeaders.AUTHORIZATION, adminToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.items", hasSize(1)))
                .andExpect(jsonPath("$.data.items[0].action").value("ADMIN_UPDATE_MEMBERSHIP"))
                .andExpect(jsonPath("$.data.items[0]", not(hasKey("requestBody"))));

        mockMvc.perform(get("/api/v1/admin/audit-logs/{id}", 1L)
                        .header(HttpHeaders.AUTHORIZATION, aliceToken))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("FORBIDDEN"));
    }

    private org.springframework.test.web.servlet.ResultActions aiAction(String token, Long recordId) throws Exception {
        return mockMvc.perform(post("/api/v1/ai/actions")
                .header(HttpHeaders.AUTHORIZATION, token)
                .contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of(
                        "recordId", recordId,
                        "action", "SUMMARY",
                        "consentAccepted", true))));
    }

    private void acceptAiConsent(String token) throws Exception {
        mockMvc.perform(post("/api/v1/ai/consent")
                        .header(HttpHeaders.AUTHORIZATION, token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("accepted", true))))
                .andExpect(status().isOk());
    }

    private org.springframework.test.web.servlet.ResultActions exportPdf(String token, Long recordId) throws Exception {
        return mockMvc.perform(post("/api/v1/exports/pdf")
                .header(HttpHeaders.AUTHORIZATION, token)
                .contentType(MediaType.APPLICATION_JSON)
                .content(json(Map.of(
                        "recordIds", List.of(recordId),
                        "fileName", "quota.pdf",
                        "searchable", false))));
    }

    private Long insertRecord(Long userId) {
        return insertRecord(userId, "Quota", "camera");
    }

    private Long insertRecord(Long userId, String title, String sourceType) {
        jdbcTemplate.update("""
                INSERT INTO recognition_records
                    (user_id, title, source_type, raw_text, edited_text, favorite, deleted, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, 0, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """, userId, title, sourceType, "raw " + title + " text", "edited " + title + " text");
        return jdbcTemplate.queryForObject("SELECT MAX(id) FROM recognition_records", Long.class);
    }

    private Long insertFeedback(Long userId, String feedbackType, String status) {
        jdbcTemplate.update("""
                INSERT INTO feedback
                    (user_id, feedback_type, content, contact, device_info, app_version, status, deleted, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """, userId, feedbackType, "feedback content", "contact@example.test", "device", "test", status);
        return jdbcTemplate.queryForObject("SELECT MAX(id) FROM feedback", Long.class);
    }

    private void insertAudit(Long adminUserId, String action, String targetType, Long targetId) {
        jdbcTemplate.update("""
                INSERT INTO admin_audit_logs (admin_user_id, action, target_type, target_id, created_at)
                VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
                """, adminUserId, action, targetType, targetId);
    }

    private void seedAdmin(Long userId) {
        jdbcTemplate.update("""
                INSERT INTO admin_accounts (user_id, role, created_at)
                VALUES (?, 'SUPER_ADMIN', CURRENT_TIMESTAMP)
                """, userId);
    }

    private void register(String username, String password) throws Exception {
        mockMvc.perform(post("/api/v1/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("username", username, "password", password))))
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
