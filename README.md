# DetoxPlayer

Личный музыкальный плеер: сервер на Windows в Docker и будущие Flutter-клиенты для Android, iOS и web.

Реализованы локальная веб-админка, несколько музыкальных папок, фоновая индексация MP3, каталог, поиск и переиндексация. Отдельный клиентский API поддерживает ключи устройств, web-сессии, выдачу MP3 с Range/HEAD и обложки. Flutter-клиент пока не реализован.

## Запуск на Windows

Docker Desktop должен работать в режиме Linux containers. В PowerShell из папки репозитория:

```powershell
Copy-Item .env.example .env
docker compose up -d --build
docker compose exec server python -m app.secret
```

Откройте [localhost:8080](http://localhost:8080), войдите с полученным административным секретом и добавьте `/sources/music` в библиотеку. По умолчанию это `F:/Music`, подключённая только для чтения. Музыка не копируется в контейнер.

[Подробная инструкция для Windows и дополнительных дисков](docs/windows-setup.md).

Клиентский API работает на [localhost:8081](http://localhost:8081/health); административных маршрутов в нём нет. Оба порта пока доступны только на этом компьютере. Для подключения нужен ключ устройства из админки. [Контракт API и примеры](docs/client-api.md). Внешний HTTPS-доступ через Caddy описан в [инструкции](docs/external-access.md) (не проверен из внешней сети).

## Структура

- `server/` — FastAPI, SQLite, индексатор Mutagen, клиентский API и веб-админка без сборки JavaScript.
- `compose.yaml` — локальный Docker-сервер с постоянным томом данных.
- `deploy/` — дополнительные настройки окружения разработки.
- `docs/` — архитектура и инструкции.
- `.github/workflows/server.yml` — тесты и проверка Docker-сборки.

Flutter-приложение с интерфейсом воспроизведения и внешний HTTPS-доступ ещё не реализованы. Серверная выдача аудио и обложек готова. Требования: [архитектура](docs/architecture.md). Для будущей iOS-сборки необходимы macOS и Xcode.

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
