# DetoxPlayer

Личный музыкальный плеер: сервер на Windows в Docker и Flutter-клиент для Android/iOS. Web входит в roadmap.

Реализованы локальная веб-админка, несколько музыкальных папок, фоновая индексация MP3, каталог, поиск и переиндексация. Отдельный клиентский API поддерживает ключи устройств, web-сессии, выдачу MP3 с Range/HEAD и обложки. Flutter-клиент поддерживает подключение, каталог, альбомы, исполнителей, воспроизведение, очередь, shuffle/repeat, кэш метаданных, локальные плейлисты, мобильные офлайн-загрузки и журнал диагностики. [Сверенный roadmap и границы проверок](docs/roadmap.md).

## Запуск на Windows

Docker Desktop должен работать в режиме Linux containers. В PowerShell из папки репозитория:

```powershell
Copy-Item .env.example .env
docker compose up -d --build
docker compose exec server python -m app.secret
```

Откройте [localhost:8080](http://localhost:8080), войдите с полученным административным секретом и добавьте `/sources/music` в библиотеку. По умолчанию это `F:/Music`, подключённая только для чтения. Музыка не копируется в контейнер.

[Подробная инструкция для Windows и дополнительных дисков](docs/windows-setup.md).

Клиентский API работает на [localhost:8081](http://localhost:8081/health); административных маршрутов в нём нет. Базовый Compose публикует оба порта только локально. Для подключения нужен ключ устройства из админки. [Контракт API и примеры](docs/client-api.md). Внешний HTTPS-доступ через Caddy реализован отдельной конфигурацией: [инструкция](docs/external-access.md). Проверка публичного HTTPS на Android отмечена в [README приложения](app/README.md); отдельное подтверждение проверки через другую сеть ещё нужно зафиксировать.

## Структура

- `server/` — FastAPI, SQLite, индексатор Mutagen, клиентский API и веб-админка без сборки JavaScript.
- `compose.yaml` — локальный Docker-сервер с постоянным томом данных.
- `deploy/` — дополнительные настройки окружения разработки.
- `docs/` — архитектура и инструкции.
- `.github/workflows/server.yml` — тесты и проверка Docker-сборки.

Плейлисты и офлайн-загрузки реализованы; требуется проверка на реальных телефонах по [сценариям](docs/mobile-validation.md). Web-адаптация, Android Auto и CarPlay ещё не завершены. Требования: [архитектура](docs/architecture.md), актуальное состояние: [roadmap](docs/roadmap.md). iOS собирается на macOS в Xcode.

## Проверка сервера

```sh
python -m venv .venv
# Linux/macOS; на Windows: .venv\Scripts\Activate.ps1
. .venv/bin/activate
pip install -r server/requirements-dev.txt
python -m pytest server/tests -q
```

Для локальной разработки без контейнера задайте `DATA_DIR` и `SOURCE_ROOTS` (несколько путей разделяются `;`), затем из `server/` запустите `uvicorn app.main:create_app --factory --host 127.0.0.1 --port 8080`. Для штатного запуска используйте Docker Compose.

Музыка, база, скачанные треки, локальные настройки и секреты не хранятся в Git.
