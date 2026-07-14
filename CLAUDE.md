# terpevshie.ru

Статический сайт музыкальной группы «потерпевшие». Шаблоны Jinja2 →
`minijinja-cli` → минифицированный HTML → rsync на сервер. Ни фреймворка,
ни node-проекта, ни пакетного менеджера — только шаблоны и три скрипта.

## Команды

- `make run` — dev-сервер (Go, `dev_server/`): рендерит `.jinja2` на лету,
  live-reload через SSE, отдаёт статику из `pages/`. Порт в логе при старте.
- `make build` — `scripts/build.sh`: rsync `pages/` → `dist/`, рендер каждого
  `.jinja2` в `.html`, минификация через `npx html-minifier-terser`, удаление
  исходников и `common/jinja/` из `dist/`.
- `make test` — сборка + `go test` на dev-сервере + `scripts/check_dist.py`:
  проверяет собранный `dist/` (битые локальные ссылки, ровно один экземпляр
  каждого метатега, валидность JSON-LD, sitemap не разъехался со страницами).
- `make deploy` — прогоняет `make test` и rsync `dist/` на
  `$SSH_TARGET:$REMOTE_DIR` (см. `.env`, пример в `.env.example`).

Зависимости: `minijinja-cli`, Go, `npx`, `rsync`, `python3` (только для тестов).

## Структура

- `pages/` — единственный источник правды. Путь файла = URL:
  `pages/games/bus/index.jinja2` → `/games/bus/`. Ассеты (webp, mp3) лежат
  рядом со своей страницей и копируются как есть.
- `pages/common/jinja/` — шаблоны, не попадают в сборку:
  - `layouts/base.jinja2` — голый html-скелет, блоки `title/head/style/content/script`.
  - `layouts/fog.jinja2` — основной лейаут: og-теги, шрифт Old Standard TT,
    фон Vanta.FOG (three.js с CDN), навбар, общие стили. От него наследуются
    почти все страницы.
  - `components/` — `navbar`, `links`. Компонент = два макроса: `html()` и
    `styles()`; лейаут/страница вызывает оба (разметку в `content`, стили
    внутри `<style>`).
  - `includes/` — фрагменты для `{% include %}`: favicon-теги, аналитика,
    css-ресеты (`simple_reset.css`, `view_transition.css`).
- `dist/` — артефакт сборки, коммитится, руками не редактируется.
- `dev_server/` — Go-сервер для разработки, трогать только при работе над
  самим dev-режимом.

## Соглашения

- Стили инлайновые, в `{% block extra_styles %}` внутри `<style>` в конце
  страницы. Отдельных `.css`-файлов на страницу нет — так всё уезжает в один
  минифицированный HTML.
- Переменные лейаута задаются через `{% set %}` в `fog.jinja2`
  (`telegram_link`, `sm_breakpoint = 600`) и доступны наследникам, в том числе
  в media-query: `@media (max-width: {{ sm_breakpoint }}px)`.
- Флаг `{% set exclude_navbar = true %}` в странице убирает навбар.
- Тексты и `lang="ru"` — сайт русскоязычный, новые страницы тоже.
- `pages/experimental/` — черновики, живут по тем же правилам.

Новая страница = один `index.jinja2` в новой директории, `extends
'.../layouts/fog.jinja2'`, блоки `main` и `extra_styles`. Больше ничего
регистрировать не нужно: og-теги, canonical и попадание в sitemap она
получит автоматически.

## Данные и SEO

- `pages/common/jinja/data.yaml` — единый контекст всех шаблонов (`site_url`,
  `telegram_link`, `sm_breakpoint`, `band`, `releases`). Передаётся в
  `minijinja-cli` вторым аргументом из `build.sh` и dev-сервера.
- `page_path` (канонический URL страницы) вычисляется из пути файла и
  передаётся через `-D`. На нём держатся `og:url` и `canonical`.
- Дефолтные метатеги — в `layouts/base.jinja2`; страница переопределяет их
  через `{% set og_title %}` / `{% set og_description %}`, `fog.jinja2`
  подтягивает через `{{ super() }}`.
- `components/schema.jinja2` — JSON-LD: `music_group()` на главной,
  `music_album()` на страницах релизов.
- `sitemap.xml` генерируется в конце `build.sh` из фактически собранных
  страниц (`404` и `experimental/` исключены), `robots.txt` лежит статикой
  в `pages/`.
- `scripts/check_dist.py` держит всё это в узде — при добавлении страницы,
  которая не должна индексироваться, правь списки `RAW_PAGES` / `NOINDEX`
  там же.
