#!/usr/bin/env python3
"""Refresh static client feedback locations for the notice lab; never invokes app APIs."""
import json
import re
from pathlib import Path

ios = Path(__file__).resolve().parents[1]
app = ios / "VeraBot"
rules = [
    ("确认 / 弹窗", re.compile(r"\.alert\(|\.confirmationDialog\(")),
    ("加载 / 空状态", re.compile(r"ProgressView\(|ContentUnavailableView|BotLoadingView\(|BotConnectionView\(")),
    ("提示 / 错误", re.compile(r"\b(?:errorText|errorMessage|infoText|missingNotice|healthError|serverError|inputError|message|error|connectionIssue|suggestionErrors)\b.*(?:=|Text\()|Text\([^)]*(?:errorText|message|error)|NSLocalizedDescriptionKey|return \"|throw .*\(")),
    ("状态 / 反馈", re.compile(r"case \"(?:pending|done|cancelled|expired|failed|unknown)\"|reviewStatus|state = \.(?:preparing|uploading|ready|failed)|\.hapticFeedback\(|UIPasteboard|\.banner|enum .*State|case .*thinking|case .*warning")),
]
records = []
for root in [app, ios / "Packages/VeraBotKit/Sources"]:
    for path in sorted(root.rglob("*.swift")):
        if "NoticeLab" in path.parts or "Notices" in path.parts:
            continue
        for number, line in enumerate(path.read_text().splitlines(), 1):
            stripped = line.strip()
            if not stripped or stripped.startswith("//"):
                continue
            kinds = [kind for kind, pattern in rules if pattern.search(stripped)]
            if kinds:
                records.append({"file": str(path.relative_to(ios)), "line": number,
                                "kinds": kinds, "excerpt": stripped[:500]})
output = app / "Features/Settings/NoticeLab/NoticeSourceIndex.json"
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps({"scope": "iOS 客户端视图、状态模型、服务与本地 Package；静态匹配索引，动态 API 错误由对应失败场景覆盖。",
                              "records": records}, ensure_ascii=False, indent=2) + "\n")
print(f"Indexed {len(records)} locations across {len(set(r['file'] for r in records))} files")
