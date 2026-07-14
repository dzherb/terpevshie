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
- `make deploy` — rsync `dist/` на `$SSH_TARGET:$REMOTE_DIR` (см. `.env`,
  пример в `.env.example`).

Зависимости: `minijinja-cli`, Go, `npx`, `rsync`.

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
регистрировать не нужно.
