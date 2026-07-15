package com.harmonyocr.ai.provider;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.harmonyocr.ai.config.AiProperties;
import com.harmonyocr.ai.config.OpenAiCompatibleProviderCondition;
import com.harmonyocr.ai.dto.AiActionResponse;
import com.harmonyocr.ai.dto.AiProviderRequest;
import com.harmonyocr.ai.service.AiPromptTemplate;
import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import java.time.Duration;
import java.util.List;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.context.annotation.Conditional;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

/**
 * OpenAI-compatible AI Provider，属于 ai 模块。
 * 维护说明：通过临时环境变量读取 Base URL、API Key 和模型；请求和异常都不得记录 OCR 原文、prompt、响应全文或密钥。
 */
@Component
@Conditional(OpenAiCompatibleProviderCondition.class)
public class OpenAiCompatibleAiProvider implements AiProvider {

    private static final String PROVIDER_NAME = "openai-compatible";
    private static final String FALLBACK_REASON = "Real AI provider failed; mock fallback response returned";

    private final AiProperties properties;
    private final RestTemplate restTemplate;
    private final MockAiProvider fallbackProvider = new MockAiProvider();
    private final ObjectMapper objectMapper = new ObjectMapper();

    public OpenAiCompatibleAiProvider(
            AiProperties properties,
            RestTemplateBuilder restTemplateBuilder) {
        this.properties = properties;
        this.restTemplate = restTemplateBuilder
                .setConnectTimeout(Duration.ofMillis(properties.timeoutMs()))
                .setReadTimeout(Duration.ofMillis(properties.timeoutMs()))
                .build();
    }

    /**
     * 调用 OpenAI-compatible chat completions 接口。
     * 参数 request 包含内存中的 OCR 文本；返回 provider 元数据和处理结果。失败时抛出脱敏业务异常，不回显 prompt 或响应全文。
     */
    @Override
    public AiActionResponse process(AiProviderRequest request) {
        if (properties.apiKey() == null || properties.apiKey().isBlank()) {
            throw new BusinessException(ErrorCode.VALIDATION_ERROR, "AI provider API key is not configured");
        }
        try {
            ResponseEntity<String> responseEntity = restTemplate.postForEntity(
                    endpoint("/chat/completions"),
                    new HttpEntity<>(toChatRequest(request), headers()),
                    String.class);
            OpenAiChatResponse response = parseResponse(responseEntity.getBody());
            String outputText = extractOutput(response);
            if (outputText.isBlank()) {
                throw new BusinessException(ErrorCode.INTERNAL_ERROR, "AI provider returned empty output");
            }
            return new AiActionResponse(
                    request.action(),
                    PROVIDER_NAME,
                    properties.model(),
                    outputText,
                    safeLength(request.sourceText()),
                    true,
                    false,
                    null,
                    null);
        } catch (BusinessException ex) {
            return fallbackProvider.degradedResponse(request, FALLBACK_REASON);
        } catch (RestClientException ex) {
            return fallbackProvider.degradedResponse(request, FALLBACK_REASON);
        }
    }

    private OpenAiChatRequest toChatRequest(AiProviderRequest request) {
        return new OpenAiChatRequest(
                properties.model(),
                List.of(
                        new ChatMessage("system", AiPromptTemplate.systemPrompt(request)),
                        new ChatMessage("user", AiPromptTemplate.userMessage(request.sourceText()))));
    }

    private HttpHeaders headers() {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.setBearerAuth(properties.apiKey());
        return headers;
    }

    private String endpoint(String path) {
        String base = properties.baseUrl().replaceAll("/+$", "");
        return path.startsWith("/") ? base + path : base + "/" + path;
    }

    private String extractOutput(OpenAiChatResponse response) {
        if (response == null || response.choices() == null || response.choices().isEmpty()) {
            return "";
        }
        ChatChoice choice = response.choices().getFirst();
        if (choice == null || choice.message() == null || choice.message().content() == null) {
            return "";
        }
        return choice.message().content().trim();
    }

    private OpenAiChatResponse parseResponse(String body) {
        if (body == null || body.isBlank()) {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "AI provider returned empty response");
        }
        try {
            return objectMapper.readValue(stripEventStreamPrefix(body), OpenAiChatResponse.class);
        } catch (JsonProcessingException ex) {
            throw new BusinessException(ErrorCode.INTERNAL_ERROR, "AI provider response is not valid JSON");
        }
    }

    private String stripEventStreamPrefix(String body) {
        String trimmed = body.trim();
        if (!trimmed.startsWith("data:")) {
            return trimmed;
        }
        return trimmed.lines()
                .filter(line -> line.startsWith("data:"))
                .map(line -> line.substring("data:".length()).trim())
                .filter(line -> !line.isBlank() && !"[DONE]".equals(line))
                .findFirst()
                .orElse("");
    }

    private int safeLength(String value) {
        return value == null ? 0 : value.length();
    }

    private record OpenAiChatRequest(String model, List<ChatMessage> messages) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    private record ChatMessage(String role, String content) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    private record OpenAiChatResponse(List<ChatChoice> choices) {
    }

    @JsonIgnoreProperties(ignoreUnknown = true)
    private record ChatChoice(ChatMessage message) {
    }
}
