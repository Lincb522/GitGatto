#!/usr/bin/env python3
"""Generate the roadmap and architecture diagrams embedded by the repository docs."""

from __future__ import annotations

import argparse
import html
from pathlib import Path


STYLE = """
    :root { color-scheme: light dark; }
    .bg { fill: #ffffff; }
    .panel { fill: #f7f9fa; stroke: #dce2e6; stroke-width: 1.5; }
    .panel-accent { fill: #fff5ef; stroke: #efb092; stroke-width: 1.5; }
    .panel-green { fill: #edf8f4; stroke: #86c7b7; stroke-width: 1.5; }
    .panel-blue { fill: #eef5fb; stroke: #91b9da; stroke-width: 1.5; }
    .panel-purple { fill: #f5f0fb; stroke: #b7a0d4; stroke-width: 1.5; }
    .panel-muted { fill: #f2f4f5; stroke: #bfc7cd; stroke-width: 1.5; stroke-dasharray: 7 6; }
    .lane { fill: #fbfcfc; stroke: #e3e7ea; stroke-width: 1.5; }
    text { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }
    .title { fill: #17202a; font-size: 28px; font-weight: 700; }
    .section { fill: #17202a; font-size: 17px; font-weight: 700; }
    .label { fill: #25313b; font-size: 15px; font-weight: 650; }
    .detail { fill: #687580; font-size: 13px; font-weight: 500; }
    .badge { fill: #e85d24; font-size: 12px; font-weight: 700; }
    .connector { fill: none; stroke: #8b979f; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }
    .connector-accent { fill: none; stroke: #e85d24; stroke-width: 2.5; stroke-linecap: round; stroke-linejoin: round; }
    .dot { fill: #e85d24; }
    @media (prefers-color-scheme: dark) {
        .bg { fill: #101419; }
        .panel, .lane { fill: #171d23; stroke: #303943; }
        .panel-accent { fill: #2b1d17; stroke: #8f4d31; }
        .panel-green { fill: #14251f; stroke: #397d6c; }
        .panel-blue { fill: #16232e; stroke: #477da9; }
        .panel-purple { fill: #211b2a; stroke: #72599a; }
        .panel-muted { fill: #151a1f; stroke: #53606a; }
        .title, .section, .label { fill: #f2f5f7; }
        .detail { fill: #a2adb6; }
        .connector { stroke: #66737d; }
    }
"""


def text_block(
    x: float,
    y: float,
    lines: list[str],
    css: str = "label",
    anchor: str = "middle",
    gap: int = 20,
) -> str:
    tspans = []
    for index, line in enumerate(lines):
        dy = 0 if index == 0 else gap
        tspans.append(
            f'<tspan x="{x}" dy="{dy}">{html.escape(line)}</tspan>'
        )
    return f'<text class="{css}" x="{x}" y="{y}" text-anchor="{anchor}">' + "".join(tspans) + "</text>"


def card(
    x: float,
    y: float,
    width: float,
    height: float,
    title: str,
    details: list[str] | None = None,
    css: str = "panel",
) -> str:
    details = details or []
    content = [f'<rect class="{css}" x="{x}" y="{y}" width="{width}" height="{height}" rx="16"/>']
    title_y = y + height / 2 - (10 if details else -5)
    content.append(text_block(x + width / 2, title_y, [title], "label"))
    if details:
        content.append(text_block(x + width / 2, title_y + 24, details, "detail", gap=18))
    return "".join(content)


def arrow(x1: float, y1: float, x2: float, y2: float, accent: bool = False) -> str:
    css = "connector-accent" if accent else "connector"
    return f'<path class="{css}" d="M{x1} {y1} L{x2} {y2}" marker-end="url(#arrow)"/>'


def base_svg(width: int, height: int, title: str, description: str, body: str) -> str:
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">
<title id="title">{html.escape(title)}</title>
<desc id="desc">{html.escape(description)}</desc>
<style>{STYLE}</style>
<defs>
  <marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
    <path d="M 0 0 L 10 5 L 0 10 z" fill="#8b979f"/>
  </marker>
</defs>
<rect class="bg" x="0" y="0" width="{width}" height="{height}" rx="24"/>
{body}
</svg>
'''


def roadmap() -> str:
    width, height = 1520, 560
    stages = [
        ("0.14–0.18.10", ["Git · GitHub · 工作区", "Agent · 工具安装"], "panel-green"),
        ("0.18.11–0.18.26", ["目标 · 回归 · 灾备", "编排与项目工具"], "panel-green"),
        ("0.18.27–0.18.31", ["目标简化 · 自定义 API", "监控降频 · 更新签名"], "panel-green"),
        ("0.18.32–0.18.35", ["独立后台 · 全仓状态栏", "翻译与主题切换"], "panel-green"),
        ("0.18.36", ["监控面板扩展", "灾备落盘顺序修复"], "panel-accent"),
    ]
    planned = [
        ("NEXT 01", ["恢复验证回执", "完整恢复点导入与导出"]),
        ("NEXT 02", ["可复用 Agent", "处理方案"]),
        ("NEXT 03", ["公证与更新", "发行验证"]),
    ]
    body = [
        '<text class="title" x="64" y="58">GitGatto 路线图</text>',
        '<text class="detail" x="64" y="84">源码已实现范围见 CHANGELOG；发布状态见 Releases；虚线为计划</text>',
        '<text class="section" x="64" y="138">已实现</text>',
        '<line class="connector-accent" x1="142" y1="222" x2="1378" y2="222"/>',
    ]
    start_x, card_w, gap = 62, 250, 38
    for index, (version, details, css) in enumerate(stages):
        x = start_x + index * (card_w + gap)
        body.append(card(x, 166, card_w, 112, version, details, css))

    body.extend([
        '<text class="section" x="64" y="354">下一阶段</text>',
    ])
    plan_w, plan_gap, plan_x = 390, 78, 62
    for index, (badge, details) in enumerate(planned):
        x = plan_x + index * (plan_w + plan_gap)
        body.append(card(x, 386, plan_w, 108, details[0], [details[1]], "panel-muted"))
        body.append(f'<text class="badge" x="{x + 18}" y="410">{badge}</text>')
        if index < len(planned) - 1:
            body.append(arrow(x + plan_w + 12, 440, x + plan_w + plan_gap - 12, 440))
    return base_svg(width, height, "GitGatto 路线图", "已实现版本和下一阶段计划。", "\n".join(body))


def architecture() -> str:
    width, height = 1520, 1130
    body = [
        '<text class="title" x="64" y="58">GitGatto 系统架构</text>',
        '<text class="detail" x="64" y="84">主程序与系统后台助手分别运行；监控和灾备由一个持有者执行</text>',
        card(160, 126, 500, 112, "GitGatto 主程序", ["SwiftUI · AppKit · WebKit", "界面状态与用户操作"], "panel-blue"),
        card(860, 126, 500, 112, "GitGattoMonitor 后台助手", ["SMAppService · LaunchAgent", "主程序退出后接手已开启的监控与灾备"], "panel-purple"),
        arrow(410, 246, 590, 290), arrow(1110, 246, 930, 290),
        card(340, 298, 840, 100, "监控任务所有权", ["foreground.lock / runtime.lock", "交接时先取消并等待旧任务结束，再释放运行锁"], "panel-accent"),
        '<text class="section" x="64" y="450">主程序运行或后台接手时持续执行</text>',
    ]
    xs = [64, 422, 780, 1138]
    monitoring = [
        ("仓库变化与活动", ["文件事件合并 · 增量刷新", "Git 状态 · 活动点阵"]),
        ("灾备与仓库守卫", ["定时 · 重大改动 · 外部异常", "内容落盘 → 完成标记 → 三份轮换"]),
        ("远端与 Actions", ["上游状态 · 检查结果", "按已开启通道读取"]),
        ("目标状态", ["读取待完成条件", "发布与安装仍需单独确认"]),
    ]
    for x, (title, details) in zip(xs, monitoring):
        body.append(card(x, 478, 318, 132, title, details, "panel-green"))
    body.extend([
        '<path class="connector" d="M760 406 V462 H223 V470 M760 462 H581 V470 M760 462 H939 V470 M939 462 H1297 V470"/>',
        '<text class="section" x="64" y="680">主程序中的交互功能</text>',
    ])
    interactive = [
        ("Git / GitHub", ["工作区 · PR · Issue · 历史", "GitCommandRunner · GitHubService"]),
        ("目标 / 编排 / 回归", ["交付条件 · Hunk 分组提交", "独立 worktree · git bisect"]),
        ("Agent 执行通道", ["项目 · 翻译 · 搜索 · 安装", "CLI / OpenAI 兼容 API / DeepSeek"]),
        ("应用与开发工具", ["下载 · 安装 · 配置 · 验证", "三路队列 · Homebrew 写入串行"]),
    ]
    for x, (title, details) in zip(xs, interactive):
        body.append(card(x, 708, 318, 132, title, details, "panel-blue"))
    body.extend([
        '<text class="section" x="64" y="902">系统、存储与发布边界</text>',
        card(64, 930, 438, 124, "本地数据", ["Git 仓库 · Git bundle · 未提交文件", "目标 · 记录 · 译文 · 三份恢复点"]),
        card(541, 930, 438, 124, "网络与凭据", ["GitHub / CLI / 配置的模型服务", "API 密钥存系统钥匙串"]),
        card(1018, 930, 438, 124, "版本更新", ["Sparkle · Developer ID · EdDSA", "Appcast · DMG · 公证单独申请"]),
    ])
    return base_svg(width, height, "GitGatto 系统架构", "前后台进程、监控任务交接、灾备、应用交互、存储与外部服务。", "\n".join(body))


def flow_diagram(
    title: str,
    description: str,
    steps: list[tuple[str, list[str]]],
    width: int = 1520,
    height: int = 400,
) -> str:
    body = [
        f'<text class="title" x="64" y="58">{html.escape(title)}</text>',
        f'<text class="detail" x="64" y="84">{html.escape(description)}</text>',
    ]
    count = len(steps)
    margin = 64
    gap = 46
    card_w = (width - 2 * margin - (count - 1) * gap) / count
    y, card_h = 150, 132
    for index, (name, details) in enumerate(steps):
        x = margin + index * (card_w + gap)
        css = "panel-accent" if index == count - 1 else "panel"
        body.append(card(x, y, card_w, card_h, name, details, css))
        body.append(f'<text class="badge" x="{x + 16}" y="{y + 24}">{index + 1:02d}</text>')
        if index < count - 1:
            body.append(arrow(x + card_w + 9, y + card_h / 2, x + card_w + gap - 9, y + card_h / 2, accent=True))
    return base_svg(width, height, title, description, "\n".join(body))


def recovery() -> str:
    steps = [
        ("触发", ["文件事件 · 定时 · 手动"]),
        ("检查", ["Git 状态与内容指纹"]),
        ("数据落盘", ["bundle · 文件 · 清单"]),
        ("完成标记", ["标记落盘后发布目录"]),
        ("轮换", ["每个仓库最多三份"]),
        ("恢复", ["还原为新的仓库副本"]),
    ]
    return flow_diagram("灾备与恢复流程", "定时与重大改动备份跳过无变化内容；新恢复点落盘后才轮换旧备份", steps, height=420)


def agent_flow() -> str:
    steps = [
        ("选择操作", ["当前仓库与明确任务"]),
        ("读取证据", ["分支 · Diff · 错误"]),
        ("Agent 执行", ["CLI / API · 独立通道"]),
        ("重新读取", ["Git · GitHub · 文件系统"]),
        ("显示结果", ["远端写入仍需确认"]),
    ]
    return flow_diagram("Agent 执行闭环", "Agent 的文字输出不是成功依据", steps)


def release_flow() -> str:
    steps = [
        ("版本标签", ["版本与构建号"]),
        ("测试构建", ["通用架构应用"]),
        ("Developer ID", ["签名与嵌套组件"]),
        ("DMG + Appcast", ["SHA-256 · EdDSA"]),
        ("GitHub Release", ["安装包与版本说明"]),
        ("独立公证", ["Notary · Staple · Gatekeeper"]),
    ]
    return flow_diagram("构建与发布流程", "公证是独立门禁，只有验证通过后才标记为已公证", steps, height=420)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=Path("docs/media"))
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    diagrams = {
        "roadmap.svg": roadmap(),
        "architecture-overview.svg": architecture(),
        "agent-flow.svg": agent_flow(),
        "recovery-flow.svg": recovery(),
        "release-flow.svg": release_flow(),
    }
    for name, content in diagrams.items():
        path = args.output_dir / name
        path.write_text(content, encoding="utf-8")
        print(f"Wrote {path}")


if __name__ == "__main__":
    main()
