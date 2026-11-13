# Календарь звонков


[![hexlet-check](https://github.com/ikurennyi/ai-for-developers-project-386/actions/workflows/hexlet-check.yml/badge.svg)](https://github.com/ikurennyi/ai-for-developers-project-386/actions)

Разработайте совместно с ИИ сервис для бронирования календаря

Учебный проект Хекслета: https://ru.hexlet.io/programs/ai-for-developers
Как это должно работать: https://files.hexlet.app/a/2ipc5m

## Первый шаг: каркас приложения

- [Исходные требования шага](1-step.md).
- [Утверждённая спецификация](https://github.com/ikurennyi/ai-for-developers-project-386/issues/1).
- [Закреплённые инструменты](docs/toolchain.md), [локальная приёмка и открытые критерии](docs/acceptance.md).

Главная страница рассказывает о сервисе; Book a meeting открывает список
опубликованных типов встреч с сервера. Публичная ссылка открывает календарь:
можно выбрать свободный интервал Europe/Berlin, заполнить данные гостя и явно
подтвердить бронирование. Общая занятость атомарно защищена PostgreSQL.
Безопасный вход администратора реализован; управление бронированиями пока отсутствует.
Локальный прогон не подтверждает зелёный GitHub Actions: внешний CI и итоговый
review пока не подтверждены, родительская спецификация не объявляется выполненной.

## Стек

- Rails API / Ruby, PostgreSQL; Vue 3, Router, TypeScript и Element Plus.
- TypeSpec → OpenAPI 3.0 → generated Fetch SDK; RSpec и Vitest (включая Chromium).
- mise, Docker Compose, pitchfork, hk и commitlint.

## Установка

Нужны [mise 2026.11.6 и закреплённые инструменты](docs/toolchain.md), работающий
Docker Engine и системные зависимости сборки Ruby/pg (libpq, компилятор).
mise устанавливает Docker CLI, но не Docker Engine/VM.

```bash
git clone https://github.com/ikurennyi/ai-for-developers-project-386.git
cd ai-for-developers-project-386
mise trust mise.toml
mise install
mise exec -- gem install bundler -v 4.0.22 --no-document
mise run install
```

`install` использует frozen Bundler и отдельный `npm ci` в `contracts/`,
`frontend/`, `tooling/`, затем устанавливает Chromium. На Linux нужны также
системные библиотеки браузера:

```sh
mise exec -- node frontend/node_modules/playwright/cli.js install --with-deps chromium
```

## Использование

Для запуска приложения целиком в контейнерах из чистого checkout, с HTTPS,
миграциями и постоянной БД: [Docker application](docs/docker.md).

Для каждого checkout/worktree создайте отдельную игнорируемую конфигурацию.
Не перезаписывайте существующий `mise.local.toml`: шаблон меняет пароль.

```sh
umask 077
mise exec -- ruby scripts/services.rb dev:env > mise.local.toml
# Выберите три свободных разных порта; при смене POSTGRES_PORT обновите оба URL.
mise trust mise.local.toml
mise run dev:validate
mise run db:up
mise run db:prepare
mise run dev:start
mise run dev:status
```

Откройте `http://127.0.0.1:<FRONTEND_PORT>/`: страница показывает
`API healthy: ok`, полученный через SDK и Vite proxy от Rails
`GET /api/v1/health`. Health не доказывает подключение БД; smoke проверяет его отдельно.
`dev:start` также сам подготавливает БД. Повторный start при занятых портах — ошибка.

Первичная подготовка БД создаёт опубликованные 15- и 30-минутные типы встреч.
Повторный `db:seed` (из `backend/`: `mise exec -- bundle exec rails db:seed`)
сохраняет изменения названий, описаний, длительности, адресов и публикации.
Начальные предложения распознаются по постоянному служебному ключу, не по адресу.
Данные и технические UUID хранятся в PostgreSQL, а не в памяти приложения.
Публичный `GET /api/v1/meeting-types` возвращает только опубликованные предложения;
пустой список отображается как “No meeting types available”.

Календарь доступен по `/book/<slug>` и читает через generated SDK
`GET /api/v1/meeting-types/<slug>/availability`. Скрытые и несуществующие адреса
одинаково недоступны. Окно — сегодня и следующие 13 дат Europe/Berlin;
расписание пн–пт 09:00–18:00, шаг стартов 15 минут.
Выбор и Continue ничего не записывают и не резервируют; Confirm booking сохраняет
бронирование и показывает данные встречи без обещаний отправки письма.
Правила общей занятости: [calendar](docs/calendar.md);
API подтверждения и границы следующих этапов: [confirmation](docs/booking-confirmation.md).

```sh
mise run dev:stop
```

Остановка сохраняет данные и затрагивает только этот worktree. Идентификаторы,
переменные, диагностика и смена настроек описаны в [dev-services](docs/dev-services.md).

## Проверки и hooks

Настройка единственного администратора, ограничения попыток входа и серверная
команда смены пароля с отзывом всех сессий: [Administrator access](docs/admin-authentication.md).

```sh
mise run check
mise run hooks:install
mise run hooks:test
mise run commits:test
mise run ci:validate
```

`check` не требует dev-сервисов или локальной конфигурации: он запускает все
контрактные проверки, lint, форматирование, типы, RSpec, Vitest/jsdom,
настоящий Chromium smoke и production build. Docker должен работать.
Проверки не исправляют и не индексируют исходники.

- [Все отдельные команды и failure probes](docs/checks.md).
- [Chromium, изоляция и cleanup](docs/chromium-smoke.md).
- [Hooks, commit ranges и CI](docs/hooks-and-ci.md). Установка hooks явная,
  локальная для репозитория; linked worktree могут разделять hooks.
- [Версионирование и release PR](docs/releases.md): единая версия приложения,
  настройка отдельного токена maintainer-ом и ещё не подтверждённые внешние шаги.
- Коммиты: Conventional Commits, например `docs: clarify local setup`;
  ветки: `docs/short-description`, PR titles — также Conventional Commits.

Приложение проверяется отдельным `.github/workflows/application-check.yml` на
push/PR той же командой `mise run check`. Push/PR требуют отдельного разрешения;
результаты внешнего CI не выводятся из локального успеха.

---

<details>
<summary>Автоматические тесты Хекслета</summary>

Тесты запускаются на каждый коммит. За запуск отвечает файл `.github/workflows/hexlet-check.yml` — не удаляйте и не переименовывайте ни его, ни репозиторий.

</details>

## О Хекслете

[Хекслет](https://ru.hexlet.io/) — школа программирования: авторские программы обучения с практикой, поддержкой наставников и реальными проектами, которые остаются в резюме. Этот репозиторий — один из таких проектов.
