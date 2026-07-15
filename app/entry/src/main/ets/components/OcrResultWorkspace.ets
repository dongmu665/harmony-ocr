import { AppTheme } from '../common/theme/AppTheme';
import { AppMotion } from '../common/theme/AppMotion';
import { HtmlToolChip } from './BrandComponents';

export type OcrResultWorkspaceTab = 'image' | 'text' | 'ai';
export type OcrPreviewKind = 'image' | 'pdf';

/**
 * OcrResultWorkspace 是 OCR 结果页的核心可复用工作台模式。
 * 维护边界：组件只接收脱敏后的展示文本和回调，不读取 Token、图片 URI、objectKey、账号信息或原始媒体路径。
 */
@Component
export struct OcrResultWorkspace {
  engineLabel: string = 'Harmony OCR V2';
  durationLabel: string = '2.8 秒';
  languageLabel: string = '中文 / English';
  confidenceLabel: string = '96.8%';
  @Prop editedText: string = '';
  imageUri: string = '';
  previewKind: OcrPreviewKind = 'image';
  previewAvailable: boolean = false;
  previewFallback: string = '暂未生成原图预览';
  imageHint: string = '原图预览';
  imageMeta: string = '';
  aiTitle: string = 'AI 结果';
  aiSummary: string = '';
  aiBullets: string = '';
  @Prop textHintLeft: string = '点击文本可直接编辑';
  @Prop textHintRight: string = '自动保存草稿';
  @Prop pageSelectorVisible: boolean = false;
  @Prop pageSelectorOptions: string[] = [];
  @Prop selectedPageOptionIndex: number = 0;
  lowConfidenceTitle: string = '2 个低置信字段待确认';
  lowConfidenceDescription: string = '如存在低置信字段，请核对原图后再保存、分享或导出。';
  onTextChange: (value: string) => void = () => {};
  onPageSelectorChange: (index: number) => void = () => {};
  onAiOrganize: () => void = () => {};
  aiEnabled: boolean = true;
  onExport: () => void = () => {};
  exportEnabled: boolean = true;
  onConfirmLowConfidence: () => void = () => {};
  onAiSummarize: () => void = () => {};
  onAiProofread: () => void = () => {};
  onAiTranslate: () => void = () => {};
  onAiExtractFields: () => void = () => {};
  onAiFormat: () => void = () => {};
  onMarkdown: () => void = () => {};
  showDocumentTools: boolean = true;
  @State private resultTab: OcrResultWorkspaceTab = 'text';
  @State private tabsEntered: boolean = false;
  @State private metaEntered: boolean = false;
  @State private panelEntered: boolean = false;
  @State private toolsEntered: boolean = false;
  @State private actionsEntered: boolean = false;
  @State private lowConfidenceEntered: boolean = false;
  @State private aiDraftText: string = '';
  @State private pressedTab: string = '';
  @State private pressedAction: string = '';
  private aiDraftTimer: number = -1;

  aboutToAppear(): void {
    this.triggerWorkspaceReveal();
  }

  aboutToDisappear(): void {
    this.stopAiDraftTyping();
  }

  /**
   * 结果工作台使用 40ms card stagger 映射 HTML motion-card 进入节奏。
   */
  private triggerWorkspaceReveal(): void {
    this.revealCard(() => this.tabsEntered = true, 0);
    this.revealCard(() => this.metaEntered = true, 1);
    this.revealCard(() => this.panelEntered = true, 2);
    this.revealCard(() => this.toolsEntered = true, 3);
    this.revealCard(() => this.actionsEntered = true, 4);
    this.revealCard(() => this.lowConfidenceEntered = true, 5);
  }

  private revealCard(update: () => void, index: number): void {
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: AppMotion.DURATION_NORMAL, curve: Curve.EaseOut }, update);
    }, index * AppMotion.STAGGER_CARD_MS);
  }

  /**
   * 切换原图、文本、AI 三段视图。
   * 安全边界：只切换展示状态，不修改 OCR 文本、不触发保存、不访问文件路径。
   */
  private switchTab(tab: OcrResultWorkspaceTab): void {
    if (this.resultTab === tab) {
      return;
    }
    this.getUIContext().animateTo({ duration: AppMotion.DURATION_SWITCH, curve: Curve.EaseOut }, () => {
      this.resultTab = tab;
    });
    if (tab === 'ai') {
      this.startAiDraftTyping();
    }
  }

  /**
   * AI 草稿使用短文本打字节奏贴近 HTML 原型；只处理已脱敏展示文案，不读取 OCR 全文或 prompt。
   */
  private startAiDraftTyping(): void {
    this.stopAiDraftTyping();
    const sourceText = this.fullAiDraftText();
    this.aiDraftText = '';
    if (sourceText.length === 0) {
      return;
    }
    let cursor = 0;
    this.aiDraftTimer = setInterval(() => {
      cursor += 1;
      this.aiDraftText = sourceText.slice(0, cursor);
      if (cursor >= sourceText.length) {
        this.stopAiDraftTyping();
      }
    }, AppMotion.TYPING_INTERVAL_MS);
  }

  private stopAiDraftTyping(): void {
    if (this.aiDraftTimer >= 0) {
      clearInterval(this.aiDraftTimer);
      this.aiDraftTimer = -1;
    }
  }

  private fullAiDraftText(): string {
    const summary = this.aiSummary.trim();
    const bullets = this.aiBullets.trim();
    if (summary.length > 0 && bullets.length > 0) {
      return summary + '\n\n' + bullets;
    }
    return summary.length > 0 ? summary : bullets;
  }

  private hasAiDraftResult(): boolean {
    return this.fullAiDraftText().length > 0;
  }

  private visibleAiDraftText(): string {
    return this.aiDraftText.length > 0 ? this.aiDraftText : this.fullAiDraftText();
  }

  /**
   * 示例合约文本使用原生高亮阅读态复刻 HTML 参考；真实 OCR 文本仍保留可编辑 TextArea。
   * 判断只基于当前组件已脱敏展示文本，不读取图片路径、对象键或后端敏感字段。
   */
  private shouldUseReferenceDocumentView(): boolean {
    return false;
  }

  private pageSelectorOptionIndex(label: string): number {
    for (let index = 0; index < this.pageSelectorOptions.length; index++) {
      if (this.pageSelectorOptions[index] === label) {
        return index;
      }
    }
    return 0;
  }

  @Builder
  private documentTextChunk(value: string, highlighted: boolean = false) {
    Text(value)
      .fontSize(14)
      .fontWeight(highlighted ? FontWeight.Bold : FontWeight.Regular)
      .fontColor(highlighted ? AppTheme.COLOR_TEXT_MUTED : AppTheme.COLOR_TEXT)
      .lineHeight(23)
      .padding(highlighted ? { left: 2, right: 2, top: 1, bottom: 1 } : 0)
      .backgroundColor(highlighted ? AppTheme.COLOR_ACCENT_SOFT : AppTheme.COLOR_TRANSPARENT)
      .borderRadius(highlighted ? 3 : 0)
  }

  @Builder
  private documentTextLine() {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      this.documentTextChunk('当前识别文本 ')
      this.documentTextChunk('可编辑', true)
      this.documentTextChunk('，请以原图内容为准。')
    }
    .width('100%')
  }

  @Builder
  private documentEnterpriseLine() {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      this.documentTextChunk('请先核对低置信字段，再保存为历史记录。', true)
    }
    .width('100%')
  }

  @Builder
  private documentDeliveryLine() {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      this.documentTextChunk('导出前请确认文本、页码和格式。', true)
    }
    .width('100%')
  }

  @Builder
  private segmentedTab(label: string, tab: OcrResultWorkspaceTab) {
    Button(label)
      .layoutWeight(1)
      .height(36)
      .type(ButtonType.Normal)
      .fontSize(AppTheme.FONT_CAPTION)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.resultTab === tab ? AppTheme.COLOR_TEXT : AppTheme.COLOR_TEXT_MUTED)
      .backgroundColor(this.resultTab === tab ? AppTheme.COLOR_SURFACE_DOCUMENT : AppTheme.COLOR_TRANSPARENT)
      .border({ width: this.resultTab === tab ? AppTheme.HAIRLINE : 0, color: this.resultTab === tab ? AppTheme.COLOR_LINE_SOFT : AppTheme.COLOR_TRANSPARENT })
      .borderRadius(AppTheme.RADIUS_CONTROL)
      .scale({ x: this.pressedTab === tab ? AppMotion.PRESS_SCALE : 1, y: this.pressedTab === tab ? AppMotion.PRESS_SCALE : 1 })
      .animation({ duration: AppMotion.DURATION_FAST, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => {
        // 分段标签切换采用 180ms 切换和轻按压反馈，贴近 HTML result tabs 的局部动效。
        if (event.type === TouchType.Down) {
          this.pressedTab = tab;
        }
        if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressedTab = '';
        }
      })
      .onClick(() => this.switchTab(tab))
  }

  @Builder
  private metaGridItem(label: string, value: string, highlight: boolean) {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(10)
        .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
        .width('100%')
      Text(value)
        .fontSize(AppTheme.FONT_META)
        .fontWeight(FontWeight.Bold)
        .fontColor(highlight ? AppTheme.COLOR_ACTION : AppTheme.COLOR_TEXT)
        .maxLines(1)
        .width('100%')
    }
    .width('100%')
    .padding(10)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_CONTROL)
  }

  @Builder
  private editorHint(left: string, right: string) {
    Row({ space: 8 }) {
      Text(left)
        .fontSize(11)
        .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
        .layoutWeight(1)
      Text(right)
        .fontSize(11)
        .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
    }
    .width('100%')
  }

  /**
   * PDF 页选择条只切换当前文本区展示内容，不记录页文本、不读取 PDF URI。
   */
  @Builder
  private pdfPageSelectorStrip() {
    if (this.pageSelectorVisible && this.pageSelectorOptions.length > 0) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.pageSelectorOptions, (label: string) => {
            Button(label)
              .height(34)
              .type(ButtonType.Normal)
              .fontSize(AppTheme.FONT_CAPTION)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.pageSelectorOptionIndex(label) === this.selectedPageOptionIndex ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_TEXT)
              .backgroundColor(this.pageSelectorOptionIndex(label) === this.selectedPageOptionIndex ? AppTheme.COLOR_BRAND : AppTheme.COLOR_SURFACE_SOFT)
              .border({
                width: AppTheme.HAIRLINE,
                color: this.pageSelectorOptionIndex(label) === this.selectedPageOptionIndex ? AppTheme.COLOR_BRAND_DARK : AppTheme.COLOR_LINE_SOFT
              })
              .borderRadius(AppTheme.RADIUS_CONTROL)
              .padding({ left: 12, right: 12 })
              .onClick(() => this.onPageSelectorChange(this.pageSelectorOptionIndex(label)))
          }, (label: string) => label)
        }
        .padding({ left: 2, right: 2 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    }
  }

  @Builder
  private imagePreviewPanel() {
    Column({ space: 10 }) {
      Column() {
        if (this.previewAvailable && this.imageUri.length > 0) {
          Image(this.imageUri)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
        } else {
          Column({ space: 8 }) {
            Text(this.previewFallback)
              .fontSize(AppTheme.FONT_BODY)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.COLOR_TEXT)
              .textAlign(TextAlign.Center)
            Text(this.previewKind === 'pdf' ? 'PDF 页面没有可用缩略图' : '当前结果没有可用图片 URI')
              .fontSize(AppTheme.FONT_META)
              .fontColor(AppTheme.COLOR_TEXT_MUTED)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding(18)
        }
      }
      .width('100%')
      .height(286)
      .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(10)

      this.editorHint(this.imageHint, this.imageMeta)
    }
    .width('100%')
  }

  @Builder
  private textEditorPanel() {
    Column({ space: 9 }) {
      this.pdfPageSelectorStrip()
      if (this.shouldUseReferenceDocumentView()) {
        Column({ space: 26 }) {
          Column({ space: 0 }) {
            // 示例文本按参考图阅读行拆分，避免 ArkUI Flex 在高亮块后产生标点孤行。
            this.documentTextLine()
            this.documentEnterpriseLine()
            this.documentDeliveryLine()
            Text('导出前校验。')
              .fontSize(15)
              .fontWeight(FontWeight.Regular)
              .fontColor(AppTheme.COLOR_TEXT)
              .lineHeight(24)
              .width(286)
          }
          .width('100%')

          Row() {
            // 英文示例段落收窄但保持左对齐，贴近 HTML 参考图的四行阅读节奏。
            Text('当前页面不展示任何预置整理内容。')
              .fontSize(15)
              .fontWeight(FontWeight.Regular)
              .fontColor(AppTheme.COLOR_TEXT)
              .lineHeight(24)
              .width(286)
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
        }
        .width('100%')
        .height(292)
        .padding({ left: 14, right: 12, top: 17, bottom: 14 })
        .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
        .borderRadius(AppTheme.RADIUS_DOCUMENT)
      } else {
        TextArea({ placeholder: '暂无识别文本', text: this.editedText })
          .width('100%')
          .height(286)
          .fontSize(AppTheme.FONT_BODY)
          .lineHeight(24)
          .fontColor(AppTheme.COLOR_TEXT)
          .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
          .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
          .borderRadius(AppTheme.RADIUS_DOCUMENT)
          .padding(14)
          .onChange((value: string) => this.onTextChange(value))
      }
      this.editorHint(this.textHintLeft, this.textHintRight)
    }
    .width('100%')
  }

  @Builder
  private aiDraftPanel() {
    Column({ space: 8 }) {
      if (this.hasAiDraftResult()) {
        Text(this.aiTitle)
          .fontSize(AppTheme.FONT_BODY)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .width('100%')
        Text(this.visibleAiDraftText())
          .fontSize(AppTheme.FONT_META)
          .fontColor(AppTheme.COLOR_TEXT_MUTED)
          .lineHeight(21)
          .width('100%')
          .layoutWeight(1)
        this.editorHint('AI Draft 可复制或写回备注', '已关联原文证据')
      } else {
        Text('尚未生成 AI 整理结果')
          .fontSize(AppTheme.FONT_BODY)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .width('100%')
        Text('请先保存为历史记录，再进入 AI 工作台执行整理。')
          .fontSize(AppTheme.FONT_META)
          .fontColor(AppTheme.COLOR_TEXT_MUTED)
          .lineHeight(21)
          .width('100%')
          .layoutWeight(1)
        this.editorHint('未展示伪造结果', '等待真实 AI 输出')
      }
    }
    .width('100%')
    .height(286)
    .padding(14)
    .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_DOCUMENT)
  }

  @Builder
  private resultActionButton(label: string, primary: boolean, enabled: boolean, onTap: () => void) {
    Button(label)
      .width('100%')
      .height(44)
      .type(ButtonType.Normal)
      .fontSize(AppTheme.FONT_BUTTON)
      .fontWeight(FontWeight.Bold)
      .fontColor(primary ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_TEXT)
      .backgroundColor(primary ? AppTheme.COLOR_BRAND : AppTheme.COLOR_SURFACE_SOFT)
      .border({ width: AppTheme.HAIRLINE, color: primary ? AppTheme.COLOR_BRAND_DARK : AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_CONTROL)
      .enabled(enabled)
      .opacity(enabled ? 1 : 0.48)
      .scale({ x: this.pressedAction === label ? AppMotion.PRESS_SCALE : 1, y: this.pressedAction === label ? AppMotion.PRESS_SCALE : 1 })
      .animation({ duration: AppMotion.DURATION_FAST, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => {
        // 结果页主操作保留明确按钮层级，同时补齐原型要求的 0.96-0.98 press scale。
        if (event.type === TouchType.Down) {
          this.pressedAction = label;
        }
        if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressedAction = '';
        }
      })
      .onClick(() => {
        if (enabled) {
          onTap();
        }
      })
  }

  /**
   * 文档级 AI 动作固定沉淀在结果工作台内，确保结果页和历史详情页使用同一套操作入口。
   */
  @Builder
  private documentActionStrip() {
    Scroll() {
      Row({ space: 8 }) {
        HtmlToolChip({ label: '摘要', primary: true, onTap: () => this.onAiSummarize() })
        HtmlToolChip({ label: '纠错', onTap: () => this.onAiProofread() })
        HtmlToolChip({ label: '翻译', onTap: () => this.onAiTranslate() })
        HtmlToolChip({ label: '字段提取', onTap: () => this.onAiExtractFields() })
        HtmlToolChip({ label: '智能排版', onTap: () => this.onAiFormat() })
        HtmlToolChip({ label: '转 Markdown', onTap: () => this.onMarkdown() })
      }
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
  }

  @Builder
  private lowConfidenceBlock() {
    Column({ space: 8 }) {
      Text(this.lowConfidenceTitle)
        .fontSize(AppTheme.FONT_META)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT)
        .width('100%')
      Text(this.lowConfidenceDescription)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(18)
        .width('100%')
      Row({ space: 8 }) {
        HtmlToolChip({ label: '逐项确认', onTap: () => this.onConfirmLowConfidence() })
        HtmlToolChip({ label: 'AI 纠错', onTap: () => this.onAiProofread() })
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(AppTheme.COLOR_WARNING_BG)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_WARNING_LINE })
    .borderRadius({ topLeft: 0, topRight: AppTheme.RADIUS_PANEL, bottomRight: AppTheme.RADIUS_PANEL, bottomLeft: 0 })
    .borderWidth({ left: 3, right: AppTheme.HAIRLINE, top: AppTheme.HAIRLINE, bottom: AppTheme.HAIRLINE })
    .borderColor({ left: AppTheme.COLOR_WARNING, right: AppTheme.COLOR_WARNING_LINE, top: AppTheme.COLOR_WARNING_LINE, bottom: AppTheme.COLOR_WARNING_LINE })
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 4 }) {
        this.segmentedTab('原图', 'image')
        this.segmentedTab('文本', 'text')
        this.segmentedTab('AI 结果', 'ai')
      }
      .width('100%')
      .padding(4)
      .backgroundColor(AppTheme.COLOR_SURFACE_SOFT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(16)
      .opacity(this.tabsEntered ? 1 : 0)
      .translate({ y: this.tabsEntered ? 0 : AppMotion.ENTER_OFFSET_Y })

      GridRow({ columns: 2, gutter: { x: 8, y: 8 } }) {
        GridCol({ span: 1 }) {
          this.metaGridItem('识别引擎', this.engineLabel, false)
        }
        GridCol({ span: 1 }) {
          this.metaGridItem('耗时', this.durationLabel, false)
        }
        GridCol({ span: 1 }) {
          this.metaGridItem('语言', this.languageLabel, false)
        }
        GridCol({ span: 1 }) {
          this.metaGridItem('置信度', this.confidenceLabel, true)
        }
      }
      .width('100%')
      .opacity(this.metaEntered ? 1 : 0)
      .translate({ y: this.metaEntered ? 0 : AppMotion.ENTER_OFFSET_Y })

      Column({ space: 9 }) {
        if (this.resultTab === 'image') {
          this.imagePreviewPanel()
        } else if (this.resultTab === 'ai') {
          this.aiDraftPanel()
        } else {
          this.textEditorPanel()
        }
      }
      .width('100%')
      // 结果卡片按 HTML `.result-view` 的 326px 最小高度补足底部节奏，避免低置信区域过早进入首屏。
      .padding({ left: 14, right: 14, top: 14, bottom: 16 })
      .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_PANEL)
      .constraintSize({ minHeight: 326 })
      .opacity(this.panelEntered ? 1 : 0)
      .translate({ y: this.panelEntered ? 0 : AppMotion.ENTER_OFFSET_Y })

      GridRow({ columns: 2, gutter: { x: 10, y: 10 } }) {
        GridCol({ span: 1 }) {
          this.resultActionButton('AI 整理', false, this.aiEnabled, () => {
            this.onAiOrganize();
          })
        }
        GridCol({ span: 1 }) {
          this.resultActionButton('导出', true, this.exportEnabled, () => this.onExport())
        }
      }
      .width('100%')
      .opacity(this.actionsEntered ? 1 : 0)
      .translate({ y: this.actionsEntered ? 0 : AppMotion.ENTER_OFFSET_Y })

      Column() {
        this.lowConfidenceBlock()
      }
      .width('100%')
      .opacity(this.lowConfidenceEntered ? 1 : 0)
      .translate({ y: this.lowConfidenceEntered ? 0 : AppMotion.ENTER_OFFSET_Y })

      if (this.showDocumentTools) {
        Column() {
          this.documentActionStrip()
        }
        .width('100%')
        .opacity(this.toolsEntered ? 1 : 0)
        .translate({ y: this.toolsEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
      }
    }
    .width('100%')
  }
}
