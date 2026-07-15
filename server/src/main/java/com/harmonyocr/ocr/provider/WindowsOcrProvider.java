package com.harmonyocr.ocr.provider;

import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.ocr.config.OcrProperties;
import com.harmonyocr.ocr.dto.OcrRequest;
import com.harmonyocr.ocr.dto.OcrResult;
import com.harmonyocr.ocr.dto.OcrTextBlockResponse;
import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.TimeUnit;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

/**
 * Windows Runtime OCR Provider，属于 ocr 模块。
 * 维护说明：通过本机 Windows.Media.Ocr 识别图片，属于真实离线 OCR；不调用云服务，不记录图片内容、OCR 全文或临时路径。
 */
@Component
@ConditionalOnProperty(prefix = "app.ocr", name = "provider", havingValue = "windows", matchIfMissing = true)
public class WindowsOcrProvider implements OcrProvider {

    private final OcrProperties properties;

    public WindowsOcrProvider(OcrProperties properties) {
        this.properties = properties;
    }

    /**
     * 调用 Windows OCR 识别图片。
     * 通过受控 PowerShell 脚本桥接 WinRT API，参数只包含临时图片路径和语言，不拼接用户输入 shell。
     */
    @Override
    public OcrResult recognize(OcrRequest request) {
        if (!properties.enabled()) {
            throw new BusinessException(ErrorCode.OCR_FAILED, "OCR provider is disabled");
        }
        long start = System.nanoTime();
        Path imageFile = null;
        Path scriptFile = null;
        try {
            imageFile = Files.createTempFile("harmony-ocr-windows-", extension(request.contentType()));
            scriptFile = writeScriptResource();
            Files.write(imageFile, request.content());
            List<String> languages = languagePlan(request.language(), properties.language());
            List<OcrResult> successfulResults = new ArrayList<>();
            BusinessException firstFailure = null;
            for (String language : languages) {
                try {
                    String stdout = runWindowsOcr(scriptFile, imageFile, language);
                    if (stdout.isBlank()) {
                        throw new BusinessException(ErrorCode.OCR_FAILED, "OCR result is empty");
                    }
                    successfulResults.add(toOcrResult(
                            request,
                            stdout,
                            language,
                            Duration.ofNanos(System.nanoTime() - start).toMillis()));
                } catch (BusinessException ex) {
                    if (firstFailure == null) {
                        firstFailure = ex;
                    }
                    if (languages.size() == 1) {
                        throw ex;
                    }
                }
            }
            if (successfulResults.isEmpty()) {
                if (firstFailure != null) {
                    throw firstFailure;
                }
                throw new BusinessException(ErrorCode.OCR_FAILED, "Windows OCR provider failed");
            }
            OcrResult selected = languages.size() == 1
                    ? successfulResults.getFirst()
                    : selectBestMixedResult(successfulResults);
            return withDurationAndLanguage(
                    selected,
                    Duration.ofNanos(System.nanoTime() - start).toMillis(),
                    responseLanguage(languages, selected.language()));
        } catch (BusinessException ex) {
            throw ex;
        } catch (IOException ex) {
            throw new BusinessException(ErrorCode.OCR_FAILED, "Windows OCR provider is unavailable");
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            throw new BusinessException(ErrorCode.OCR_TIMEOUT);
        } finally {
            deleteQuietly(imageFile);
            deleteQuietly(scriptFile);
        }
    }

    private String runWindowsOcr(Path scriptFile, Path imageFile, String language) throws IOException, InterruptedException {
        Process process = new ProcessBuilder(
                properties.executable(),
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                scriptFile.toString(),
                "-ImagePath",
                imageFile.toString(),
                "-Language",
                language)
                .start();
        boolean finished = process.waitFor(properties.timeoutMs(), TimeUnit.MILLISECONDS);
        if (!finished) {
            process.destroyForcibly();
            throw new BusinessException(ErrorCode.OCR_TIMEOUT);
        }
        String stdout = decodeUtf8Strict(
                process.getInputStream().readAllBytes(),
                "Windows OCR output encoding mismatch").trim();
        String stderr = decodeUtf8Strict(
                process.getErrorStream().readAllBytes(),
                "Windows OCR error output encoding mismatch").trim();
        if (process.exitValue() != 0) {
            throw new BusinessException(ErrorCode.OCR_FAILED, safeError(stderr));
        }
        return stdout;
    }

    private OcrResult toOcrResult(OcrRequest request, String stdout, String language, long durationMs) {
        return new OcrResult(
                providerName(),
                engineName(),
                request.mode(),
                stdout,
                durationMs,
                language,
                null,
                null,
                List.of(new OcrTextBlockResponse(1, stdout, null, null)),
                null);
    }

    private OcrResult withDurationAndLanguage(OcrResult result, long durationMs, String language) {
        return new OcrResult(
                result.providerName(),
                result.engineName(),
                result.mode(),
                result.rawText(),
                durationMs,
                language,
                result.confidence(),
                result.boundingBox(),
                result.blocks(),
                result.errorCode());
    }

    /**
     * 检查 Windows OCR Runtime 是否可创建英文识别引擎。
     */
    @Override
    public boolean isAvailable() {
        Path scriptFile = null;
        try {
            scriptFile = writeScriptResource();
            Process process = new ProcessBuilder(
                    properties.executable(),
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    scriptFile.toString(),
                    "-Health",
                    "-Language",
                    safeLanguage(properties.language()))
                    .start();
            boolean finished = process.waitFor(5000, TimeUnit.MILLISECONDS);
            if (!finished) {
                process.destroyForcibly();
                return false;
            }
            String stdout = decodeUtf8Strict(
                    process.getInputStream().readAllBytes(),
                    "Windows OCR output encoding mismatch").trim();
            decodeUtf8Strict(
                    process.getErrorStream().readAllBytes(),
                    "Windows OCR error output encoding mismatch");
            return process.exitValue() == 0 && "OK".equals(stdout);
        } catch (BusinessException | IOException ex) {
            return false;
        } catch (InterruptedException ex) {
            Thread.currentThread().interrupt();
            return false;
        } finally {
            deleteQuietly(scriptFile);
        }
    }

    /**
     * 返回 Windows.Media.Ocr 引擎标识。
     * 该值用于结果元数据展示，不包含 PowerShell 脚本路径或临时图片路径。
     */
    @Override
    public String engineName() {
        return "windows-media-ocr";
    }

    /**
     * 返回 Windows 本机 OCR provider 标识。
     * 该值只表示本地离线识别来源，不暴露设备路径或系统细节。
     */
    @Override
    public String providerName() {
        return "windows";
    }

    private Path writeScriptResource() throws IOException {
        try (InputStream inputStream = WindowsOcrProvider.class.getResourceAsStream("/ocr/windows-ocr.ps1")) {
            if (inputStream == null) {
                throw new IOException("windows OCR script missing");
            }
            Path script = Files.createTempFile("harmony-ocr-windows-", ".ps1");
            Files.write(script, inputStream.readAllBytes());
            return script;
        }
    }

    private String safeLanguage(String language) {
        return languagePlan(language, properties.language()).getFirst();
    }

    /**
     * 解析 OCR 语言计划。
     * 混合语言用两次本地 OCR 结果择优，避免英文引擎把中文页误读成符号，也避免英文页被中文页策略锁死。
     */
    static List<String> languagePlan(String language, String defaultLanguage) {
        String candidate = language == null || language.isBlank() ? defaultLanguage : language;
        if (candidate == null || candidate.isBlank()) {
            candidate = "en";
        }
        String normalized = candidate.trim().toLowerCase(Locale.ROOT);
        if (isMixedLanguage(normalized)) {
            return List.of("zh-Hans", "en");
        }
        if (normalized.startsWith("zh")) {
            return List.of("zh-Hans");
        }
        return List.of("en");
    }

    private static boolean isMixedLanguage(String normalizedLanguage) {
        return normalizedLanguage.contains("zh_en")
                || normalizedLanguage.contains("zh-hans,en")
                || normalizedLanguage.contains("zh,en")
                || normalizedLanguage.contains("mixed")
                || (normalizedLanguage.contains("zh") && normalizedLanguage.contains("en"));
    }

    private String responseLanguage(List<String> languages, String selectedLanguage) {
        if (languages.size() > 1) {
            return String.join(",", languages);
        }
        return selectedLanguage;
    }

    /**
     * 在中英混合候选结果中选择信息量更高的输出。
     * 这里不做无坐标文本拼接，避免把两次 OCR 的重复行或错序行返回给前端。
     */
    static OcrResult selectBestMixedResult(List<OcrResult> results) {
        if (results == null || results.isEmpty()) {
            throw new IllegalArgumentException("results must not be empty");
        }
        OcrResult best = results.getFirst();
        int bestScore = mixedLanguageScore(best.rawText());
        for (int index = 1; index < results.size(); index++) {
            OcrResult candidate = results.get(index);
            int score = mixedLanguageScore(candidate.rawText());
            if (score > bestScore) {
                best = candidate;
                bestScore = score;
            }
        }
        return best;
    }

    static int mixedLanguageScore(String text) {
        if (text == null || text.isBlank()) {
            return Integer.MIN_VALUE;
        }
        int score = 0;
        for (int offset = 0; offset < text.length(); ) {
            int codePoint = text.codePointAt(offset);
            offset += Character.charCount(codePoint);
            if (isCjk(codePoint)) {
                score += 12;
            } else if (isLatinLetter(codePoint)) {
                score += 2;
            } else if (Character.isDigit(codePoint)) {
                score += 1;
            } else if (codePoint == '\uFFFD') {
                score -= 30;
            } else if (Character.isISOControl(codePoint)) {
                score -= 3;
            } else if (!Character.isWhitespace(codePoint)) {
                score -= 1;
            }
        }
        return score;
    }

    private static boolean isLatinLetter(int codePoint) {
        return (codePoint >= 'A' && codePoint <= 'Z') || (codePoint >= 'a' && codePoint <= 'z');
    }

    private static boolean isCjk(int codePoint) {
        return (codePoint >= 0x4E00 && codePoint <= 0x9FFF)
                || (codePoint >= 0x3400 && codePoint <= 0x4DBF)
                || (codePoint >= 0x20000 && codePoint <= 0x2A6DF)
                || (codePoint >= 0x2A700 && codePoint <= 0x2B73F)
                || (codePoint >= 0x2B740 && codePoint <= 0x2B81F)
                || (codePoint >= 0x2B820 && codePoint <= 0x2CEAF)
                || (codePoint >= 0xF900 && codePoint <= 0xFAFF);
    }

    private String extension(String contentType) {
        return switch (contentType) {
            case "image/jpeg" -> ".jpg";
            case "image/webp" -> ".webp";
            default -> ".png";
        };
    }

    /**
     * 严格按 UTF-8 解码 PowerShell 输出。
     * 如果 Windows OCR stdout/stderr 出现非 UTF-8 字节，必须失败，避免替换字符进入 JSON 和前端。
     */
    static String decodeUtf8Strict(byte[] bytes, String mismatchMessage) {
        try {
            return StandardCharsets.UTF_8
                    .newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(bytes))
                    .toString();
        } catch (CharacterCodingException ex) {
            throw new BusinessException(ErrorCode.OCR_FAILED, mismatchMessage);
        }
    }

    private String safeError(String value) {
        if (value == null || value.isBlank()) {
            return "Windows OCR provider failed";
        }
        String singleLine = value.replaceAll("[\\r\\n]+", " ").trim();
        if (singleLine.contains("Windows OCR engine unavailable")) {
            return "Windows OCR engine unavailable for requested language";
        }
        if (singleLine.contains("OCR image missing")) {
            return "OCR image missing";
        }
        if (singleLine.contains("Windows OCR failed")) {
            return "Windows OCR failed";
        }
        return "Windows OCR provider failed";
    }

    private void deleteQuietly(Path path) {
        if (path == null) {
            return;
        }
        try {
            Files.deleteIfExists(path);
        } catch (IOException ignored) {
        }
    }
}
