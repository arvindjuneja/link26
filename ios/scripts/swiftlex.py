#!/usr/bin/env python3
"""Swift source lexing for the release guard (`ios/scripts/verify.sh`, C11).

Three of the SPEC §7 step 6 conditions are *lexical*, not textual, and a plain
`grep` gets every one of them wrong:

* **S1 · copy rule** (`SPEC-ADDENDUM.md` §2 S1) — "no string literal containing a
  letter in `Sources/Screens/**` or `Sources/Components/**` outside `#Preview`
  blocks and `accessibilityIdentifier` / `Image(systemName:)` / `Font.custom`
  arguments". A grep counts doc comments, `#Preview` fixtures and identifier
  arguments as copy, and cannot see a `#if SENTRY_QA` region at all.
* **B4/R12 · pay figures** — R12 says the `\\$\\s?\\d` alternative must run over
  *string literals*, never raw Swift, or every `$0` closure argument trips it. It
  must also not see `"\\($0.min)"`: an interpolation is code inside a literal, so
  this lexer strips interpolations before the guard reads the text.
* **§4.6 · colour and font names** — allowed only under `Design/`. The C11 ruling
  excludes comments, so the guard reads comment-stripped source (`code` mode) and
  reports comment hits from `comments` mode as a notice.

The lexer tracks string state, comment state, `#Preview` blocks, `#if SENTRY_QA`
regions and the stack of open call names. `#if SENTRY_QA` is excluded from S1 by
ruling — P1-9 moved `ComponentKit` behind that condition precisely because "S1's
grep cannot tell [a QA catalogue] apart, a compilation condition can".

Usage:
  swiftlex.py literals FILE...                 # file:line:TEXT, interpolations stripped
  swiftlex.py s1 --allow ALLOWFILE FILE...     # file:line:TEXT for every S1 violation
  swiftlex.py code FILE...                     # file:line:SOURCE with comments stripped
  swiftlex.py comments FILE...                 # file:line:TEXT of comment text only
"""

from __future__ import annotations

import re
import sys

# The call sites S1 names itself. `ios/scripts/s1-allow.txt` adds this project's own
# address accessors on top, one `call:` line each with its reason.
BUILTIN_ADDRESS_CALLS = ["accessibilityIdentifier", "systemName", "custom"]

IDENT_TAIL = re.compile(r"[A-Za-z0-9_.]+$")
LABEL_TAIL = re.compile(r"([A-Za-z0-9_]+)\s*:\s*$")
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", "\\": "\\", '"': '"', "'": "'"}


class Lit:
    __slots__ = ("path", "line", "text", "enclosing", "label", "suffix", "in_qa", "in_preview")

    def __init__(self, path, line, text, enclosing, label, suffix, in_qa, in_preview):
        self.path = path
        self.line = line
        self.text = text
        self.enclosing = enclosing
        self.label = label
        self.suffix = suffix
        self.in_qa = in_qa
        self.in_preview = in_preview


def strip_interpolations(text: str) -> str:
    """Remove `\\(...)` runs — code, not copy — keeping parens balanced."""
    out = []
    i = 0
    while i < len(text):
        if text.startswith("\\(", i):
            depth = 1
            i += 2
            while i < len(text) and depth:
                if text[i] == "(":
                    depth += 1
                elif text[i] == ")":
                    depth -= 1
                i += 1
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def unescape(text: str) -> str:
    """`\\n` is a separator, not the letter n — decode before the letter test."""
    out = []
    i = 0
    while i < len(text):
        if text[i] == "\\" and i + 1 < len(text):
            out.append(ESCAPES.get(text[i + 1], ""))
            i += 2
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


def scan(path: str):
    """Return (literals, code-lines, comment-lines) for one Swift file."""
    with open(path, "r", encoding="utf-8") as handle:
        source = handle.read()

    lits: list[Lit] = []
    code_lines: dict[int, list[str]] = {}
    comment_lines: dict[int, list[str]] = {}

    code: list[str] = []            # every non-comment, non-string character, in order
    call_stack: list[str] = []      # dotted names of the currently open calls
    i = 0
    line = 1
    block_comment = 0
    qa_depth = 0
    if_stack: list[bool] = []       # one entry per open `#if`; True = the SENTRY_QA one
    preview_stack: list[int] = []   # brace depth at each open `#Preview`
    brace = 0

    def emit(ch: str) -> None:
        code.append(ch)
        code_lines.setdefault(line, []).append(ch)

    while i < len(source):
        ch = source[i]

        if block_comment:
            if source.startswith("*/", i):
                block_comment -= 1
                i += 2
                continue
            if source.startswith("/*", i):
                block_comment += 1
                i += 2
                continue
            if ch == "\n":
                line += 1
            else:
                comment_lines.setdefault(line, []).append(ch)
            i += 1
            continue

        if source.startswith("//", i):
            while i < len(source) and source[i] != "\n":
                comment_lines.setdefault(line, []).append(source[i])
                i += 1
            continue

        if source.startswith("/*", i):
            block_comment = 1
            i += 2
            continue

        if ch == '"':
            multi = source.startswith('"""', i)
            start_line = line
            before = "".join(code)
            enclosing = call_stack[-1] if call_stack else ""
            label_match = LABEL_TAIL.search(before[-64:])
            label = label_match.group(1) if label_match else ""
            i += 3 if multi else 1
            buf = []
            while i < len(source):
                if not multi and source[i] == "\\" and i + 1 < len(source):
                    buf.append(source[i:i + 2])
                    i += 2
                    continue
                if (multi and source.startswith('"""', i)) or (not multi and source[i] == '"'):
                    i += 3 if multi else 1
                    break
                if source[i] == "\n":
                    line += 1
                buf.append(source[i])
                i += 1
            lits.append(
                Lit(path, start_line, "".join(buf), enclosing, label, source[i:i + 8],
                    qa_depth > 0, bool(preview_stack)))
            continue

        if source.startswith("#Preview", i):
            preview_stack.append(brace)
            emit("#")
            i += len("#Preview")
            continue

        if source.startswith("#if", i) and (i == 0 or source[i - 1] in "\n\t "):
            eol = source.find("\n", i)
            directive = source[i:eol if eol != -1 else len(source)]
            is_qa = "SENTRY_QA" in directive
            if_stack.append(is_qa)
            if is_qa:
                qa_depth += 1
            i = eol if eol != -1 else len(source)
            continue

        if source.startswith("#endif", i):
            if if_stack and if_stack.pop():
                qa_depth = max(0, qa_depth - 1)
            i += len("#endif")
            continue

        if ch == "(":
            name = IDENT_TAIL.search("".join(code[-96:]))
            call_stack.append(name.group(0).strip(".") if name else "")
        elif ch == ")":
            if call_stack:
                call_stack.pop()
        elif ch == "{":
            brace += 1
        elif ch == "}":
            brace -= 1
            while preview_stack and brace <= preview_stack[-1]:
                preview_stack.pop()

        if ch == "\n":
            line += 1
        else:
            emit(ch)
        i += 1

    return lits, code_lines, comment_lines


def load_allowlist(path: str):
    """`call:` names, `path:` file suffixes and `text:` literals, each with a reason."""
    calls, skip_paths, texts = list(BUILTIN_ADDRESS_CALLS), [], set()
    if not path:
        return calls, skip_paths, texts
    with open(path, "r", encoding="utf-8") as handle:
        for raw in handle:
            body = raw.split("  # ", 1)[0].strip()
            if not body or body.startswith("#"):
                continue
            for tag, sink in (("call:", calls), ("path:", skip_paths)):
                if body.startswith(tag):
                    sink.append(body[len(tag):].strip())
                    break
            else:
                if body.startswith("text:"):
                    texts.add(body[len("text:"):].strip())
    return calls, skip_paths, texts


def is_address(lit: Lit, calls: list[str]) -> bool:
    """The literal names something the machine looks up, not something a player reads."""
    if lit.label and lit.label in calls:
        return True
    name = lit.enclosing
    return bool(name) and any(name == c or name.endswith("." + c) for c in calls)


def is_dictionary_key(suffix: str) -> bool:
    """`["gap": …]` — a literal followed by `:` is a template placeholder name."""
    return suffix.lstrip().startswith(":")


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        sys.stderr.write(__doc__)
        return 2
    mode, rest = argv[1], argv[2:]
    allow_path = ""
    if rest[:1] == ["--allow"]:
        allow_path, rest = rest[1], rest[2:]
    calls, skip_paths, texts = load_allowlist(allow_path)

    for path in rest:
        if mode == "s1" and any(path.endswith(suffix) for suffix in skip_paths):
            continue
        lits, code_lines, comment_lines = scan(path)
        if mode in ("code", "comments"):
            lines = code_lines if mode == "code" else comment_lines
            for number in sorted(lines):
                print(f"{path}:{number}:{''.join(lines[number])}")
            continue
        for lit in lits:
            text = strip_interpolations(lit.text)
            if mode == "literals":
                if text.strip():
                    print(f"{path}:{lit.line}:{text}")
            elif mode == "s1":
                if lit.in_qa or lit.in_preview:
                    continue
                if is_address(lit, calls) or is_dictionary_key(lit.suffix):
                    continue
                if not any(c.isalpha() for c in unescape(text)):
                    continue
                if lit.text.strip() in texts:
                    continue
                print(f"{path}:{lit.line}:{lit.text}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
