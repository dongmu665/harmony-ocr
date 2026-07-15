import { useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode } from "react";
import {
  Activity,
  AlertTriangle,
  BadgeCheck,
  BarChart3,
  BookOpenCheck,
  Check,
  ChevronRight,
  ClipboardList,
  Clock3,
  Copy,
  Database,
  FileText,
  Gauge,
  History,
  KeyRound,
  Layers3,
  Loader2,
  LockKeyhole,
  LogOut,
  MessageSquareWarning,
  RefreshCw,
  Search,
  ShieldCheck,
  SlidersHorizontal,
  Sparkles,
  TicketCheck,
  UserCog,
  Users,
  X
} from "lucide-react";
import {
  api,
  clearSessionTokens,
  pageItems,
  pageTotal,
  sessionValue,
  setSessionTokens
} from "./services/api";
import type {
  ActivationCode,
  AdminUser,
  AuditLog,
  ConfirmState,
  FeedbackRow,
  ModuleKey,
  RecordRow,
  SessionUser,
  ToastMessage,
  UsageSummary
} from "./types";
import {
  animateElement,
  animateScoped,
  cancelAnimations,
  observeReducedMotion,
  prefersReducedMotion
} from "./motion";

const MODULES: Array<{
  id: ModuleKey;
  title: string;
  crumb: string;
  icon: ReactNode;
}> = [
  { id: "overview", title: "概览", crumb: "运营数据总览", icon: <BarChart3 /> },
  { id: "users", title: "用户管理", crumb: "账号、状态与会员等级", icon: <Users /> },
  { id: "quota", title: "会员额度", crumb: "手工调整与课程开通", icon: <Gauge /> },
  { id: "codes", title: "激活码", crumb: "一次性 PRO / TEAM 权益", icon: <TicketCheck /> },
  { id: "records", title: "OCR 记录", crumb: "脱敏识别记录元数据", icon: <FileText /> },
  { id: "feedback", title: "反馈", crumb: "问题处理与状态流转", icon: <MessageSquareWarning /> },
  { id: "audit", title: "审计日志", crumb: "管理员操作留痕", icon: <ClipboardList /> },
  { id: "account", title: "账号设置", crumb: "当前管理员资料与安全", icon: <UserCog /> }
];

const LEVELS = ["FREE", "PRO", "TEAM"];
const USER_STATUS = ["ACTIVE", "DISABLED", "DELETED"];
const CODE_STATUS = ["UNUSED", "REDEEMED", "REVOKED", "EXPIRED"];
const RECORD_SOURCES = ["CAMERA", "ALBUM", "PDF", "BATCH"];
const FEEDBACK_TYPES = ["BUG", "FEATURE", "OTHER"];
const FEEDBACK_STATUS = ["PENDING", "PROCESSING", "RESOLVED", "CLOSED"];
const AUDIT_ACTIONS = [
  "ADMIN_UPDATE_MEMBERSHIP",
  "ADMIN_CREATE_MANUAL_ORDER",
  "ADMIN_CREATE_ACTIVATION_CODE",
  "ADMIN_REVOKE_ACTIVATION_CODE",
  "ADMIN_UPDATE_FEEDBACK_STATUS"
];

function nf(value?: number | string | null): string {
  const n = Number(value ?? 0);
  if (!Number.isFinite(n)) return "0";
  return new Intl.NumberFormat("zh-CN").format(n);
}

function compactDate(value?: string): string {
  if (!value) return "-";
  return value.replace("T", " ").replace(/\.\d+$/, "");
}

function labelFor(value?: string): string {
  const map: Record<string, string> = {
    ACTIVE: "正常",
    DISABLED: "停用",
    DELETED: "已删除",
    FREE: "FREE",
    PRO: "PRO",
    TEAM: "TEAM",
    UNUSED: "未使用",
    REDEEMED: "已兑换",
    REVOKED: "已撤销",
    EXPIRED: "已过期",
    CAMERA: "拍照",
    ALBUM: "相册",
    PDF: "PDF",
    BATCH: "批量",
    BUG: "缺陷",
    FEATURE: "建议",
    OTHER: "其他",
    PENDING: "待处理",
    OPEN: "待处理",
    PROCESSING: "处理中",
    IN_PROGRESS: "处理中",
    RESOLVED: "已解决",
    CLOSED: "已关闭",
    ADMIN_UPDATE_MEMBERSHIP: "调整会员额度",
    ADMIN_CREATE_MANUAL_ORDER: "手工开通会员",
    ADMIN_CREATE_ACTIVATION_CODE: "生成激活码",
    ADMIN_REVOKE_ACTIVATION_CODE: "撤销激活码",
    ADMIN_UPDATE_FEEDBACK_STATUS: "更新反馈状态"
  };
  return value ? map[value] || value : "-";
}

function defaultExpiryValue(): string {
  const date = new Date();
  date.setDate(date.getDate() + 7);
  date.setMinutes(date.getMinutes() - date.getTimezoneOffset());
  return date.toISOString().slice(0, 16);
}

function useReducedMotion(): boolean {
  const [reduced, setReduced] = useState(prefersReducedMotion);
  useEffect(() => observeReducedMotion(setReduced), []);
  return reduced;
}

function useReveal(scope: React.RefObject<HTMLElement>, deps: unknown[] = []) {
  const reducedMotion = useReducedMotion();
  useLayoutEffect(() => {
    const root = scope.current;
    if (!root || reducedMotion) return;
    const animations = [
      ...animateScoped(
        root,
        ".motion-section",
        [{ opacity: 0, transform: "translateY(10px)" }, { opacity: 1, transform: "translateY(0)" }],
        { duration: 300, easing: "cubic-bezier(0.22, 1, 0.36, 1)" },
        40
      ),
      ...animateScoped(
        root,
        ".data-row",
        [{ opacity: 0, transform: "translateY(6px)" }, { opacity: 1, transform: "translateY(0)" }],
        { duration: 180, delay: 40, easing: "cubic-bezier(0.2, 0.7, 0.2, 1)" },
        14
      )
    ];
    return () => cancelAnimations(animations);
  }, [scope, reducedMotion, ...deps]);
}

function useAsyncData<T>(loader: () => Promise<T>, deps: unknown[]) {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string>("");
  const [data, setData] = useState<T | null>(null);

  useEffect(() => {
    let active = true;
    setLoading(true);
    setError("");
    loader()
      .then((value) => {
        if (active) setData(value);
      })
      .catch((err) => {
        if (active) setError(err?.message || "加载失败");
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, deps);

  return { loading, error, data };
}

function IconWrap({ children, tone = "neutral" }: { children: ReactNode; tone?: string }) {
  return <span className={`icon-wrap ${tone}`}>{children}</span>;
}

// KPI value that counts up from 0 to the target once data lands.
function CountUp({ value, loading }: { value?: number | string | null; loading: boolean }) {
  const ref = useRef<HTMLElement>(null);
  const target = Number(value ?? 0);
  const reducedMotion = useReducedMotion();
  useLayoutEffect(() => {
    if (loading) return;
    const node = ref.current;
    if (!node) return;
    const safe = Number.isFinite(target) ? target : 0;
    if (reducedMotion) {
      node.textContent = nf(safe);
      return;
    }

    let frame = 0;
    const startedAt = performance.now();
    const tick = (now: number) => {
      const progress = Math.min((now - startedAt) / 900, 1);
      const eased = 1 - (1 - progress) * (1 - progress);
      node.textContent = nf(Math.round(safe * eased));
      if (progress < 1) frame = window.requestAnimationFrame(tick);
    };
    node.textContent = nf(0);
    frame = window.requestAnimationFrame(tick);
    return () => window.cancelAnimationFrame(frame);
  }, [target, loading, reducedMotion]);
  return <strong ref={ref}>{loading ? "…" : nf(target)}</strong>;
}

function StatusBadge({ value }: { value?: string }) {
  const v = value || "";
  let tone = "neutral";
  if (["ACTIVE", "UNUSED", "RESOLVED", "PRO", "TEAM"].includes(v)) tone = "success";
  if (["PENDING", "PROCESSING", "OPEN", "IN_PROGRESS", "EXPIRED"].includes(v)) tone = "warn";
  if (["DISABLED", "DELETED", "REVOKED", "CLOSED"].includes(v)) tone = "danger";
  if (v === "FREE") tone = "info";
  return <span className={`badge ${tone}`}>{labelFor(v)}</span>;
}

function PageIntro({
  eyebrow,
  title,
  body,
  icon,
  action
}: {
  eyebrow: string;
  title: string;
  body: string;
  icon?: ReactNode;
  action?: ReactNode;
}) {
  return (
    <div className="page-intro motion-section">
      {icon ? <span className="page-intro-mark">{icon}</span> : null}
      <div className="page-intro-copy">
        <span className="eyebrow">{eyebrow}</span>
        <h2>{title}</h2>
        <p>{body}</p>
      </div>
      {action ? <div className="intro-action">{action}</div> : null}
    </div>
  );
}

function Panel({
  title,
  subtitle,
  children,
  action,
  className = ""
}: {
  title: string;
  subtitle?: ReactNode;
  children: ReactNode;
  action?: ReactNode;
  className?: string;
}) {
  return (
    <section className={`panel motion-section ${className}`}>
      <div className="panel-head">
        <div>
          <h3>{title}</h3>
          {subtitle ? <p>{subtitle}</p> : null}
        </div>
        {action}
      </div>
      {children}
    </section>
  );
}

function LoadingRows({ columns = 5, rows = 5 }: { columns?: number; rows?: number }) {
  return (
    <>
      {Array.from({ length: rows }).map((_, row) => (
        <tr key={row}>
          {Array.from({ length: columns }).map((__, col) => (
            <td key={col}>
              <span className="skeleton" style={{ width: `${col === 0 ? 42 : 58 + col * 7}%` }} />
            </td>
          ))}
        </tr>
      ))}
    </>
  );
}

function StateBlock({
  type,
  title,
  body,
  action
}: {
  type: "empty" | "error" | "loading";
  title: string;
  body?: string;
  action?: ReactNode;
}) {
  const icon = type === "error" ? <AlertTriangle /> : type === "loading" ? <Loader2 className="spin" /> : <Database />;
  return (
    <div className={`state-block ${type}`}>
      <span>{icon}</span>
      <h4>{title}</h4>
      {body ? <p>{body}</p> : null}
      {action}
    </div>
  );
}

function BrandMark() {
  return (
    <span className="brand-mark" aria-hidden="true">
      <FileText />
      <Sparkles className="spark" />
    </span>
  );
}

function InteractiveOcrBackdrop({ variant = "login" }: { variant?: "login" | "console" }) {
  const ref = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const nodes = variant === "login" ? 12 : 8;
  const reducedMotion = useReducedMotion();

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas || reducedMotion) return;

    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    type Dot = {
      x: number;
      y: number;
      vx: number;
      vy: number;
      size: number;
      phase: number;
    };

    let width = 1;
    let height = 1;
    let dpr = 1;
    let frame = 0;
    let dots: Dot[] = [];
    const mouse = { x: 0, y: 0, tx: 0, ty: 0, active: false };
    const intensity = variant === "login" ? 1 : 0.42;
    const colors = {
      ink: [31, 29, 26],
      brand: [201, 100, 66],
      olive: [95, 115, 70],
      info: [47, 99, 146]
    };
    const rgba = (rgb: number[], alpha: number) => `rgba(${rgb[0]}, ${rgb[1]}, ${rgb[2]}, ${alpha})`;

    const seedDots = () => {
      const count = variant === "login" ? 82 : 44;
      dots = Array.from({ length: count }, (_, index) => ({
        x: ((index * 137.5) % Math.max(width, 1)) + Math.sin(index) * 24,
        y: ((index * 89.3) % Math.max(height, 1)) + Math.cos(index) * 18,
        vx: (Math.sin(index * 1.7) * 0.18 + 0.08) * intensity,
        vy: (Math.cos(index * 1.1) * 0.14 + 0.05) * intensity,
        size: 1.1 + (index % 4) * 0.42,
        phase: index * 0.37
      }));
    };

    const resize = () => {
      const rect = canvas.getBoundingClientRect();
      dpr = Math.min(window.devicePixelRatio || 1, 2);
      width = Math.max(1, rect.width);
      height = Math.max(1, rect.height);
      canvas.width = Math.floor(width * dpr);
      canvas.height = Math.floor(height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      mouse.x = mouse.tx = width * 0.64;
      mouse.y = mouse.ty = height * 0.42;
      seedDots();
    };

    const onPointerMove = (event: PointerEvent) => {
      const rect = canvas.getBoundingClientRect();
      mouse.tx = event.clientX - rect.left;
      mouse.ty = event.clientY - rect.top;
      mouse.active = true;
    };

    const drawPerspectiveGrid = (time: number) => {
      const vanishingX = width * 0.58 + Math.sin(time * 0.35) * width * 0.04;
      const vanishingY = height * 0.2;
      ctx.save();
      ctx.globalAlpha = 0.38 * intensity;
      ctx.lineWidth = 1;
      for (let i = 0; i < 17; i += 1) {
        const x = (i / 16) * width;
        ctx.strokeStyle = rgba(i % 3 === 0 ? colors.brand : colors.ink, i % 3 === 0 ? 0.08 : 0.04);
        ctx.beginPath();
        ctx.moveTo(x, height + 40);
        ctx.lineTo(vanishingX, vanishingY);
        ctx.stroke();
      }
      for (let j = 0; j < 14; j += 1) {
        const y = height * (0.32 + j * 0.058) + Math.sin(time * 0.5 + j) * 3;
        ctx.strokeStyle = rgba(j % 4 === 0 ? colors.olive : colors.ink, j % 4 === 0 ? 0.1 : 0.045);
        ctx.beginPath();
        ctx.moveTo(width * -0.08, y);
        ctx.quadraticCurveTo(width * 0.5, y - 18, width * 1.08, y + 4);
        ctx.stroke();
      }
      ctx.restore();
    };

    const drawScanRibbon = (time: number) => {
      const y = ((time * (variant === "login" ? 82 : 34)) % (height + 280)) - 140;
      const gradient = ctx.createLinearGradient(0, y - 70, 0, y + 130);
      gradient.addColorStop(0, "rgba(255,255,255,0)");
      gradient.addColorStop(0.42, rgba(colors.brand, 0.16 * intensity));
      gradient.addColorStop(0.52, "rgba(255,255,255,0.34)");
      gradient.addColorStop(0.68, rgba(colors.olive, 0.09 * intensity));
      gradient.addColorStop(1, "rgba(255,255,255,0)");
      ctx.save();
      ctx.translate(width * 0.5, y);
      ctx.rotate(-0.1);
      ctx.fillStyle = gradient;
      ctx.fillRect(-width * 0.62, -70, width * 1.24, 190);
      ctx.restore();
    };

    const drawNetwork = (time: number) => {
      mouse.x += (mouse.tx - mouse.x) * 0.055;
      mouse.y += (mouse.ty - mouse.y) * 0.055;
      dots.forEach((dot, index) => {
        dot.x += dot.vx + Math.sin(time * 0.7 + dot.phase) * 0.04;
        dot.y += dot.vy + Math.cos(time * 0.6 + dot.phase) * 0.035;
        if (dot.x > width + 24) dot.x = -24;
        if (dot.x < -24) dot.x = width + 24;
        if (dot.y > height + 24) dot.y = -24;
        if (dot.y < -24) dot.y = height + 24;

        for (let next = index + 1; next < dots.length; next += 1) {
          const other = dots[next];
          const dx = dot.x - other.x;
          const dy = dot.y - other.y;
          const distance = Math.sqrt(dx * dx + dy * dy);
          const limit = variant === "login" ? 112 : 82;
          if (distance < limit) {
            const alpha = (1 - distance / limit) * 0.13 * intensity;
            ctx.strokeStyle = rgba(index % 5 === 0 ? colors.brand : colors.ink, alpha);
            ctx.lineWidth = 0.7;
            ctx.beginPath();
            ctx.moveTo(dot.x, dot.y);
            ctx.lineTo(other.x, other.y);
            ctx.stroke();
          }
        }

        const mdx = dot.x - mouse.x;
        const mdy = dot.y - mouse.y;
        const mouseDistance = Math.sqrt(mdx * mdx + mdy * mdy);
        if (mouse.active && mouseDistance < 210) {
          const alpha = (1 - mouseDistance / 210) * 0.32 * intensity;
          ctx.strokeStyle = rgba(colors.brand, alpha);
          ctx.lineWidth = 1;
          ctx.beginPath();
          ctx.moveTo(dot.x, dot.y);
          ctx.lineTo(mouse.x, mouse.y);
          ctx.stroke();
        }

        ctx.fillStyle = rgba(index % 4 === 0 ? colors.brand : index % 4 === 1 ? colors.olive : colors.info, 0.42 * intensity);
        ctx.beginPath();
        ctx.rect(dot.x - dot.size / 2, dot.y - dot.size / 2, dot.size, dot.size);
        ctx.fill();
      });
    };

    const draw = () => {
      const time = performance.now() / 1000;
      ctx.clearRect(0, 0, width, height);
      drawPerspectiveGrid(time);
      drawNetwork(time);
      drawScanRibbon(time);
      frame = window.requestAnimationFrame(draw);
    };

    resize();
    draw();
    const observer = new ResizeObserver(resize);
    observer.observe(canvas);
    window.addEventListener("pointermove", onPointerMove, { passive: true });
    return () => {
      window.cancelAnimationFrame(frame);
      observer.disconnect();
      window.removeEventListener("pointermove", onPointerMove);
    };
  }, [variant, reducedMotion]);

  useLayoutEffect(() => {
    const root = ref.current;
    if (!root) return;

    const revealGroups = [
      { selector: ".ocr-node", opacity: variant === "login" ? 0.88 : 0.42, duration: 700, stagger: 35 },
      { selector: ".ocr-holo-card", opacity: variant === "login" ? 0.86 : 0.36, duration: 900, stagger: 110 },
      { selector: ".ocr-glass-panel, .ocr-prism-sheet", opacity: variant === "login" ? 0.92 : 0.34, duration: 1100, stagger: 60 },
      { selector: ".ocr-depth-ring", opacity: variant === "login" ? 0.48 : 0.2, duration: 1100, stagger: 80 }
    ];
    revealGroups.forEach(({ selector, opacity }) => {
      root.querySelectorAll<HTMLElement>(selector).forEach((element) => {
        element.style.opacity = String(opacity);
      });
    });
    if (reducedMotion) return;

    const animations = revealGroups.flatMap(({ selector, opacity, duration, stagger }) =>
      animateScoped(
        root,
        selector,
        [{ opacity: 0 }, { opacity }],
        { duration, easing: "cubic-bezier(0.22, 1, 0.36, 1)" },
        stagger
      )
    );
    const cursor = root.querySelector<HTMLElement>(".ocr-cursor");
    const focus = root.querySelector<HTMLElement>(".ocr-focus");
    const scanPlane = root.querySelector<HTMLElement>(".ocr-scan-plane");
    const glassRig = root.querySelector<HTMLElement>(".ocr-glass-rig");
    const parallax = Array.from(root.querySelectorAll<HTMLElement>(".ocr-parallax"));
    const target = { x: 0, y: 0 };
    const current = { x: 0, y: 0 };
    let frame = 0;

    // pointermove 只更新目标值；单一 RAF 负责平滑插值，避免每个元素各自创建动画。
    const renderParallax = () => {
      frame = 0;
      current.x += (target.x - current.x) * 0.14;
      current.y += (target.y - current.y) * 0.14;
      cursor?.style.setProperty("translate", `${current.x * 64}px ${current.y * 44}px`);
      focus?.style.setProperty("translate", `${current.x * 104}px ${current.y * 72}px`);
      scanPlane?.style.setProperty("--ocr-tilt-y", `${current.x * (variant === "login" ? 9 : 4)}deg`);
      glassRig?.style.setProperty("--ocr-tilt-y", `${current.x * (variant === "login" ? 22 : 8)}deg`);
      glassRig?.style.setProperty("--ocr-tilt-x", `${-current.y * (variant === "login" ? 12 : 4)}deg`);
      parallax.forEach((layer, index) => {
        const depth = variant === "login" ? (index + 1) * 18 : (index + 1) * 6;
        layer.style.translate = `${current.x * depth}px ${current.y * depth * 0.7}px`;
      });
      if (Math.abs(target.x - current.x) > 0.001 || Math.abs(target.y - current.y) > 0.001) {
        frame = window.requestAnimationFrame(renderParallax);
      }
    };
    const onPointerMove = (event: PointerEvent) => {
      const rect = root.getBoundingClientRect();
      if (!rect.width || !rect.height) return;
      target.x = (event.clientX - rect.left) / rect.width - 0.5;
      target.y = (event.clientY - rect.top) / rect.height - 0.5;
      if (!frame) frame = window.requestAnimationFrame(renderParallax);
    };

    window.addEventListener("pointermove", onPointerMove, { passive: true });
    return () => {
      cancelAnimations(animations);
      if (frame) window.cancelAnimationFrame(frame);
      window.removeEventListener("pointermove", onPointerMove);
      cursor?.style.removeProperty("translate");
      focus?.style.removeProperty("translate");
      scanPlane?.style.removeProperty("--ocr-tilt-y");
      glassRig?.style.removeProperty("--ocr-tilt-x");
      glassRig?.style.removeProperty("--ocr-tilt-y");
      parallax.forEach((layer) => layer.style.removeProperty("translate"));
    };
  }, [variant, reducedMotion]);

  return (
    <div ref={ref} className={`ocr-backdrop ${variant}`} aria-hidden="true">
      <canvas ref={canvasRef} className="ocr-canvas" />
      <div className="ocr-focus ocr-animated" />
      <div className="ocr-cursor ocr-animated" />
      <div className="ocr-layer ocr-cinema-vignette" />
      <div className="ocr-parallax ocr-layer ocr-grid-layer" />
      <div className="ocr-parallax ocr-layer ocr-cinematic-scene">
        <div className="ocr-glass-rig ocr-animated">
          <span className="ocr-light-sheet s1 ocr-animated" />
          <span className="ocr-light-sheet s2 ocr-animated" />
          <span className="ocr-depth-ring r1 ocr-animated" />
          <span className="ocr-depth-ring r2 ocr-animated" />
          <span className="ocr-depth-ring r3 ocr-animated" />
          <div className="ocr-prism-core">
            <span className="ocr-prism-sheet sheet-a ocr-animated" />
            <span className="ocr-prism-sheet sheet-b ocr-animated" />
            <span className="ocr-prism-sheet sheet-c ocr-animated" />
          </div>
          {["upload", "recognize", "verify", "audit"].map((label, index) => (
            <span className={`ocr-glass-panel p${index + 1} ocr-animated`} key={label}>
              <i className="ocr-liquid-sheen" />
              <b>{label}</b>
              <em />
              <em />
              <em />
            </span>
          ))}
        </div>
      </div>
      <div className="ocr-parallax ocr-layer ocr-holo-stack">
        {["OCR INPUT", "TEXT MAP", "AUDIT TRAIL", "TOKEN SAFE"].map((label, index) => (
          <span className={`ocr-holo-card c${index + 1} ocr-animated`} key={label}>
            <em />
            <i />
            <b>{label}</b>
          </span>
        ))}
      </div>
      <div className="ocr-parallax ocr-layer ocr-scan-plane ocr-animated">
        <span className="ocr-scan-beam ocr-animated" />
        <span className="ocr-scan-beam secondary ocr-animated" />
      </div>
      <div className="ocr-layer ocr-horizon">
        <span className="ocr-horizon-line" />
        <span className="ocr-horizon-line" />
        <span className="ocr-horizon-line" />
      </div>
      <div className="ocr-parallax ocr-layer ocr-streams">
        <span className="ocr-stream ocr-animated">OCR · HASH · LOG · ADMIN · OCR · HASH · LOG · ADMIN</span>
        <span className="ocr-stream ocr-animated">SCAN · TEXT · QUOTA · AUDIT · SCAN · TEXT · QUOTA · AUDIT</span>
        <span className="ocr-stream ocr-animated">DOC · USER · CODE · SAFE · DOC · USER · CODE · SAFE</span>
      </div>
      <div className="ocr-parallax ocr-layer ocr-nodes">
        {Array.from({ length: nodes }).map((_, index) => (
          <span className={`ocr-node n${index + 1} ocr-animated`} key={index}>
            <i />
            <b>{index % 3 === 0 ? "OCR" : index % 3 === 1 ? "ID" : "LOG"}</b>
          </span>
        ))}
      </div>
    </div>
  );
}

function ToastItem({ toast, onClose }: { toast: ToastMessage; onClose: () => void }) {
  const ref = useRef<HTMLDivElement>(null);
  const closingRef = useRef(false);
  const exitAnimationRef = useRef<Animation | null>(null);
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;
  const reducedMotion = useReducedMotion();
  useLayoutEffect(() => {
    if (reducedMotion) return;
    const animation = animateElement(
      ref.current,
      [
        { opacity: 0, transform: "translateX(22px) scale(0.98)" },
        { opacity: 1, transform: "translateX(0) scale(1)" }
      ],
      { duration: 280, easing: "cubic-bezier(0.2, 0.7, 0.2, 1)" }
    );
    return () => animation?.cancel();
  }, [reducedMotion]);
  useLayoutEffect(() => {
    if (!reducedMotion || !exitAnimationRef.current) return;
    exitAnimationRef.current.cancel();
    exitAnimationRef.current = null;
    onCloseRef.current();
  }, [reducedMotion]);
  useLayoutEffect(
    () => () => {
      exitAnimationRef.current?.cancel();
      exitAnimationRef.current = null;
    },
    []
  );
  const closeToast = () => {
    if (closingRef.current) return;
    closingRef.current = true;
    const animation = animateElement(
      ref.current,
      [
        { opacity: 1, transform: "translateX(0) scale(1)" },
        { opacity: 0, transform: "translateX(16px) scale(0.98)" }
      ],
      { duration: 160, easing: "ease-in", fill: "forwards" }
    );
    exitAnimationRef.current = animation;
    if (!animation || reducedMotion) {
      exitAnimationRef.current = null;
      onCloseRef.current();
      return;
    }
    void animation.finished.then(
      () => {
        if (exitAnimationRef.current !== animation) return;
        exitAnimationRef.current = null;
        onCloseRef.current();
      },
      () => undefined
    );
  };
  const Icon = toast.type === "success" ? Check : toast.type === "error" ? AlertTriangle : ShieldCheck;
  return (
    <div ref={ref} className={`toast ${toast.type}`}>
      <Icon />
      <div>
        <b>{toast.title}</b>
        {toast.body ? <span>{toast.body}</span> : null}
      </div>
      <button onClick={closeToast} aria-label="关闭提示">
        <X />
      </button>
    </div>
  );
}

function ConfirmModal({
  state,
  onCancel,
  onConfirm
}: {
  state: ConfirmState | null;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const confirmBtnRef = useRef<HTMLButtonElement>(null);
  const reducedMotion = useReducedMotion();
  useLayoutEffect(() => {
    if (!state || reducedMotion) return;
    const root = ref.current;
    const animations = [
      animateElement(root, [{ opacity: 0 }, { opacity: 1 }], { duration: 180, easing: "ease-out" }),
      animateElement(
        root?.querySelector(".confirm-card") ?? null,
        [{ transform: "translateY(16px) scale(0.98)" }, { transform: "translateY(0) scale(1)" }],
        { duration: 240, easing: "cubic-bezier(0.22, 1, 0.36, 1)" }
      )
    ].filter((animation): animation is Animation => animation !== null);
    return () => cancelAnimations(animations);
  }, [state, reducedMotion]);
  useEffect(() => {
    if (!state) return;
    const opener = document.activeElement as HTMLElement | null;
    confirmBtnRef.current?.focus();
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") onCancel();
    };
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("keydown", onKey);
      opener?.focus?.();
    };
  }, [state, onCancel]);
  if (!state) return null;
  const tone = state.tone || "danger";
  return (
    <div ref={ref} className="modal-layer">
      <button className="modal-scrim" aria-label="取消操作" onClick={onCancel} />
      <div className="confirm-card" role="dialog" aria-modal="true" aria-labelledby="confirm-title">
        <div className="confirm-head">
          <IconWrap tone={tone}>{tone === "danger" ? <AlertTriangle /> : <ShieldCheck />}</IconWrap>
          <div>
            <h3 id="confirm-title">{state.title}</h3>
            <p>请确认当前操作符合后台管理规范。</p>
          </div>
        </div>
        <div className="confirm-body">{state.body}</div>
        <div className="confirm-foot">
          <button className="btn ghost" onClick={onCancel}>
            取消
          </button>
          <button
            ref={confirmBtnRef}
            className={`btn ${tone === "danger" ? "danger" : "primary"}`}
            onClick={onConfirm}
          >
            {state.confirmText || "确认"}
          </button>
        </div>
      </div>
    </div>
  );
}

function Drawer({
  title,
  children,
  onClose
}: {
  title: string;
  children: ReactNode;
  onClose: () => void;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const closeRef = useRef<HTMLButtonElement>(null);
  const reducedMotion = useReducedMotion();
  useLayoutEffect(() => {
    if (reducedMotion) return;
    const root = ref.current;
    const animations = [
      animateElement(root, [{ opacity: 0 }, { opacity: 1 }], { duration: 180, easing: "ease-out" }),
      animateElement(
        root?.querySelector(".drawer-card") ?? null,
        [{ transform: "translateX(100%)" }, { transform: "translateX(0)" }],
        { duration: 300, easing: "cubic-bezier(0.22, 1, 0.36, 1)" }
      )
    ].filter((animation): animation is Animation => animation !== null);
    return () => cancelAnimations(animations);
  }, [reducedMotion]);
  useEffect(() => {
    const opener = document.activeElement as HTMLElement | null;
    closeRef.current?.focus();
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("keydown", onKey);
      opener?.focus?.();
    };
  }, [onClose]);
  return (
    <div ref={ref} className="drawer-layer">
      <button className="drawer-scrim" aria-label="关闭详情" onClick={onClose} />
      <aside className="drawer-card" role="dialog" aria-modal="true" aria-label={title}>
        <div className="drawer-head">
          <h3>{title}</h3>
          <button ref={closeRef} className="icon-btn" onClick={onClose} aria-label="关闭">
            <X />
          </button>
        </div>
        <div className="drawer-body">{children}</div>
      </aside>
    </div>
  );
}

function LoginScreen({
  onLogin,
  busy,
  error
}: {
  onLogin: (username: string, password: string) => Promise<void>;
  busy: boolean;
  error: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const reducedMotion = useReducedMotion();

  useLayoutEffect(() => {
    const root = ref.current;
    if (!root) return;
    const strokes = Array.from(root.querySelectorAll<SVGPathElement>(".doc-visual .stroke"));
    const dots = Array.from(root.querySelectorAll<SVGCircleElement>(".doc-visual .dot"));
    strokes.forEach((stroke) => {
      const length = stroke.getTotalLength();
      stroke.style.strokeDasharray = String(length);
      stroke.style.strokeDashoffset = "0";
    });
    dots.forEach((dot) => {
      dot.style.opacity = "0.85";
      dot.style.scale = "1";
    });
    if (reducedMotion) return;

    const animations = [
      ...animateScoped(
        root,
        ".login-shell",
        [{ opacity: 0, transform: "translateY(14px) scale(0.985)" }, { opacity: 1, transform: "translateY(0) scale(1)" }],
        { duration: 500, easing: "cubic-bezier(0.2, 0.7, 0.2, 1)" }
      ),
      ...animateScoped(
        root,
        ".brand-copy > *",
        [{ opacity: 0, transform: "translateY(10px)" }, { opacity: 1, transform: "translateY(0)" }],
        { duration: 340, delay: 220, easing: "cubic-bezier(0.22, 1, 0.36, 1)" },
        60
      ),
      ...animateScoped(
        root,
        ".login-form > *",
        [{ opacity: 0, transform: "translateY(9px)" }, { opacity: 1, transform: "translateY(0)" }],
        { duration: 320, delay: 160, easing: "cubic-bezier(0.22, 1, 0.36, 1)" },
        50
      ),
      ...strokes.flatMap((stroke, index) => {
        const length = stroke.getTotalLength();
        const animation = animateElement(
          stroke,
          [{ strokeDashoffset: length }, { strokeDashoffset: 0 }],
          { duration: 850, delay: 300 + index * 100, easing: "ease-in-out" }
        );
        return animation ? [animation] : [];
      }),
      ...dots.flatMap((dot, index) => {
        const animation = animateElement(
          dot,
          [{ opacity: 0, scale: 0 }, { opacity: 0.85, scale: 1 }],
          { duration: 400, delay: 820 + index * 120, easing: "cubic-bezier(0.34, 1.56, 0.64, 1)" }
        );
        return animation ? [animation] : [];
      })
    ];
    return () => cancelAnimations(animations);
  }, [reducedMotion]);

  const submit = async (event?: React.FormEvent) => {
    event?.preventDefault();
    await onLogin(username.trim(), password);
  };

  return (
    <main ref={ref} className="login-stage">
      <InteractiveOcrBackdrop variant="login" />
      <div className="login-shell">
        <section className="login-brand">
          <div className="brand-copy">
            <div className="brand-lockup">
              <BrandMark />
              <div>
                <b>Harmony OCR</b>
                <span>Admin Console</span>
              </div>
            </div>
            <span className="eyebrow">运营管理后台</span>
            <h1>
              让每一份文档，
              <br />
              都被稳妥地管理。
            </h1>
            <p>识别用量、会员额度、激活码与审计日志，都在这一处安静而可信的工作台里。</p>
            <div className="login-proof">
              <span>
                <Check /> 脱敏聚合数据，绝不展示正文与密钥
              </span>
              <span>
                <Check /> 写操作二次确认，全程留痕可审计
              </span>
              <span>
                <Check /> 仅限授权管理员访问
              </span>
            </div>
          </div>
          <svg className="doc-visual" viewBox="0 0 200 200" aria-hidden="true">
            <path
              className="stroke fill-soft"
              d="M56 44c0-5 4-9 9-9h52l30 30v82c0 5-4 9-9 9H65c-5 0-9-4-9-9V44Z"
            />
            <path className="stroke" d="M117 35v22c0 5 4 9 9 9h22" />
            <path className="stroke" d="M74 78h44" />
            <path className="stroke" d="M74 96h56" />
            <path className="stroke" d="M74 114h40" />
            <path className="stroke olive" d="M40 132c14 10 30 14 47 12" />
            <circle className="dot" cx="150" cy="150" r="4" />
            <circle className="dot" cx="46" cy="70" r="3" />
          </svg>
        </section>

        <section className="login-panel">
          <form className="login-form" onSubmit={submit}>
            <div className="login-head">
              <h2>管理员登录</h2>
              <p>请使用已授权的账号登录，系统随后校验 Admin 权限。</p>
            </div>
            {error ? (
              <div className="login-alert" role="alert">
                <AlertTriangle />
                <span>{error}</span>
              </div>
            ) : null}
            <label>
              <span>管理员账号</span>
              <input
                value={username}
                onChange={(event) => setUsername(event.target.value)}
                autoComplete="username"
                placeholder="输入用户名"
              />
            </label>
            <label>
              <span>管理员密码</span>
              <input
                value={password}
                onChange={(event) => setPassword(event.target.value)}
                autoComplete="current-password"
                type="password"
                placeholder="输入密码"
              />
            </label>
            <button className="btn primary large" disabled={busy} type="submit">
              {busy ? <Loader2 className="spin" /> : <ShieldCheck />}
              {busy ? "登录中" : "登录"}
            </button>
            <p className="session-note">凭证仅保存在当前浏览器会话中，退出登录会立即清理。</p>
          </form>
        </section>
      </div>
    </main>
  );
}

function Shell({
  user,
  active,
  setActive,
  onLogout,
  onRefresh,
  children
}: {
  user: SessionUser | null;
  active: ModuleKey;
  setActive: (module: ModuleKey) => void;
  onLogout: () => void;
  onRefresh: () => void;
  children: ReactNode;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const activeModule = MODULES.find((item) => item.id === active) || MODULES[0];
  const reducedMotion = useReducedMotion();
  useLayoutEffect(() => {
    if (reducedMotion) return;
    const root = ref.current;
    const animations = [
      animateElement(
        root?.querySelector(".rail") ?? null,
        [{ opacity: 0, transform: "translateX(-14px)" }, { opacity: 1, transform: "translateX(0)" }],
        { duration: 280, easing: "cubic-bezier(0.22, 1, 0.36, 1)" }
      ),
      animateElement(
        root?.querySelector(".topbar") ?? null,
        [{ opacity: 0, transform: "translateY(-8px)" }, { opacity: 1, transform: "translateY(0)" }],
        { duration: 240, delay: 60, easing: "cubic-bezier(0.2, 0.7, 0.2, 1)" }
      )
    ].filter((animation): animation is Animation => animation !== null);
    return () => cancelAnimations(animations);
  }, [reducedMotion]);
  const initials = (user?.nickname || user?.username || "AD")
    .replace(/[^a-zA-Z0-9\u4e00-\u9fa5]/g, "")
    .slice(0, 2)
    .toUpperCase();
  return (
    <div ref={ref} className="console-shell">
      <InteractiveOcrBackdrop variant="console" />
      <aside className="rail">
        <div className="rail-head">
          <BrandMark />
          <div>
            <b>Harmony OCR</b>
            <span>Admin Console</span>
          </div>
        </div>
        <nav className="nav-list" aria-label="后台模块">
          <span className="nav-label">管理模块</span>
          {MODULES.map((module) => (
            <button
              key={module.id}
              className={module.id === active ? "active" : ""}
              onClick={() => setActive(module.id)}
              aria-current={module.id === active ? "page" : undefined}
            >
              {module.icon}
              <span>{module.title}</span>
              <ChevronRight className="nav-chevron" />
            </button>
          ))}
        </nav>
        <button className="rail-logout" onClick={onLogout}>
          <LogOut />
          <span>退出登录</span>
        </button>
      </aside>
      <div className="workspace">
        <header className="topbar">
          <div className="topbar-crumb">
            <span className="crumb-root">Ops Workbench</span>
            <ChevronRight className="crumb-sep" />
            <span className="crumb-current">{activeModule.crumb}</span>
          </div>
          <div className="top-actions">
            <button className="icon-btn" onClick={onRefresh} title="刷新当前模块" aria-label="刷新当前模块">
              <RefreshCw />
            </button>
            <button className="user-pill" onClick={() => setActive("account")}>
              <span>{initials || "AD"}</span>
              <b>{user?.nickname || user?.username || "Admin"}</b>
            </button>
          </div>
        </header>
        <main className="content">{children}</main>
      </div>
    </div>
  );
}

function OverviewPage({ refreshKey }: { refreshKey: number }) {
  const ref = useRef<HTMLElement>(null);
  const summary = useAsyncData(() => api.usageSummary(), [refreshKey]);
  const audits = useAsyncData(() => api.auditLogs(), [refreshKey]);
  const auditRows = pageItems<AuditLog>(audits.data);
  useReveal(ref, [summary.loading, audits.loading, refreshKey]);
  const reducedMotion = useReducedMotion();

  useLayoutEffect(() => {
    if (summary.loading || reducedMotion) return;
    const root = ref.current;
    if (!root) return;
    const animations = Array.from(root.querySelectorAll<HTMLElement>(".usage-item i")).flatMap((bar) => {
      const target = Number(bar.dataset.scale ?? 0);
      const animation = animateElement(
        bar,
        [{ transform: "scaleX(0)" }, { transform: `scaleX(${target})` }],
        { duration: 700, delay: 100, easing: "cubic-bezier(0.22, 1, 0.36, 1)" }
      );
      return animation ? [animation] : [];
    });
    return () => cancelAnimations(animations);
  }, [summary.loading, refreshKey, reducedMotion]);

  const usage = summary.data || ({} as UsageSummary);
  const kpis = [
    { label: "总用户", value: usage.totalUsers, icon: <Users />, tone: "brand", hint: `活跃 ${nf(usage.activeUsers)} 人` },
    { label: "OCR 记录", value: usage.totalRecords, icon: <FileText />, tone: "info", hint: "仅展示元数据" },
    { label: "待处理反馈", value: usage.openFeedback ?? usage.totalFeedback, icon: <MessageSquareWarning />, tone: "warn", hint: "按状态队列处理" },
    { label: "审计事件", value: pageTotal(audits.data), icon: <ClipboardList />, tone: "success", hint: "最近操作留痕" }
  ];

  return (
    <section ref={ref}>
      <PageIntro
        eyebrow="Operations Overview"
        title="今日运行状态"
        body="聚合用户、识别、反馈与审计数据，帮助管理员快速判断系统是否需要处理。"
        icon={<BarChart3 />}
      />
      <div className="kpi-grid">
        {kpis.map((kpi) => (
          <article key={kpi.label} className="kpi-card motion-section">
            <IconWrap tone={kpi.tone}>{kpi.icon}</IconWrap>
            <span>{kpi.label}</span>
            <CountUp value={kpi.value} loading={summary.loading || audits.loading} />
            <small>{kpi.hint}</small>
          </article>
        ))}
      </div>
      <div className="two-col overview-workspace">
        <Panel title="额度消耗概览" subtitle="后台只展示聚合指标，不展示用户原文。">
          <div className="usage-list">
            {[
              ["OCR", usage.ocrUsed ?? usage.ocrUsage, "brand"],
              ["AI", usage.aiUsed ?? usage.aiUsage, "info"],
              ["导出", usage.exportUsed ?? usage.exportUsage, "success"]
            ].map(([name, value, tone]) => (
              <div key={name as string} className="usage-item">
                <div>
                  <b>{name}</b>
                  <span>{nf(value as number)} 次</span>
                </div>
                <i
                  className={tone as string}
                  data-scale={Math.min(Number(value || 0) / 100, 1)}
                  style={{ transform: `scaleX(${Math.min(Number(value || 0) / 100, 1)})` }}
                />
              </div>
            ))}
          </div>
        </Panel>
        <Panel title="最近审计日志" subtitle="仅包含动作、目标与时间。">
          {audits.loading ? (
            <StateBlock type="loading" title="正在加载审计日志" />
          ) : audits.error ? (
            <StateBlock type="error" title="审计日志加载失败" body={audits.error} />
          ) : auditRows.length ? (
            <div className="recent-list">
              {auditRows.slice(0, 6).map((row) => (
                <div className="recent-item data-row" key={row.id}>
                  <IconWrap tone="neutral">
                    <Clock3 />
                  </IconWrap>
                  <div>
                    <b>{labelFor(row.action)}</b>
                    <span>
                      {row.targetType || "-"} #{row.targetId || "-"} · {compactDate(row.createdAt)}
                    </span>
                  </div>
                </div>
              ))}
            </div>
          ) : (
            <StateBlock type="empty" title="暂无审计事件" body="管理员操作产生后会显示在这里。" />
          )}
        </Panel>
      </div>
    </section>
  );
}

function UsersPage({
  refreshKey,
  openDrawer,
  notify
}: {
  refreshKey: number;
  openDrawer: (title: string, body: ReactNode) => void;
  notify: (message: Omit<ToastMessage, "id">) => void;
}) {
  const ref = useRef<HTMLElement>(null);
  const [keyword, setKeyword] = useState("");
  const [status, setStatus] = useState("");
  const [level, setLevel] = useState("");
  const [query, setQuery] = useState({ keyword: "", status: "", level: "" });
  const data = useAsyncData(() => api.users(query), [query.keyword, query.status, query.level, refreshKey]);
  const rows = pageItems<AdminUser>(data.data);
  useReveal(ref, [data.loading, query, refreshKey]);

  const showUser = async (id: number) => {
    openDrawer("用户详情", <StateBlock type="loading" title="正在加载用户详情" />);
    try {
      const user = await api.user(id);
      openDrawer(
        "用户详情",
        <div className="detail-stack">
          <div className="detail-hero">
            <IconWrap tone="brand">
              <Users />
            </IconWrap>
            <div>
              <h4>{user.nickname || user.username || `用户 #${user.id}`}</h4>
              <span>#{user.id}</span>
            </div>
          </div>
          <dl className="detail-list">
            <dt>用户名</dt>
            <dd>{user.username || "-"}</dd>
            <dt>状态</dt>
            <dd>
              <StatusBadge value={user.status} />
            </dd>
            <dt>会员等级</dt>
            <dd>
              <StatusBadge value={user.membershipLevel} />
            </dd>
            <dt>创建时间</dt>
            <dd>{compactDate(user.createdAt)}</dd>
            <dt>最近登录</dt>
            <dd>{compactDate(user.lastLoginAt)}</dd>
          </dl>
          <p className="privacy-note">详情接口只返回用户元数据与会员信息，不展示认证凭证或私密内容。</p>
        </div>
      );
    } catch (err) {
      notify({ type: "error", title: "用户详情加载失败", body: (err as Error).message });
    }
  };

  return (
    <section ref={ref}>
      <PageIntro
        eyebrow="User Directory"
        title="用户、状态和会员等级"
        body="通过关键字、账号状态和会员等级定位用户；所有列表响应均保持脱敏。"
        icon={<Users />}
      />
      <Panel title="用户列表" subtitle="按关键字、状态与会员等级检索账号，结果保持脱敏">
        <div className="toolbar">
          <label className="search-field">
            <Search />
            <input value={keyword} onChange={(event) => setKeyword(event.target.value)} placeholder="用户名 / ID" />
          </label>
          <select value={status} onChange={(event) => setStatus(event.target.value)}>
            <option value="">全部状态</option>
            {USER_STATUS.map((item) => (
              <option key={item} value={item}>
                {labelFor(item)}
              </option>
            ))}
          </select>
          <select value={level} onChange={(event) => setLevel(event.target.value)}>
            <option value="">全部会员</option>
            {LEVELS.map((item) => (
              <option key={item} value={item}>
                {labelFor(item)}
              </option>
            ))}
          </select>
          <button className="btn primary" onClick={() => setQuery({ keyword, status, level })}>
            查询
          </button>
          <button
            className="btn ghost"
            onClick={() => {
              setKeyword("");
              setStatus("");
              setLevel("");
              setQuery({ keyword: "", status: "", level: "" });
            }}
          >
            重置
          </button>
        </div>
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>ID</th>
                <th>用户</th>
                <th>状态</th>
                <th>会员等级</th>
                <th>创建时间</th>
                <th className="right">操作</th>
              </tr>
            </thead>
            <tbody>
              {data.loading ? (
                <LoadingRows columns={6} />
              ) : data.error ? (
                <tr>
                  <td colSpan={6}>
                    <StateBlock type="error" title="用户列表加载失败" body={data.error} />
                  </td>
                </tr>
              ) : rows.length ? (
                rows.map((user) => (
                  <tr className="data-row" key={user.id}>
                    <td className="mono">#{user.id}</td>
                    <td>
                      <b>{user.nickname || user.username || "-"}</b>
                      <span className="cell-sub">{user.username || "-"}</span>
                    </td>
                    <td>
                      <StatusBadge value={user.status} />
                    </td>
                    <td>
                      <StatusBadge value={user.membershipLevel} />
                    </td>
                    <td className="mono">{compactDate(user.createdAt)}</td>
                    <td className="right">
                      <button className="link-btn" onClick={() => showUser(user.id)}>
                        查看详情
                      </button>
                    </td>
                  </tr>
                ))
              ) : (
                <tr>
                  <td colSpan={6}>
                    <StateBlock type="empty" title="没有匹配用户" body="调整筛选条件后重试。" />
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
        <div className="table-foot">共 {data.loading ? "..." : nf(pageTotal(data.data))} 个用户</div>
      </Panel>
    </section>
  );
}

function QuotaPage({
  refreshKey,
  confirm,
  notify
}: {
  refreshKey: number;
  confirm: (state: ConfirmState) => void;
  notify: (message: Omit<ToastMessage, "id">) => void;
}) {
  const ref = useRef<HTMLElement>(null);
  const [userId, setUserId] = useState("");
  const [level, setLevel] = useState("PRO");
  const [ocrQuota, setOcrQuota] = useState(100);
  const [aiQuota, setAiQuota] = useState(20);
  const [exportQuota, setExportQuota] = useState(10);
  const [note, setNote] = useState("");
  const [user, setUser] = useState<AdminUser | null>(null);
  const [lookupState, setLookupState] = useState("");
  const users = useAsyncData(() => api.users({ level: "PRO" }), [refreshKey]);
  useReveal(ref, [refreshKey, users.loading]);

  const lookup = async () => {
    if (!userId.trim()) return;
    setLookupState("正在查询用户");
    try {
      const row = await api.user(userId.trim());
      setUser(row);
      setLookupState(`匹配用户：${row.nickname || row.username || `#${row.id}`}`);
    } catch (err) {
      setUser(null);
      setLookupState((err as Error).message || "用户不存在或无权读取");
    }
  };

  const payload = () => ({
    membershipLevel: level,
    ocrQuota: Number(ocrQuota),
    aiQuota: Number(aiQuota),
    exportQuota: Number(exportQuota)
  });

  const saveMembership = () => {
    if (!userId.trim()) {
      notify({ type: "error", title: "缺少用户 ID" });
      return;
    }
    confirm({
      title: "确认保存会员额度",
      tone: "brand",
      confirmText: "保存额度",
      body: (
        <p>
          将用户 <b className="mono">#{userId}</b> 调整为 <b>{level}</b>，OCR / AI / 导出额度分别为{" "}
          <b>
            {ocrQuota} / {aiQuota} / {exportQuota}
          </b>
          。
        </p>
      ),
      onConfirm: async () => {
        await api.updateMembership(userId.trim(), payload());
        notify({ type: "success", title: "额度已保存", body: `用户 #${userId} 的会员额度已更新。` });
        lookup();
      }
    });
  };

  const createOrder = () => {
    if (!userId.trim()) {
      notify({ type: "error", title: "缺少用户 ID" });
      return;
    }
    confirm({
      title: "确认手工开通会员",
      tone: "brand",
      confirmText: "开通",
      body: (
        <div>
          <p>
            将为用户 <b className="mono">#{userId}</b> 创建手工开通订单并同步更新会员额度。
          </p>
          <p className="privacy-note">该流程不接入支付、订阅、发票或退款闭环。</p>
        </div>
      ),
      onConfirm: async () => {
        await api.manualOrder(userId.trim(), { ...payload(), note: note.trim() });
        notify({ type: "success", title: "手工开通完成", body: `用户 #${userId} 已开通 ${level}。` });
        lookup();
      }
    });
  };

  return (
    <section ref={ref}>
      <PageIntro
        eyebrow="Quota Operations"
        title="会员额度与手工开通"
        body="用于课程或运营场景的额度维护。所有写操作都会经过确认，并由后端写入审计日志。"
        icon={<Gauge />}
      />
      <div className="quota-layout">
        <Panel title="额度调整" subtitle="按用户设置会员等级与 OCR / AI / 导出额度" className="quota-editor-panel">
          <div className="form-stack">
            <div className="form-section-title">
              <span>目标用户</span>
              <b>先查询用户，再调整权益</b>
            </div>
            <label>
              <span>用户 ID</span>
              <div className="inline-field">
                <input value={userId} onChange={(event) => setUserId(event.target.value)} placeholder="输入用户 ID" />
                <button className="btn" onClick={lookup}>
                  查询
                </button>
              </div>
              {lookupState ? <small>{lookupState}</small> : null}
            </label>
            <div className="form-section-title">
              <span>额度配置</span>
              <b>写操作会进入审计日志</b>
            </div>
            <div className="segmented">
              {LEVELS.filter((item) => item !== "FREE").map((item) => (
                <button key={item} className={level === item ? "active" : ""} onClick={() => setLevel(item)}>
                  {item}
                </button>
              ))}
            </div>
            <div className="form-grid">
              <label>
                <span>OCR 额度</span>
                <input type="number" min={0} value={ocrQuota} onChange={(event) => setOcrQuota(Number(event.target.value))} />
              </label>
              <label>
                <span>AI 额度</span>
                <input type="number" min={0} value={aiQuota} onChange={(event) => setAiQuota(Number(event.target.value))} />
              </label>
              <label>
                <span>导出额度</span>
                <input
                  type="number"
                  min={0}
                  value={exportQuota}
                  onChange={(event) => setExportQuota(Number(event.target.value))}
                />
              </label>
            </div>
            <label>
              <span>手工开通备注</span>
              <textarea value={note} onChange={(event) => setNote(event.target.value)} placeholder="可选，仅用于后台审计说明" />
            </label>
            <div className="actions-row">
              <button className="btn primary" onClick={saveMembership}>
                保存额度
              </button>
              <button className="btn" onClick={createOrder}>
                手工开通
              </button>
            </div>
          </div>
        </Panel>
        <Panel title="最近 PRO 用户" subtitle="帮助快速复制用户 ID。" className="quota-recent-panel">
          {users.loading ? (
            <StateBlock type="loading" title="正在加载用户" />
          ) : pageItems<AdminUser>(users.data).length ? (
            <div className="recent-list compact">
              {pageItems<AdminUser>(users.data)
                .slice(0, 8)
                .map((row) => (
                  <button
                    className="recent-item data-row pick-row"
                    key={row.id}
                    onClick={() => {
                      setUserId(String(row.id));
                      setUser(row);
                      setLookupState(`已选择：${row.nickname || row.username || `#${row.id}`}`);
                    }}
                  >
                    <IconWrap tone="brand">
                      <UserCog />
                    </IconWrap>
                    <div>
                      <b>{row.nickname || row.username}</b>
                      <span>
                        #{row.id} · {row.membershipLevel}
                      </span>
                    </div>
                  </button>
                ))}
            </div>
          ) : (
            <StateBlock type="empty" title="暂无可选用户" />
          )}
          {user ? (
            <div className="selected-user">
              <span>当前目标</span>
              <b>
                #{user.id} · {user.nickname || user.username}
              </b>
              <StatusBadge value={user.membershipLevel} />
            </div>
          ) : null}
        </Panel>
      </div>
    </section>
  );
}

function CodesPage({
  refreshKey,
  confirm,
  notify
}: {
  refreshKey: number;
  confirm: (state: ConfirmState) => void;
  notify: (message: Omit<ToastMessage, "id">) => void;
}) {
  const ref = useRef<HTMLElement>(null);
  const [level, setLevel] = useState("PRO");
  const [ocrQuota, setOcrQuota] = useState(100);
  const [aiQuota, setAiQuota] = useState(20);
  const [exportQuota, setExportQuota] = useState(10);
  const [count, setCount] = useState(1);
  const [expiresAt, setExpiresAt] = useState(defaultExpiryValue);
  const [note, setNote] = useState("");
  const [created, setCreated] = useState<ActivationCode[]>([]);
  const [reload, setReload] = useState(0);
  const list = useAsyncData(() => api.codes(), [refreshKey, reload]);
  const rows = pageItems<ActivationCode>(list.data);
  useReveal(ref, [list.loading, refreshKey, reload, created.length]);

  const create = () => {
    if (!expiresAt) {
      notify({ type: "error", title: "请填写过期时间", body: "激活码必须设置有效期。" });
      return;
    }
    confirm({
      title: "确认生成激活码",
      tone: "brand",
      confirmText: "生成",
      body: (
        <p>
          将生成 <b>{count}</b> 个 <b>{level}</b> 激活码。明文只会在创建结果中展示一次，请妥善保存。
        </p>
      ),
      onConfirm: async () => {
        const result = await api.createCodes({
          membershipLevel: level,
          ocrQuota: Number(ocrQuota),
          aiQuota: Number(aiQuota),
          exportQuota: Number(exportQuota),
          expiresAt,
          count: Number(count),
          note: note.trim()
        });
        setCreated(result.codes || []);
        setReload((value) => value + 1);
        notify({ type: "success", title: "激活码已生成", body: "明文仅在当前结果区展示一次。" });
      }
    });
  };

  const revoke = (id: number) => {
    confirm({
      title: "确认撤销激活码",
      tone: "danger",
      confirmText: "撤销",
      body: (
        <p>
          确认撤销激活码 <b className="mono">#{id}</b>？已兑换或已过期的激活码不会被撤销。
        </p>
      ),
      onConfirm: async () => {
        await api.revokeCode(id);
        setReload((value) => value + 1);
        notify({ type: "success", title: "激活码已撤销" });
      }
    });
  };

  const copyCode = async (code?: string) => {
    if (!code) return;
    await navigator.clipboard.writeText(code);
    notify({ type: "success", title: "已复制", body: "激活码已复制到剪贴板。" });
  };

  return (
    <section ref={ref}>
      <PageIntro
        eyebrow="Activation Codes"
        title="一次性会员激活码"
        body="生成、查看和撤销 PRO / TEAM 权益码。列表只展示指纹与元数据，绝不回显完整明文。"
        icon={<TicketCheck />}
      />
      <Panel title="生成激活码" subtitle="配置权益参数后批量签发，明文仅在结果区展示一次" className="activation-panel">
        <div className="form-stack activation-form">
            <div className="form-section-title">
              <span>配置参数</span>
              <b>过期时间必填，明文只展示一次</b>
            </div>
            <div className="activation-config">
            <div className="segmented">
            {["PRO", "TEAM"].map((item) => (
              <button key={item} className={level === item ? "active" : ""} onClick={() => setLevel(item)}>
                {item}
              </button>
            ))}
            </div>
            <div className="form-grid">
            <label>
              <span>OCR 额度</span>
              <input type="number" min={0} value={ocrQuota} onChange={(event) => setOcrQuota(Number(event.target.value))} />
            </label>
            <label>
              <span>AI 额度</span>
              <input type="number" min={0} value={aiQuota} onChange={(event) => setAiQuota(Number(event.target.value))} />
            </label>
            <label>
              <span>导出额度</span>
              <input
                type="number"
                min={0}
                value={exportQuota}
                onChange={(event) => setExportQuota(Number(event.target.value))}
              />
            </label>
            <label>
              <span>数量</span>
              <input type="number" min={1} max={50} value={count} onChange={(event) => setCount(Number(event.target.value))} />
            </label>
            <label>
              <span>过期时间</span>
              <input type="datetime-local" value={expiresAt} onChange={(event) => setExpiresAt(event.target.value)} />
            </label>
            <label>
              <span>备注</span>
              <input value={note} onChange={(event) => setNote(event.target.value)} placeholder="可选" />
            </label>
            </div>
          </div>
          <div className="activation-action-row">
            <span>生成后请立即复制保存，列表仅保留指纹与状态。</span>
            <button className="btn primary activation-submit" onClick={create}>
              生成激活码
            </button>
          </div>
        </div>
        {created.length ? (
          <div className="reveal-box motion-section">
            <div className="reveal-head">
              <KeyRound />
              <b>创建结果：明文只展示一次</b>
            </div>
            {created.map((item) => (
              <div className="reveal-row" key={`${item.id}-${item.codeFingerprint}`}>
                <span className="mono">{item.code}</span>
                <StatusBadge value={item.membershipLevel} />
                <button className="icon-btn" onClick={() => copyCode(item.code)} aria-label="复制激活码">
                  <Copy />
                </button>
              </div>
            ))}
          </div>
        ) : null}
      </Panel>
      <Panel title="激活码列表" subtitle="列表仅展示指纹与状态，不回显完整明文">
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>ID</th>
                <th>指纹</th>
                <th>等级</th>
                <th>额度</th>
                <th>状态</th>
                <th>过期时间</th>
                <th className="right">操作</th>
              </tr>
            </thead>
            <tbody>
              {list.loading ? (
                <LoadingRows columns={7} rows={4} />
              ) : list.error ? (
                <tr>
                  <td colSpan={7}>
                    <StateBlock type="error" title="激活码列表加载失败" body={list.error} />
                  </td>
                </tr>
              ) : rows.length ? (
                rows.map((code) => (
                  <tr className="data-row" key={code.id}>
                    <td className="mono">#{code.id}</td>
                    <td className="mono">{code.codeFingerprint || "-"}</td>
                    <td>
                      <StatusBadge value={code.membershipLevel} />
                    </td>
                    <td className="mono">
                      {nf(code.ocrQuota)} / {nf(code.aiQuota)} / {nf(code.exportQuota)}
                    </td>
                    <td>
                      <StatusBadge value={code.status} />
                    </td>
                    <td className="mono">{compactDate(code.expiresAt)}</td>
                    <td className="right">
                      {code.status === "UNUSED" ? (
                        <button className="link-btn danger" onClick={() => revoke(code.id)}>
                          撤销
                        </button>
                      ) : (
                        <span className="muted">-</span>
                      )}
                    </td>
                  </tr>
                ))
              ) : (
                <tr>
                  <td colSpan={7}>
                    <StateBlock type="empty" title="暂无激活码" />
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </Panel>
    </section>
  );
}

function RecordsPage({ refreshKey }: { refreshKey: number }) {
  const ref = useRef<HTMLElement>(null);
  const [userId, setUserId] = useState("");
  const [sourceType, setSourceType] = useState("");
  const [keyword, setKeyword] = useState("");
  const [query, setQuery] = useState({ userId: "", sourceType: "", keyword: "" });
  const data = useAsyncData(() => api.records(query), [query.userId, query.sourceType, query.keyword, refreshKey]);
  const rows = pageItems<RecordRow>(data.data);
  useReveal(ref, [data.loading, query, refreshKey]);
  return (
    <section ref={ref}>
      <PageIntro
        eyebrow="Record Metadata"
        title="OCR 记录脱敏查询"
        icon={<FileText />}
        body="后台只读取记录元数据、来源和文本长度；完整识别文本仍由用户侧权限保护。"
      />
      <Panel title="记录列表" subtitle="仅读取记录元数据、来源与文本长度，不含识别正文">
        <div className="toolbar">
          <input value={userId} onChange={(event) => setUserId(event.target.value)} placeholder="用户 ID" />
          <select value={sourceType} onChange={(event) => setSourceType(event.target.value)}>
            <option value="">全部来源</option>
            {RECORD_SOURCES.map((item) => (
              <option key={item} value={item}>
                {labelFor(item)}
              </option>
            ))}
          </select>
          <label className="search-field">
            <Search />
            <input value={keyword} onChange={(event) => setKeyword(event.target.value)} placeholder="标题关键字" />
          </label>
          <button className="btn primary" onClick={() => setQuery({ userId, sourceType, keyword })}>
            查询
          </button>
          <button
            className="btn ghost"
            onClick={() => {
              setUserId("");
              setSourceType("");
              setKeyword("");
              setQuery({ userId: "", sourceType: "", keyword: "" });
            }}
          >
            重置
          </button>
        </div>
        <DataTable
          loading={data.loading}
          error={data.error}
          emptyTitle="没有匹配记录"
          columns={["ID", "用户", "标题", "来源", "文本长度", "创建时间"]}
          rows={rows.map((row) => [
            <span className="mono">#{row.id}</span>,
            <span className="mono">#{row.userId || "-"}</span>,
            <b>{row.title || "-"}</b>,
            <StatusBadge value={row.sourceType?.toUpperCase()} />,
            <span className="mono">{nf(row.textLength)}</span>,
            <span className="mono">{compactDate(row.createdAt)}</span>
          ])}
        />
      </Panel>
    </section>
  );
}

function FeedbackPage({
  refreshKey,
  confirm,
  notify
}: {
  refreshKey: number;
  confirm: (state: ConfirmState) => void;
  notify: (message: Omit<ToastMessage, "id">) => void;
}) {
  const ref = useRef<HTMLElement>(null);
  const [userId, setUserId] = useState("");
  const [type, setType] = useState("");
  const [status, setStatus] = useState("");
  const [reload, setReload] = useState(0);
  const data = useAsyncData(() => api.feedback({ userId, type, status }), [userId, type, status, refreshKey, reload]);
  const rows = pageItems<FeedbackRow>(data.data);
  useReveal(ref, [data.loading, userId, type, status, reload]);

  const updateStatus = (row: FeedbackRow) => {
    let next = row.status || "PROCESSING";
    confirm({
      title: "更新反馈状态",
      tone: "brand",
      confirmText: "保存状态",
      body: (
        <div className="form-stack compact-form">
          <p>
            反馈 <b className="mono">#{row.id}</b> · 当前状态 <StatusBadge value={row.status} />
          </p>
          <label>
            <span>更新为</span>
            <select defaultValue={next} onChange={(event) => (next = event.target.value)}>
              {FEEDBACK_STATUS.map((item) => (
                <option key={item} value={item}>
                  {labelFor(item)}
                </option>
              ))}
            </select>
          </label>
        </div>
      ),
      onConfirm: async () => {
        await api.updateFeedbackStatus(row.id, next);
        setReload((value) => value + 1);
        notify({ type: "success", title: "反馈状态已更新", body: `反馈 #${row.id} 已更新为 ${labelFor(next)}。` });
      }
    });
  };

  return (
    <section ref={ref}>
      <PageIntro
        eyebrow="Feedback Queue"
        title="反馈状态处理"
        body="列表只展示反馈元数据和处理状态，不展示正文、联系方式或设备详情。"
        icon={<MessageSquareWarning />}
      />
      <Panel title="反馈列表" subtitle="按用户、类型与状态筛选，流转处理进度">
        <div className="toolbar">
          <input value={userId} onChange={(event) => setUserId(event.target.value)} placeholder="用户 ID" />
          <select value={type} onChange={(event) => setType(event.target.value)}>
            <option value="">全部类型</option>
            {FEEDBACK_TYPES.map((item) => (
              <option key={item} value={item}>
                {labelFor(item)}
              </option>
            ))}
          </select>
          <select value={status} onChange={(event) => setStatus(event.target.value)}>
            <option value="">全部状态</option>
            {["OPEN", "IN_PROGRESS", "RESOLVED", "CLOSED"].map((item) => (
              <option key={item} value={item}>
                {labelFor(item)}
              </option>
            ))}
          </select>
        </div>
        <DataTable
          loading={data.loading}
          error={data.error}
          emptyTitle="没有匹配反馈"
          columns={["ID", "用户", "类型", "状态", "创建时间", "操作"]}
          rows={rows.map((row) => [
            <span className="mono">#{row.id}</span>,
            <span className="mono">#{row.userId || "-"}</span>,
            labelFor(row.feedbackType),
            <StatusBadge value={row.status} />,
            <span className="mono">{compactDate(row.createdAt)}</span>,
            <button className="link-btn" onClick={() => updateStatus(row)}>
              更新状态
            </button>
          ])}
        />
      </Panel>
    </section>
  );
}

function AuditPage({ refreshKey }: { refreshKey: number }) {
  const ref = useRef<HTMLElement>(null);
  const [action, setAction] = useState("");
  const [targetType, setTargetType] = useState("");
  const [targetId, setTargetId] = useState("");
  const [query, setQuery] = useState({ action: "", targetType: "", targetId: "" });
  const data = useAsyncData(() => api.auditLogs(query), [query.action, query.targetType, query.targetId, refreshKey]);
  const rows = pageItems<AuditLog>(data.data);
  useReveal(ref, [data.loading, query, refreshKey]);

  return (
    <section ref={ref}>
      <PageIntro
        eyebrow="Audit Trail"
        title="管理员操作审计"
        body="审计列表记录动作、目标和时间，不保存请求体或敏感值。"
        icon={<ClipboardList />}
      />
      <Panel title="审计日志" subtitle="按动作、目标类型与目标 ID 追溯管理员操作">
        <div className="toolbar">
          <select value={action} onChange={(event) => setAction(event.target.value)}>
            <option value="">全部动作</option>
            {AUDIT_ACTIONS.map((item) => (
              <option key={item} value={item}>
                {labelFor(item)}
              </option>
            ))}
          </select>
          <select value={targetType} onChange={(event) => setTargetType(event.target.value)}>
            <option value="">全部目标</option>
            {["USER", "ACTIVATION_CODE", "FEEDBACK"].map((item) => (
              <option key={item} value={item}>
                {item}
              </option>
            ))}
          </select>
          <input value={targetId} onChange={(event) => setTargetId(event.target.value)} placeholder="目标 ID" />
          <button className="btn primary" onClick={() => setQuery({ action, targetType, targetId })}>
            查询
          </button>
          <button
            className="btn ghost"
            onClick={() => {
              setAction("");
              setTargetType("");
              setTargetId("");
              setQuery({ action: "", targetType: "", targetId: "" });
            }}
          >
            重置
          </button>
        </div>
        <DataTable
          loading={data.loading}
          error={data.error}
          emptyTitle="没有匹配日志"
          columns={["ID", "管理员", "动作", "目标类型", "目标 ID", "时间"]}
          rows={rows.map((row) => [
            <span className="mono">#{row.id}</span>,
            <span className="mono">admin#{row.adminUserId || "-"}</span>,
            labelFor(row.action),
            <StatusBadge value={row.targetType} />,
            <span className="mono">#{row.targetId || "-"}</span>,
            <span className="mono">{compactDate(row.createdAt)}</span>
          ])}
        />
      </Panel>
    </section>
  );
}

function AccountPage({
  user,
  refreshSession,
  logout,
  confirm,
  notify
}: {
  user: SessionUser | null;
  refreshSession: () => Promise<void>;
  logout: () => void;
  confirm: (state: ConfirmState) => void;
  notify: (message: Omit<ToastMessage, "id">) => void;
}) {
  const ref = useRef<HTMLElement>(null);
  const [nickname, setNickname] = useState(user?.nickname || "");
  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  useReveal(ref, [user?.id]);

  useEffect(() => setNickname(user?.nickname || ""), [user?.nickname]);
  const strength = useMemo(() => {
    let score = 0;
    if (newPassword.length >= 8) score += 1;
    if (/[a-z]/.test(newPassword) && /[A-Z]/.test(newPassword)) score += 1;
    if (/\d/.test(newPassword)) score += 1;
    if (/[^A-Za-z0-9]/.test(newPassword)) score += 1;
    return score;
  }, [newPassword]);

  const saveProfile = async () => {
    await api.updateMe({ nickname: nickname.trim() });
    await refreshSession();
    notify({ type: "success", title: "资料已保存" });
  };

  const savePassword = () => {
    if (!currentPassword || !newPassword || newPassword !== confirmPassword || strength < 2) {
      notify({ type: "error", title: "密码信息不完整", body: "请检查当前密码、新密码强度和两次确认。" });
      return;
    }
    confirm({
      title: "确认修改密码",
      tone: "brand",
      confirmText: "修改",
      body: <p>确认更新当前管理员密码？密码不会在页面、日志或接口响应中展示。</p>,
      onConfirm: async () => {
        await api.changePassword({ currentPassword, newPassword });
        setCurrentPassword("");
        setNewPassword("");
        setConfirmPassword("");
        notify({ type: "success", title: "密码已修改" });
      }
    });
  };

  return (
    <section ref={ref}>
      <PageIntro
        eyebrow="Account Security"
        title="当前管理员账号"
        body="维护自己的低敏资料和登录密码；退出登录会清理本地会话凭证。"
        icon={<UserCog />}
      />
      <div className="two-col wide account-grid">
        <Panel title="账号摘要" subtitle="当前登录管理员的身份与登录信息">
          <div className="account-hero">
            <IconWrap tone="brand">
              <ShieldCheck />
            </IconWrap>
            <div>
              <h3>{user?.nickname || user?.username || "Admin"}</h3>
              <p>
                #{user?.id || "-"} · <StatusBadge value={user?.status || "ACTIVE"} />
              </p>
            </div>
          </div>
          <dl className="detail-list inline">
            <dt>用户名</dt>
            <dd>{user?.username || "-"}</dd>
            <dt>创建时间</dt>
            <dd>{compactDate(user?.createdAt)}</dd>
            <dt>最近登录</dt>
            <dd>{compactDate(user?.lastLoginAt)}</dd>
          </dl>
        </Panel>
        <Panel title="基本资料" subtitle="更新展示昵称">
          <div className="form-stack">
            <label>
              <span>用户名</span>
              <input value={user?.username || ""} readOnly />
            </label>
            <label>
              <span>昵称</span>
              <input value={nickname} onChange={(event) => setNickname(event.target.value)} placeholder="运营管理员" />
            </label>
            <button className="btn primary" onClick={saveProfile}>
              保存资料
            </button>
          </div>
        </Panel>
        <Panel title="修改密码" subtitle="定期更新登录密码以保障账号安全">
          <div className="form-stack">
            <label>
              <span>当前密码</span>
              <input type="password" value={currentPassword} onChange={(event) => setCurrentPassword(event.target.value)} />
            </label>
            <label>
              <span>新密码</span>
              <input type="password" value={newPassword} onChange={(event) => setNewPassword(event.target.value)} />
              <i className={`strength s${strength}`}>
                <span />
                <span />
                <span />
                <span />
              </i>
            </label>
            <label>
              <span>确认新密码</span>
              <input type="password" value={confirmPassword} onChange={(event) => setConfirmPassword(event.target.value)} />
            </label>
            <button className="btn primary" onClick={savePassword}>
              保存新密码
            </button>
          </div>
        </Panel>
        <Panel title="登录与安全" subtitle="当前会话状态与安全操作">
          <div className="session-card">
            <IconWrap tone="success">
              <BadgeCheck />
            </IconWrap>
            <div>
              <b>当前浏览器会话</b>
              <span>登录凭证仅保留在本次浏览器会话中，关闭或退出后立即清除，不会写入本地磁盘。</span>
            </div>
          </div>
          <div className="session-card">
            <IconWrap tone="brand">
              <ShieldCheck />
            </IconWrap>
            <div>
              <b>管理员权限</b>
              <span>已通过 Admin 权限校验，可执行用户、额度、激活码与审计相关的后台操作。</span>
            </div>
          </div>
          <button className="btn danger subtle" onClick={logout}>
            <LogOut />
            退出当前会话
          </button>
        </Panel>
      </div>
    </section>
  );
}

function DataTable({
  loading,
  error,
  emptyTitle,
  columns,
  rows
}: {
  loading: boolean;
  error?: string;
  emptyTitle: string;
  columns: string[];
  rows: ReactNode[][];
}) {
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            {columns.map((column, index) => (
              <th key={column} className={index === columns.length - 1 ? "right" : ""}>
                {column}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {loading ? (
            <LoadingRows columns={columns.length} />
          ) : error ? (
            <tr>
              <td colSpan={columns.length}>
                <StateBlock type="error" title="加载失败" body={error} />
              </td>
            </tr>
          ) : rows.length ? (
            rows.map((row, index) => (
              <tr className="data-row" key={index}>
                {row.map((cell, cellIndex) => (
                  <td key={cellIndex} className={cellIndex === row.length - 1 ? "right" : ""}>
                    {cell}
                  </td>
                ))}
              </tr>
            ))
          ) : (
            <tr>
              <td colSpan={columns.length}>
                <StateBlock type="empty" title={emptyTitle} body="调整筛选条件或稍后重试。" />
              </td>
            </tr>
          )}
        </tbody>
      </table>
      <div className="table-foot">共 {loading ? "..." : nf(rows.length)} 条</div>
    </div>
  );
}

export function AdminConsole() {
  const [checking, setChecking] = useState(true);
  const [loginBusy, setLoginBusy] = useState(false);
  const [loginError, setLoginError] = useState("");
  const [user, setUser] = useState<SessionUser | null>(null);
  const [active, setActive] = useState<ModuleKey>("overview");
  const [refreshKey, setRefreshKey] = useState(0);
  const [toasts, setToasts] = useState<ToastMessage[]>([]);
  const [confirmState, setConfirmState] = useState<ConfirmState | null>(null);
  const [drawer, setDrawer] = useState<{ title: string; body: ReactNode } | null>(null);

  const notify = (message: Omit<ToastMessage, "id">) => {
    const id = Date.now() + Math.floor(Math.random() * 1000);
    setToasts((items) => [...items, { id, ...message }]);
    window.setTimeout(() => setToasts((items) => items.filter((item) => item.id !== id)), 3800);
  };

  const refreshSession = async () => {
    const me = await api.me();
    setUser(me);
  };

  useEffect(() => {
    const restore = async () => {
      if (!sessionValue()) {
        setChecking(false);
        return;
      }
      try {
        await api.adminMe();
        await refreshSession();
      } catch {
        clearSessionTokens();
      } finally {
        setChecking(false);
      }
    };
    restore();
  }, []);

  useEffect(() => {
    const onAuthError = (event: Event) => {
      const detail = (event as CustomEvent).detail;
      if (detail?.status === 401) {
        clearSessionTokens();
        setUser(null);
        setLoginError("管理员会话已过期，请重新登录。");
      } else if (detail?.status === 403) {
        notify({ type: "error", title: "权限不足", body: "当前账号没有 Admin 权限。" });
      }
    };
    window.addEventListener("admin-console-auth-error", onAuthError);
    return () => window.removeEventListener("admin-console-auth-error", onAuthError);
  }, []);

  const login = async (username: string, password: string) => {
    if (!username || !password) {
      setLoginError("请输入管理员账号和密码。");
      return;
    }
    setLoginBusy(true);
    setLoginError("");
    try {
      const auth = await api.login(username, password);
      setSessionTokens(auth);
      const capability = await api.adminMe();
      if (!capability?.admin) {
        clearSessionTokens();
        setLoginError("当前账号没有 Admin 权限。");
        return;
      }
      await refreshSession();
      setActive("overview");
      notify({ type: "success", title: "登录成功", body: "管理员权限校验通过。" });
    } catch (err) {
      clearSessionTokens();
      setLoginError((err as Error).message || "账号或密码不正确，或该账号不具备管理员权限。");
    } finally {
      setLoginBusy(false);
    }
  };

  const logout = () => {
    const run = async () => {
      try {
        await api.logout();
      } catch {
        // 退出时即使后端不可达，也必须清理本地会话，避免残留凭证。
      } finally {
        clearSessionTokens();
        setUser(null);
        setLoginError("");
      }
    };
    setConfirmState({
      title: "确认退出登录",
      tone: "danger",
      confirmText: "退出",
      body: <p>退出后会清理当前浏览器会话中的登录凭证。</p>,
      onConfirm: run
    });
  };

  const confirm = (state: ConfirmState) => setConfirmState(state);
  const runConfirm = async () => {
    if (!confirmState) return;
    try {
      await confirmState.onConfirm();
      setConfirmState(null);
    } catch (err) {
      notify({ type: "error", title: "操作失败", body: (err as Error).message });
    }
  };

  const moduleView = () => {
    const common = { refreshKey };
    if (active === "overview") return <OverviewPage {...common} />;
    if (active === "users")
      return (
        <UsersPage
          {...common}
          notify={notify}
          openDrawer={(title, body) => setDrawer({ title, body })}
        />
      );
    if (active === "quota") return <QuotaPage {...common} confirm={confirm} notify={notify} />;
    if (active === "codes") return <CodesPage {...common} confirm={confirm} notify={notify} />;
    if (active === "records") return <RecordsPage {...common} />;
    if (active === "feedback") return <FeedbackPage {...common} confirm={confirm} notify={notify} />;
    if (active === "audit") return <AuditPage {...common} />;
    return <AccountPage user={user} refreshSession={refreshSession} logout={logout} confirm={confirm} notify={notify} />;
  };

  if (checking) {
    return (
      <main className="boot-screen">
        <Loader2 className="spin" />
        <span>正在恢复管理员会话</span>
      </main>
    );
  }

  return (
    <>
      {user ? (
        <Shell
          user={user}
          active={active}
          setActive={setActive}
          onLogout={logout}
          onRefresh={() => setRefreshKey((value) => value + 1)}
        >
          {moduleView()}
        </Shell>
      ) : (
        <LoginScreen onLogin={login} busy={loginBusy} error={loginError} />
      )}
      <div className="toast-stack" role="status" aria-live="polite" aria-atomic="false">
        {toasts.map((toast) => (
          <ToastItem
            key={toast.id}
            toast={toast}
            onClose={() => setToasts((items) => items.filter((item) => item.id !== toast.id))}
          />
        ))}
      </div>
      <ConfirmModal state={confirmState} onCancel={() => setConfirmState(null)} onConfirm={runConfirm} />
      {drawer ? <Drawer title={drawer.title} onClose={() => setDrawer(null)}>{drawer.body}</Drawer> : null}
    </>
  );
}
