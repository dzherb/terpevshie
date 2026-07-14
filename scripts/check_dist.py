#!/usr/bin/env python3
"""Проверки собранного dist/. Запускается после build.sh: make test

Ловит регрессии, которые молча доезжают до прода: битые ссылки на файлы,
пропавшие или задвоившиеся метатеги, невалидный JSON-LD, sitemap, разъехавшийся
со списком страниц.
"""

import json
import sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path

DIST = Path(__file__).resolve().parent.parent / "dist"
SITE_URL = "https://terpevshie.ru"

META_TAGS = ("og:url", "og:image", "og:title", "og:description", "description", "canonical")

# Сырые HTML-полотна: не наследуют лейауты, метатегов у них нет.
# Когда посадим их на base.jinja2 — убрать отсюда, тест напомнит.
RAW_PAGES = {"/games/forest", "/games/mosqito", "/games/warmix"}

# Не индексируются: не должны попадать в sitemap.
NOINDEX = {"/404.html"}

errors = []


def check(ok, msg):
    if not ok:
        errors.append(msg)


class Page(HTMLParser):
    """Собирает то, что нас интересует: метатеги, локальные ссылки, JSON-LD."""

    def __init__(self):
        super().__init__()
        self.meta = {}  # og:url / description / canonical → список значений
        self.links = []  # локальные href/src, которые должны существовать
        self.ld = []
        self._in_ld = False

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)

        if tag == "meta" and a.get("property", "").startswith("og:"):
            self.meta.setdefault(a["property"], []).append(a.get("content", ""))
        elif tag == "meta" and a.get("name") == "description":
            self.meta.setdefault("description", []).append(a.get("content", ""))
        elif tag == "link" and a.get("rel") == "canonical":
            self.meta.setdefault("canonical", []).append(a.get("href", ""))
        elif tag == "script" and a.get("type") == "application/ld+json":
            self._in_ld = True

        for attr in ("href", "src", "content"):
            url = a.get(attr, "")
            if attr == "content" and a.get("property") != "og:image":
                continue
            if url.startswith(SITE_URL):
                url = url[len(SITE_URL):]
            if url.startswith("/"):
                self.links.append(url)

    def handle_endtag(self, tag):
        if tag == "script":
            self._in_ld = False

    def handle_data(self, data):
        if self._in_ld:
            self.ld.append(data)


def resolve(url):
    """Существует ли /concerts, /common/images/logo.png и т.п. в dist?"""
    target = DIST / url.lstrip("/").split("?")[0].split("#")[0]
    return target.is_file() or (target / "index.html").is_file()


def page_url(html_file):
    """Канонический URL, как его считает build.sh:
    dist/index.html → /, dist/concerts/index.html → /concerts, dist/404.html → /404.html
    """
    rel = html_file.relative_to(DIST)
    if rel.name != "index.html":
        return "/" + str(rel)
    parent = str(rel.parent)
    return "/" if parent == "." else "/" + parent


def main():
    if not DIST.is_dir():
        check(False, "нет dist/ — сначала make build")
        return report()

    leftovers = list(DIST.rglob("*.jinja2")) + list(DIST.rglob("data.yaml"))
    check(not leftovers, f"исходники шаблонов утекли в dist: {leftovers}")

    html_files = sorted(DIST.rglob("*.html"))
    check(len(html_files) > 5, f"подозрительно мало страниц: {len(html_files)}")

    indexable = set()

    for f in html_files:
        url = page_url(f)
        page = Page()
        page.feed(f.read_text())

        for link in page.links:
            check(resolve(link), f"{url}: битая ссылка {link}")

        for block in page.ld:
            try:
                data = json.loads(block)
                check("@type" in data and "name" in data, f"{url}: JSON-LD без @type/name")
            except json.JSONDecodeError as e:
                check(False, f"{url}: JSON-LD не парсится — {e}")

        if url not in NOINDEX and not url.startswith("/experimental/"):
            indexable.add(url)

        # Сырые полотна индексируем, но метатегов с них не спрашиваем
        if url in RAW_PAGES:
            continue

        for tag in META_TAGS:
            values = page.meta.get(tag, [])
            check(len(values) == 1, f"{url}: ожидался ровно один {tag}, найдено {len(values)}")
            check(values and values[0].strip(), f"{url}: пустой {tag}")

        # og:url и canonical должны вести на саму страницу, а не на главную
        for tag in ("og:url", "canonical"):
            got = page.meta.get(tag, [""])[0]
            check(got == SITE_URL + url, f"{url}: {tag} = {got!r}, ожидалось {SITE_URL + url!r}")

    check_sitemap(indexable)
    report()


def check_sitemap(indexable):
    sitemap = DIST / "sitemap.xml"
    check((DIST / "robots.txt").is_file(), "нет robots.txt")
    if not sitemap.is_file():
        return check(False, "нет sitemap.xml")

    try:
        root = ET.fromstring(sitemap.read_text())
    except ET.ParseError as e:
        return check(False, f"sitemap.xml невалиден: {e}")

    ns = "{http://www.sitemaps.org/schemas/sitemap/0.9}"
    listed = {loc.text.removeprefix(SITE_URL) for loc in root.iter(f"{ns}loc")}

    check(
        listed == indexable,
        "sitemap разъехался со страницами: "
        f"лишние {sorted(listed - indexable)}, недостающие {sorted(indexable - listed)}",
    )


def report():
    if errors:
        print(f"❌ проверки не прошли ({len(errors)}):")
        for e in errors:
            print(f"  · {e}")
        sys.exit(1)
    print("✅ dist в порядке")


if __name__ == "__main__":
    main()
