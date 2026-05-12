from __future__ import annotations

import html
import re
from pathlib import Path

from jinja2 import Environment, FileSystemLoader, select_autoescape


class HtmlRenderer:
    def __init__(self, templates_dir: Path | str):
        self.env = Environment(loader=FileSystemLoader(str(templates_dir)), autoescape=select_autoescape(["html", "xml"]))

    def render(self, markdown_text: str, title: str) -> str:
        body = self.markdown_to_safe_html(markdown_text)
        template = self.env.get_template("guide_template.html")
        return template.render(title=title, body=body)

    @staticmethod
    def markdown_to_safe_html(markdown_text: str) -> str:
        lines = markdown_text.splitlines()
        html_lines: list[str] = []
        in_ul = False
        in_ol = False
        for raw in lines:
            line = raw.strip()
            if not line:
                if in_ul:
                    html_lines.append("</ul>")
                    in_ul = False
                if in_ol:
                    html_lines.append("</ol>")
                    in_ol = False
                continue
            safe = html.escape(line)
            if line.startswith("# "):
                html_lines.append(f"<h1>{html.escape(line[2:])}</h1>")
            elif line.startswith("## "):
                html_lines.append(f"<h2>{html.escape(line[3:])}</h2>")
            elif line.startswith("### "):
                html_lines.append(f"<h3>{html.escape(line[4:])}</h3>")
            elif line.startswith("- "):
                if not in_ul:
                    html_lines.append("<ul>")
                    in_ul = True
                html_lines.append(f"<li>{html.escape(line[2:])}</li>")
            elif re.match(r"^\d+\.\s+", line):
                if not in_ol:
                    html_lines.append("<ol>")
                    in_ol = True
                html_lines.append(f"<li>{html.escape(re.sub(r'^\\d+\\.\\s+', '', line))}</li>")
            else:
                if in_ul:
                    html_lines.append("</ul>")
                    in_ul = False
                if in_ol:
                    html_lines.append("</ol>")
                    in_ol = False
                html_lines.append(f"<p>{safe}</p>")
        if in_ul:
            html_lines.append("</ul>")
        if in_ol:
            html_lines.append("</ol>")
        return "\n".join(html_lines).replace("&lt;script", "&lt;blocked-script")
