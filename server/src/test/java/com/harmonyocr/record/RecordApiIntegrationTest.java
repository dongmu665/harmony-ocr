package com.harmonyocr.record;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.List;
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
 * OCR 历史记录 API 集成测试。
 * 维护说明：覆盖创建、列表、详情、编辑、收藏、搜索和删除的当前用户归属校验。
 */
class RecordApiIntegrationTest {

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
    void createRecordWithoutAccessTokenReturnsUnauthorizedUnifiedResponse() throws Exception {
        mockMvc.perform(post("/api/v1/records")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("sourceType", "camera", "rawText", "hello"))))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("UNAUTHORIZED"))
                .andExpect(jsonPath("$.timestamp").exists());
    }

    @Test
    void createRecordWithBlocksStoresCurrentUserRecordAndReturnsDetail() throws Exception {
        register("alice", "password123");
        String accessToken = accessToken("alice");

        MvcResult result = mockMvc.perform(post("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "userId", 9999,
                                "title", "Receipt",
                                "sourceType", "camera",
                                "rawText", "raw text",
                                "editedText", "edited text",
                                "language", "zh-CN",
                                "ocrEngine", "device-ocr",
                                "durationMs", 120,
                                "favorite", true,
                                "blocks", List.of(Map.of(
                                        "blockIndex", 0,
                                        "text", "raw",
                                        "confidence", 0.9876,
                                        "boundingBox", "{\"x\":1,\"y\":2}"))))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.code").value("OK"))
                .andExpect(jsonPath("$.data.id").isNumber())
                .andExpect(jsonPath("$.data.title").value("Receipt"))
                .andExpect(jsonPath("$.data.sourceType").value("camera"))
                .andExpect(jsonPath("$.data.language").value("zh-CN"))
                .andExpect(jsonPath("$.data.durationMs").value(120))
                .andExpect(jsonPath("$.data.favorite").value(true))
                .andExpect(jsonPath("$.data.blocks[0].text").value("raw"))
                .andReturn();

        Long recordId = jsonNode(result).path("data").path("id").asLong();
        Long ownerId = jdbcTemplate.queryForObject(
                "SELECT user_id FROM recognition_records WHERE id = ?",
                Long.class,
                recordId);
        assertThat(ownerId).isEqualTo(userId("alice"));
        assertThat(jdbcTemplate.queryForObject(
                "SELECT COUNT(*) FROM recognition_blocks WHERE record_id = ?",
                Integer.class,
                recordId)).isEqualTo(1);
    }

    @Test
    void createRecordValidatesImageObjectKeyBelongsToCurrentUserActiveFile() throws Exception {
        register("alice", "password123");
        register("bob", "password123");
        String aliceToken = accessToken("alice");
        Long aliceId = userId("alice");
        Long bobId = userId("bob");
        String aliceObjectKey = insertFile(aliceId, "files/2026/05/25/alice.png", false);
        String bobObjectKey = insertFile(bobId, "files/2026/05/25/bob.png", false);
        String deletedObjectKey = insertFile(aliceId, "files/2026/05/25/deleted.png", true);

        mockMvc.perform(post("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "sourceType", "camera",
                                "imageObjectKey", aliceObjectKey))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.imageObjectKey").value(aliceObjectKey));

        mockMvc.perform(post("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "sourceType", "camera",
                                "imageObjectKey", bobObjectKey))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));

        mockMvc.perform(post("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "sourceType", "camera",
                                "imageObjectKey", deletedObjectKey))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));

        mockMvc.perform(post("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "sourceType", "camera",
                                "imageObjectKey", "files/2026/05/25/missing.png"))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));

        mockMvc.perform(post("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(aliceToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "sourceType", "camera",
                                "rawText", "plain text"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.rawText").value("plain text"));
    }

    @Test
    void createRecordRejectsDuplicateBlockIndexBeforeDatabaseConstraint() throws Exception {
        register("alice", "password123");
        String accessToken = accessToken("alice");

        mockMvc.perform(post("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "sourceType", "camera",
                                "rawText", "text",
                                "blocks", List.of(
                                        Map.of("blockIndex", 1, "text", "first"),
                                        Map.of("blockIndex", 1, "text", "second"))))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
    }

    @Test
    void listRecordsClampsNegativePageAndOversizedPageSize() throws Exception {
        register("alice", "password123");
        Long aliceId = userId("alice");
        for (int i = 0; i < 105; i++) {
            insertRecord(aliceId, "Record " + i, "camera", "raw keyword " + i, null, false, false);
        }

        mockMvc.perform(get("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice")))
                        .param("page", "-10")
                        .param("size", "500")
                        .param("keyword", "keyword"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.page").value(0))
                .andExpect(jsonPath("$.data.size").value(100))
                .andExpect(jsonPath("$.data.items.length()").value(100))
                .andExpect(jsonPath("$.data.total").value(105));
    }

    @Test
    void createRecordRejectsInvalidSourceTypeAndEmptyBusinessContent() throws Exception {
        register("alice", "password123");
        String accessToken = accessToken("alice");

        mockMvc.perform(post("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("sourceType", "scanner", "rawText", "text"))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));

        mockMvc.perform(post("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("sourceType", "camera"))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));

        mockMvc.perform(post("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "sourceType", "camera",
                                "blocks", List.of(Map.of())))))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.success").value(false))
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
    }

    @Test
    void listRecordsReturnsCurrentUsersNonDeletedRecordsWithFilters() throws Exception {
        register("alice", "password123");
        register("bob", "password123");
        Long aliceId = userId("alice");
        Long bobId = userId("bob");
        insertRecord(aliceId, "Camera favorite", "camera", "invoice raw", null, true, false);
        insertRecord(aliceId, "Album normal", "album", "album raw", null, false, false);
        insertRecord(aliceId, "Deleted", "camera", "deleted raw", null, true, true);
        insertRecord(bobId, "Bob", "camera", "bob raw", null, true, false);

        mockMvc.perform(get("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice")))
                        .param("favorite", "true")
                        .param("sourceType", "camera")
                        .param("page", "0")
                        .param("size", "10"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.data.total").value(1))
                .andExpect(jsonPath("$.data.items[0].title").value("Camera favorite"));
    }

    @Test
    void listRecordsFiltersByCreatedAtRangeTogetherWithSourceAndKeyword() throws Exception {
        register("alice", "password123");
        Long aliceId = userId("alice");
        Long oldCamera = insertRecord(aliceId, "Old camera", "camera", "receipt old", null, false, false);
        Long recentCamera = insertRecord(aliceId, "Recent camera", "camera", "receipt current", null, false, false);
        Long recentAlbum = insertRecord(aliceId, "Recent album", "album", "receipt current", null, false, false);
        jdbcTemplate.update("UPDATE recognition_records SET created_at = '2026-05-01 10:00:00', updated_at = '2026-05-01 10:00:00' WHERE id = ?", oldCamera);
        jdbcTemplate.update("UPDATE recognition_records SET created_at = '2026-05-20 10:00:00', updated_at = '2026-05-20 10:00:00' WHERE id = ?", recentCamera);
        jdbcTemplate.update("UPDATE recognition_records SET created_at = '2026-05-21 10:00:00', updated_at = '2026-05-21 10:00:00' WHERE id = ?", recentAlbum);

        mockMvc.perform(get("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice")))
                        .param("sourceType", "camera")
                        .param("keyword", "receipt")
                        .param("createdFrom", "2026-05-15T00:00:00")
                        .param("createdTo", "2026-05-22T00:00:00"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.total").value(1))
                .andExpect(jsonPath("$.data.items[0].title").value("Recent camera"));
    }

    @Test
    void listRecordsSupportsAdvancedDateTagEngineFavoriteAndSortFilters() throws Exception {
        register("alice", "password123");
        register("bob", "password123");
        Long aliceId = userId("alice");
        Long bobId = userId("bob");
        Long tagId = insertTag(aliceId, "通知公告");
        Long first = insertRecord(aliceId, "First notice", "album", "course keyword", null, true, false, "device-ocr");
        Long second = insertRecord(aliceId, "Second notice", "album", "course keyword", null, true, false, "device-ocr");
        Long noTag = insertRecord(aliceId, "No tag", "album", "course keyword", null, true, false, "device-ocr");
        Long wrongEngine = insertRecord(aliceId, "Wrong engine", "album", "course keyword", null, true, false, "backend-ocr");
        Long bobRecord = insertRecord(bobId, "Bob notice", "album", "course keyword", null, true, false, "device-ocr");
        bindTag(aliceId, first, tagId);
        bindTag(aliceId, second, tagId);
        bindTag(aliceId, wrongEngine, tagId);
        bindTag(bobId, bobRecord, insertTag(bobId, "通知公告"));
        jdbcTemplate.update("UPDATE recognition_records SET created_at = '2026-05-20 09:00:00', updated_at = '2026-05-20 09:00:00' WHERE id = ?", first);
        jdbcTemplate.update("UPDATE recognition_records SET created_at = '2026-05-21 10:00:00', updated_at = '2026-05-21 10:00:00' WHERE id = ?", second);
        jdbcTemplate.update("UPDATE recognition_records SET created_at = '2026-05-21 11:00:00', updated_at = '2026-05-21 11:00:00' WHERE id = ?", noTag);
        jdbcTemplate.update("UPDATE recognition_records SET created_at = '2026-05-21 12:00:00', updated_at = '2026-05-21 12:00:00' WHERE id = ?", wrongEngine);

        mockMvc.perform(get("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice")))
                        .param("keyword", "course")
                        .param("dateFrom", "2026-05-20T00:00:00")
                        .param("dateTo", "2026-05-22T00:00:00")
                        .param("sourceType", "album")
                        .param("favorite", "true")
                        .param("tagId", String.valueOf(tagId))
                        .param("ocrEngine", "device-ocr")
                        .param("sort", "createdAt_asc"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.total").value(2))
                .andExpect(jsonPath("$.data.items[0].id").value(first))
                .andExpect(jsonPath("$.data.items[1].id").value(second))
                .andExpect(jsonPath("$.data.items[0].tags[0].id").value(tagId));

        mockMvc.perform(get("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice")))
                        .param("sort", "raw_sql_desc"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));

        mockMvc.perform(get("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice")))
                        .param("dateFrom", "2026-05-22T00:00:00")
                        .param("dateTo", "2026-05-20T00:00:00"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.code").value("VALIDATION_ERROR"));
    }

    @Test
    void detailUpdateFavoriteDeleteAndSearchOwnedRecord() throws Exception {
        register("alice", "password123");
        String accessToken = accessToken("alice");
        Long recordId = insertRecord(userId("alice"), "Initial", "camera", "raw keyword", "edited", false, false);

        mockMvc.perform(get("/api/v1/records/{id}", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.title").value("Initial"));

        mockMvc.perform(patch("/api/v1/records/{id}", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "title", "Updated",
                                "editedText", "edited keyword",
                                "favorite", true))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.title").value("Updated"))
                .andExpect(jsonPath("$.data.editedText").value("edited keyword"))
                .andExpect(jsonPath("$.data.favorite").value(true));

        mockMvc.perform(patch("/api/v1/records/{id}/favorite", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("favorite", false))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.favorite").value(false));

        mockMvc.perform(get("/api/v1/records/search")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken))
                        .param("keyword", "keyword"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.total").value(1));

        mockMvc.perform(delete("/api/v1/records/{id}", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true));

        mockMvc.perform(get("/api/v1/records/{id}", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));

        mockMvc.perform(get("/api/v1/records")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.total").value(0));
    }

    @Test
    void postFavoriteCompatibilityUpdatesOwnedRecordForHarmonyOsClient() throws Exception {
        register("alice", "password123");
        String accessToken = accessToken("alice");
        Long recordId = insertRecord(userId("alice"), "HarmonyOS favorite", "camera", "raw", null, false, false);

        mockMvc.perform(post("/api/v1/records/{id}/favorite", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("favorite", true))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.favorite").value(true));

        mockMvc.perform(post("/api/v1/records/{id}/favorite", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("favorite", false))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.favorite").value(false));
    }

    @Test
    void postUpdateCompatibilityUpdatesOwnedRecordForHarmonyOsClient() throws Exception {
        register("alice", "password123");
        String accessToken = accessToken("alice");
        Long recordId = insertRecord(userId("alice"), "HarmonyOS edit", "camera", "raw", "old edit", false, false);

        mockMvc.perform(post("/api/v1/records/{id}/update", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of(
                                "title", "HarmonyOS edit saved",
                                "editedText", "new edited keyword",
                                "favorite", true))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.title").value("HarmonyOS edit saved"))
                .andExpect(jsonPath("$.data.editedText").value("new edited keyword"))
                .andExpect(jsonPath("$.data.favorite").value(true));

        register("bob", "password123");
        mockMvc.perform(post("/api/v1/records/{id}/update", recordId)
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("bob")))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json(Map.of("editedText", "cross-user edit"))))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.code").value("NOT_FOUND"));
    }

    @Test
    void emptyKeywordSearchReturnsOrdinaryPagedList() throws Exception {
        register("alice", "password123");
        insertRecord(userId("alice"), "Ordinary", "album", "raw", null, false, false);

        mockMvc.perform(get("/api/v1/records/search")
                        .header(HttpHeaders.AUTHORIZATION, bearer(accessToken("alice")))
                        .param("keyword", ""))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.data.total").value(1))
                .andExpect(jsonPath("$.data.items[0].title").value("Ordinary"));
    }

    @Test
    void healthEndpointStillAllowsAnonymousAccessAfterRecordModule() throws Exception {
        mockMvc.perform(get("/api/v1/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.success").value(true))
                .andExpect(jsonPath("$.code").value("OK"));
    }

    private Long insertRecord(Long userId, String title, String sourceType, String rawText,
                              String editedText, boolean favorite, boolean deleted) {
        return insertRecord(userId, title, sourceType, rawText, editedText, favorite, deleted, null);
    }

    private Long insertRecord(Long userId, String title, String sourceType, String rawText,
                              String editedText, boolean favorite, boolean deleted, String ocrEngine) {
        jdbcTemplate.update("""
                INSERT INTO recognition_records
                    (user_id, title, source_type, raw_text, edited_text, favorite, deleted, ocr_engine,
                     created_at, updated_at, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP,
                        CASE WHEN ? THEN CURRENT_TIMESTAMP ELSE NULL END)
                """, userId, title, sourceType, rawText, editedText, favorite ? 1 : 0, deleted ? 1 : 0, ocrEngine, deleted);
        return jdbcTemplate.queryForObject("SELECT MAX(id) FROM recognition_records", Long.class);
    }

    private Long insertTag(Long userId, String name) {
        jdbcTemplate.update("""
                INSERT INTO recognition_tags
                    (user_id, name, normalized_name, created_at, updated_at)
                VALUES (?, ?, LOWER(?), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
                """, userId, name, name);
        return jdbcTemplate.queryForObject("SELECT MAX(id) FROM recognition_tags", Long.class);
    }

    private void bindTag(Long userId, Long recordId, Long tagId) {
        jdbcTemplate.update("""
                INSERT INTO recognition_record_tags
                    (user_id, record_id, tag_id, created_at)
                VALUES (?, ?, ?, CURRENT_TIMESTAMP)
                """, userId, recordId, tagId);
    }

    private String insertFile(Long userId, String objectKey, boolean deleted) {
        jdbcTemplate.update("""
                INSERT INTO file_objects
                    (user_id, object_key, original_filename, content_type, file_size, file_hash, storage_provider, bucket_name,
                     deleted, created_at, deleted_at, storage_delete_status)
                VALUES (?, ?, 'image.png', 'image/png', 12, 'hash', 'minio', 'harmony-ocr-test',
                        ?, CURRENT_TIMESTAMP, CASE WHEN ? THEN CURRENT_TIMESTAMP ELSE NULL END,
                        CASE WHEN ? THEN 'DELETED' ELSE 'ACTIVE' END)
                """, userId, objectKey, deleted ? 1 : 0, deleted, deleted);
        return objectKey;
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
