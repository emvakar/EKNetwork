# Release Script

Улучшенный скрипт для автоматизации создания релизов EKNetwork с поддержкой major/minor/patch версионирования, автоматического коммита изменений и интеграции с GitLab.

## Быстрый старт

### Через Makefile (рекомендуется)

```bash
# Patch релиз (1.1.2 -> 1.1.3)
make patch

# Minor релиз (1.1.2 -> 1.2.0)
make minor

# Major релиз (1.1.2 -> 2.0.0)
make major

# Конкретная версия
make release TYPE=1.5.0

# Локальный коммит (без релиза)
make dev

# Коммит и пуш (без релиза)
make commit-push
```

### Напрямую через скрипт

```bash
./scripts/release.sh patch          # Patch релиз
./scripts/release.sh minor         # Minor релиз
./scripts/release.sh major         # Major релиз
./scripts/release.sh 1.5.0         # Конкретная версия
./scripts/release.sh dev            # Локальный коммит
./scripts/release.sh commit-push    # Коммит и пуш
```

## Режимы работы

### 1. Patch Release (`patch` или без аргумента)
Инкрементирует патч-версию (последнее число): `1.1.2` → `1.1.3`

```bash
make patch
```

### 2. Minor Release (`minor`)
Инкрементирует минорную версию: `1.1.2` → `1.2.0`

```bash
make minor
```

### 3. Major Release (`major`)
Инкрементирует мажорную версию: `1.1.2` → `2.0.0`

```bash
make major
```

### 4. Specific Version
Использование конкретной версии:

```bash
make release TYPE=1.5.0
# или
./scripts/release.sh 1.5.0
```

### 5. Dev Mode (`dev`)
Коммитит изменения локально без создания релиза:

```bash
make dev
```

### 6. Commit & Push (`commit-push`)
Коммитит и пушит изменения без создания релиза:

```bash
make commit-push
```

### 7. Debug Mode (`debug`)
Показывает всю информацию о текущем состоянии проекта без внесения изменений:

```bash
make debug
```

Показывает:
- Текущую версию из Version.swift
- Последний git тег
- Preview следующих версий (patch/minor/major)
- Незакоммиченные изменения
- Неотправленные коммиты
- Конфигурацию GitLab
- Последние коммиты и теги

## Что делает скрипт при релизе

1. **Проверяет** наличие git репозитория
2. **Коммитит незакоммиченные изменения** (если есть) с умным сообщением
3. **Определяет новую версию** на основе режима (patch/minor/major) или использует указанную
4. **Обновляет** `Sources/EKNetwork/Version.swift` с новой версией
5. **Коммитит** обновление версии
6. **Создает git тег** `vX.Y.Z` с аннотированным сообщением и changelog
7. **Пушит** коммиты и тег в удаленный репозиторий
8. **Создает релиз в GitLab** (если настроен GITLAB_TOKEN)

## GitLab Integration

Для автоматического создания релизов в GitLab необходимо:

1. **Получить GitLab Personal Access Token:**
   - Зайдите в GitLab Settings → Access Tokens
   - Создайте токен с правами `api`

2. **Установить переменные окружения:**

```bash
# В вашем ~/.zshrc или ~/.bashrc
export GITLAB_TOKEN="your_token_here"
export GITLAB_API_URL="https://gitlab.eskaria.com/api/v4"  # Опционально, автодетектится
```

Или для одноразового использования:

```bash
GITLAB_TOKEN="your_token_here" make patch
```

3. **Автоматическое определение:**
   Скрипт автоматически определяет GitLab URL из remote URL репозитория, если он содержит `gitlab` в названии.

## Генерация Changelog

Скрипт автоматически генерирует changelog из коммитов между предыдущим и текущим тегом:

```
## Changes in v1.1.3

- feat: Added user-agent support
- fix: Fixed retry logic
- docs: Updated README
```

Changelog включается в:
- Сообщение git тега
- Описание GitLab релиза

## Примеры использования

### Разработка

```bash
# Работаете над фичей, хотите закоммитить локально
make dev

# Закончили работу, хотите запушить изменения
make commit-push
```

### Создание релиза

```bash
# Исправление бага - patch релиз
make patch

# Добавление новой функции - minor релиз
make minor

# Breaking changes - major релиз
make major
```

### С GitLab токеном

```bash
GITLAB_TOKEN="glpat-xxxx" make patch
```

## Требования

- Git репозиторий инициализирован
- Формат версии: `X.Y.Z` (семантическое версионирование)
- Для GitLab релизов: `GITLAB_TOKEN` (опционально)

## Структура команд Makefile

```
make help          # Показать справку
make patch         # Patch релиз
make minor         # Minor релиз
make major         # Major релиз
make release TYPE=X.Y.Z  # Конкретная версия
make dev           # Локальный коммит
make commit-push   # Коммит и пуш
```

## Troubleshooting

### Ошибка "Tag already exists"
Тег с такой версией уже существует. Используйте другую версию или удалите старый тег.

### Ошибка "You have uncommitted changes"
Скрипт автоматически коммитит изменения, но если что-то пошло не так, закоммитьте изменения вручную или используйте `git stash`.

### GitLab release не создается
- Проверьте, что `GITLAB_TOKEN` установлен
- Убедитесь, что токен имеет права `api`
- Проверьте, что remote URL содержит `gitlab` в названии или установите `GITLAB_API_URL` вручную
