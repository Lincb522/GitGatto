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
        ("0.14", ["Git + GitHub", "基础流程"], "panel-green"),
        ("0.15–0.16", ["专业工作区", "更新链路"], "panel-green"),
        ("0.17–0.18.10", ["Agent · 内容预览", "工具安装"], "panel-green"),
        ("0.18.11", ["目标驱动交付", "完整发布"], "panel-green"),
        ("0.18.12", ["回归取证", "仓库灾备"], "panel-accent"),
    ]
    planned = [
        ("NEXT 01", ["恢复证据", "多仓库值守"]),
        ("NEXT 02", ["可复用 Agent", "处理方案"]),
        ("NEXT 03", ["签名 · 公证", "更新闭环"]),
    ]
    body = [
        '<text class="title" x="64" y="58">GitGatto 路线图</text>',
        '<text class="detail" x="64" y="84">已实现版本按 CHANGELOG 记录；虚线阶段为下一步计划</text>',
        '<text class="section" x="64" y="138">已实现</text>',
        '<line class="connector-accent" x1="142" y1="222" x2="1378" y2="222"/>',
    ]
    start_x, card_w, gap = 62, 250, 38
    for index, (version, details, css) in enumerate(stages):
        x = start_x + index * (card_w + gap)
        body.append(card(x, 166, card_w, 112, version, details, css))
        body.append(f'<circle class="dot" cx="{x + card_w / 2}" cy="222" r="6"/>')

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
    width, height = 1600, 1010
    columns = [145, 515, 885, 1255]
    card_w = 250
    body = [
        '<text class="title" x="64" y="58">GitGatto 系统架构</text>',
        '<text class="detail" x="64" y="84">界面状态、任务运行时、能力适配与系统边界</text>',
    ]
    headers = ["界面与状态", "任务运行时", "能力适配", "系统与远端"]
    for x, header in zip(columns, headers):
        body.append(text_block(x + card_w / 2, 132, [header], "section"))
        body.append(f'<rect class="lane" x="{x - 24}" y="154" width="{card_w + 48}" height="740" rx="22"/>')

    ui_cards = [
        ("SwiftUI / AppKit", ["窗口 · 导航 · 主题"]),
        ("WorkspaceViewModel", ["仓库与工作区"]),
        ("Marketplace", ["应用仓库"]),
        ("DeveloperTools", ["工具与队列"]),
    ]
    runtime_cards = [
        ("Project Goals", ["交付与发布条件"]),
        ("Regression", ["worktree + git bisect"]),
        ("Recovery", ["三代滚动恢复点"]),
        ("Downloads", ["下载与安装"]),
        ("Global Errors", ["原文 · 归一 · 脱敏"]),
    ]
    adapter_cards = [
        ("Git Service", ["GitCommandRunner"]),
        ("GitHub Service", ["API · Release"]),
        ("Agent Lanes", ["仓库 · 翻译 · 安装"]),
        ("Tool Services", ["探测 · Brew · 授权"]),
        ("Sparkle / Media", ["更新 · 文档 · 媒体"]),
    ]
    external_cards = [
        ("Local Repositories", ["Git · SSH"]),
        ("GitHub", ["CLI · API · Releases"]),
        ("Agent CLIs", ["Codex · Claude · Gemini"]),
        ("Homebrew", ["开发工具与运行库"]),
        ("Local Persistence", ["设置 · 记录 · 译文 · 备份"]),
    ]
    groups = [ui_cards, runtime_cards, adapter_cards, external_cards]
    styles = ["panel-blue", "panel-purple", "panel-green", "panel-accent"]
    positions: list[list[tuple[float, float]]] = []
    for column_index, (x, entries, css) in enumerate(zip(columns, groups, styles)):
        group_positions = []
        top = 188 if len(entries) == 5 else 244
        step = 132
        for row, (title, details) in enumerate(entries):
            y = top + row * step
            body.append(card(x, y, card_w, 92, title, details, css))
            group_positions.append((x, y))
        positions.append(group_positions)

    # The overview shows dependency direction between layers. Exact many-to-many
    # service relationships stay in the owning prose below the diagram.
    for index in range(len(columns) - 1):
        body.append(
            arrow(
                columns[index] + card_w + 8,
                174,
                columns[index + 1] - 8,
                174,
                accent=(index == 1),
            )
        )

    body.extend([
        '<rect class="panel" x="121" y="920" width="1358" height="54" rx="16"/>',
        '<text class="detail" x="800" y="952" text-anchor="middle">所有写操作绑定明确仓库或受控目录；Agent 输出必须回到 Git、GitHub、可执行文件或文件系统重新验证</text>',
    ])
    return base_svg(width, height, "GitGatto 系统架构", "GitGatto 的状态所有权、运行时、适配器和外部边界。", "\n".join(body))


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
        ("写入", ["暂存目录 · bundle · 文件"]),
        ("安装", ["清单完成后原子移动"]),
        ("轮换", ["每个仓库最多三份"]),
        ("恢复", ["还原为新的仓库副本"]),
    ]
    return flow_diagram("灾备与恢复流程", "空工作区或相同内容不会重复生成恢复点", steps, height=420)


def agent_flow() -> str:
    steps = [
        ("选择操作", ["当前仓库与明确任务"]),
        ("读取证据", ["分支 · Diff · 错误"]),
        ("Agent 执行", ["限定目录与独立通道"]),
        ("重新读取", ["Git · GitHub · 文件系统"]),
        ("显示结果", ["远端写入仍需确认"]),
    ]
    return flow_diagram("Agent 执行闭环", "Agent 的文字输出不是成功依据", steps)


def release_flow() -> str:
    steps = [
        ("版本标签", ["版本与构建号"]),
        ("测试构建", ["通用架构应用"]),
        ("Developer ID", ["签名与嵌套组件"]),
        ("DMG + Appcast", ["校验值与更新源"]),
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
