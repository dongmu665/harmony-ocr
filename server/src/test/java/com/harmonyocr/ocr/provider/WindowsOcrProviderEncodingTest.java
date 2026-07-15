package com.harmonyocr.ocr.provider;

import com.harmonyocr.common.error.BusinessException;
import com.harmonyocr.common.error.ErrorCode;
import com.harmonyocr.ocr.dto.OcrResult;
import com.harmonyocr.ocr.dto.OcrTextBlockResponse;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.List;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Windows OCR 编码回归测试，属于 ocr/provider 模块。
 * 维护说明：固定 PowerShell stdout 到 Java 解码的 UTF-8 契约，避免中文 OCR 文本被替换字符污染。
 */
class WindowsOcrProviderEncodingTest {

    @Test
    void strictUtf8DecoderPreservesChineseOcrText() {
        String text = "中文OCR测试";

        String decoded = WindowsOcrProvider.decodeUtf8Strict(
                text.getBytes(StandardCharsets.UTF_8),
                "Windows OCR output encoding mismatch");

        assertThat(decoded).isEqualTo(text);
    }

    @Test
    void strictUtf8DecoderRejectsLegacyChineseBytesInsteadOfReplacementCharacters() {
        byte[] gbkBytes = "中文OCR测试".getBytes(Charset.forName("GBK"));

        assertThatThrownBy(() -> WindowsOcrProvider.decodeUtf8Strict(
                gbkBytes,
                "Windows OCR output encoding mismatch"))
                .isInstanceOfSatisfying(BusinessException.class, ex -> {
                    assertThat(ex.getErrorCode()).isEqualTo(ErrorCode.OCR_FAILED);
                    assertThat(ex.getMessage()).isEqualTo("Windows OCR output encoding mismatch");
                });
    }

    @Test
    void windowsOcrScriptDeclaresExplicitUtf8StdoutContract() throws IOException {
        String script = windowsOcrScript();

        assertThat(script)
                .contains("[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)")
                .contains("$OutputEncoding = [System.Text.UTF8Encoding]::new($false)")
                .contains("function Write-Utf8Line")
                .contains("Write-Utf8Line $result.Text")
                .contains("Write-Utf8Line \"OK\"")
                .doesNotContain("Write-Output $result.Text")
                .doesNotContain("Write-Output \"OK\"");
    }

    @Test
    void mixedLanguageHintRunsChineseAndEnglishPlan() {
        assertThat(WindowsOcrProvider.languagePlan("zh-Hans,en", "eng"))
                .containsExactly("zh-Hans", "en");
        assertThat(WindowsOcrProvider.languagePlan("zh_en", "eng"))
                .containsExactly("zh-Hans", "en");
        assertThat(WindowsOcrProvider.languagePlan("zh-Hans", "eng"))
                .containsExactly("zh-Hans");
        assertThat(WindowsOcrProvider.languagePlan("en", "zh-Hans"))
                .containsExactly("en");
    }

    @Test
    void mixedResultSelectionPreservesChineseEnglishPage() {
        OcrResult chineseResult = result(
                "示例大学移动应用 PDF 样例材料\nStudent: Alex\n学号: 000000001",
                "zh-Hans");
        OcrResult englishOnlyResult = result("PDF PDF PDF 000000001 000000001", "en");

        OcrResult selected = WindowsOcrProvider.selectBestMixedResult(List.of(chineseResult, englishOnlyResult));

        assertThat(selected).isSameAs(chineseResult);
    }

    @Test
    void mixedResultSelectionCanPreferEnglishOnlyPage() {
        OcrResult weakChineseResult = result("PDF 000000001", "zh-Hans");
        OcrResult englishResult = result("Example University Software Development PDF Sample Material 000000001", "en");

        OcrResult selected = WindowsOcrProvider.selectBestMixedResult(List.of(weakChineseResult, englishResult));

        assertThat(selected).isSameAs(englishResult);
    }

    private String windowsOcrScript() throws IOException {
        try (InputStream inputStream = WindowsOcrProvider.class.getResourceAsStream("/ocr/windows-ocr.ps1")) {
            assertThat(inputStream).isNotNull();
            return new String(inputStream.readAllBytes(), StandardCharsets.UTF_8);
        }
    }

    private OcrResult result(String text, String language) {
        return new OcrResult(
                "windows",
                "windows-media-ocr",
                "pdf-page-1",
                text,
                12,
                language,
                null,
                null,
                List.of(new OcrTextBlockResponse(1, text, null, null)),
                null);
    }
}
