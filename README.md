# DetoxPlayer

Личный музыкальный плеер: сервер на Windows в Docker и будущие Flutter-клиенты для Android, iOS и web.

Реализован первый этап: локальная веб-админка, несколько музыкальных папок, фоновая индексация MP3, просмотр каталога и папок, поиск, пересканирование и полная переиндексация. Есть выдача и отзыв ключей устройств; клиентский API для них появится следующим этапом.

## Запуск на Windows

Docker Desktop должен работать в режиме Linux containers. В PowerShell из папки репозитория:

```powershell
Copy-Item .env.example .env
docker compose up -d --build
docker compose exec server python -m app.secret
```

Откройте [localhost:8080](http://localhost:8080), войдите с полученным административным секретом и добавьте `/sources/music` в библиотеку. По умолчанию это `F:/Music`, подключённая только для чтения. Музыка не копируется в контейнер.

[Подробная инструкция для Windows и дополнительных дисков](docs/windows-setup.md).

## Структура

- `server/` — FastAPI, SQLite, индексатор Mutagen и веб-админка без сборки JavaScript.
- `compose.yaml` — локальный Docker-сервер с постоянным томом данных.
- `deploy/` — дополнительные настройки окружения разработки.
- `docs/` — архитектура и инструкции.
- `.github/workflows/server.yml` — тесты и проверка Docker-сборки.

Flutter-приложение, воспроизведение, обложки и внешний HTTPS-доступ ещё не реализованы. Требования: [архитектура](docs/architecture.md). Для будущей iOS-сборки необходимы macOS и Xcode.

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
