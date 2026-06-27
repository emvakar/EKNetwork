#!/usr/bin/env bash
#
# Генерация оформленных release notes для GitHub Release.
#
# Источник №1 — секция версии из CHANGELOG.md (ручной, выверенный текст).
# Источник №2 (fallback) — категоризация коммитов между предыдущим и текущим
# тегом с эмодзи по типу (feat/fix/...).
#
# Ожидаемые переменные окружения (передаёт release.yml):
#   VERSION     — версия без префикса v (например 1.6.1)
#   TAG         — имя тега (например v1.6.1)
#   PREV_TAG    — предыдущий тег (может быть пустым для первого релиза)
#   TEST_COUNT  — число тестов (для футера)
#   COVERAGE    — покрытие в процентах (для футера)
#
set -euo pipefail

VERSION="${VERSION:-}"
TAG="${TAG:-$VERSION}"
PREV_TAG="${PREV_TAG:-}"
TEST_COUNT="${TEST_COUNT:-}"
COVERAGE="${COVERAGE:-}"
CHANGELOG="CHANGELOG.md"

# ── 1. Пытаемся вытащить секцию из CHANGELOG.md ───────────────────────────────
changelog_section() {
  [ -f "$CHANGELOG" ] || return 0
  awk -v ver="$VERSION" '
    $0 ~ "^## \\[" ver "\\]"     { flag=1; next }
    flag && /^## \[/             { flag=0 }
    flag                         { print }
  ' "$CHANGELOG" \
    | sed -e '/./,$!d' \
    | awk 'BEGIN{n=0} {lines[n++]=$0} END{while(n>0 && lines[n-1] ~ /^[[:space:]]*$/) n--; for(i=0;i<n;i++) print lines[i]}'
}

# ── 2. Fallback: категоризация коммитов с эмодзи ──────────────────────────────
emoji_for() {
  case "$1" in
    feat)              echo "✨" ;;
    fix)               echo "🐛" ;;
    perf)              echo "⚡" ;;
    refactor)          echo "♻️" ;;
    test)              echo "🧪" ;;
    docs)              echo "📝" ;;
    ci|build|chore)    echo "🔧" ;;
    *)                 echo "📦" ;;
  esac
}

heading_for() {
  case "$1" in
    feat)              echo "✨ Улучшения" ;;
    fix)               echo "🐛 Исправления" ;;
    perf)              echo "⚡ Производительность" ;;
    refactor)          echo "♻️ Рефакторинг" ;;
    test)              echo "🧪 Тесты" ;;
    docs)              echo "📝 Документация" ;;
    ci|build|chore)    echo "🔧 Инфраструктура" ;;
    *)                 echo "📦 Прочее" ;;
  esac
}

generated_section() {
  local range
  if [ -n "$PREV_TAG" ]; then
    range="${PREV_TAG}..${TAG}"
  else
    range="$TAG"
  fi

  # Категории в порядке вывода
  local order="feat fix perf refactor test docs ci other"
  local tmp
  tmp="$(mktemp -d)"

  while IFS= read -r subject; do
    [ -n "$subject" ] || continue
    # Пропускаем служебные version-bump коммиты
    case "$subject" in
      "Bump version"*|"chore: bump version"*|"set pacakge version"|"Prepare release"*|"Release "*) continue ;;
    esac
    # Определяем тип по conventional-prefix
    local type rest
    local re='^([a-z]+)(\([^)]*\))?!?:[[:space:]]*(.*)$'
    if [[ "$subject" =~ $re ]]; then
      type="${BASH_REMATCH[1]}"
      rest="${BASH_REMATCH[3]}"
    else
      type="other"
      rest="$subject"
    fi
    case " feat fix perf refactor test docs ci build chore " in
      *" $type "*) ;;
      *) type="other"; rest="$subject" ;;
    esac
    [ "$type" = "build" ] && type="ci"
    [ "$type" = "chore" ] && type="ci"
    printf '%s\n' "$rest" >> "$tmp/$type"
  done < <(git log --no-merges --format='%s' "$range" 2>/dev/null || true)

  local printed=0
  for type in $order; do
    [ -f "$tmp/$type" ] || continue
    echo "### $(heading_for "$type")"
    echo ""
    while IFS= read -r line; do
      echo "- ${line}"
    done < "$tmp/$type"
    echo ""
    printed=1
  done
  rm -rf "$tmp"
  [ "$printed" = "1" ] || echo "_Изменения не зафиксированы в истории коммитов._"
}

# ── 3. Сборка финального документа ────────────────────────────────────────────
BODY="$(changelog_section)"
SOURCE_NOTE=""
if [ -z "$BODY" ]; then
  BODY="$(generated_section)"
  SOURCE_NOTE="> ℹ️ Заметки сформированы автоматически из истории коммитов."
fi

echo "## 🚀 EKNetwork ${VERSION}"
echo ""
if [ -n "$SOURCE_NOTE" ]; then
  echo "$SOURCE_NOTE"
  echo ""
fi
echo "$BODY"
echo ""
echo "---"
echo ""
echo "### 📦 Установка"
echo ""
echo '```swift'
echo ".package(url: \"https://github.com/emvakar/EKNetwork\", from: \"${VERSION}\")"
echo '```'
echo ""

# Футер со статистикой качества (если CI прокинул значения)
STATS=""
[ -n "$TEST_COUNT" ] && [ "$TEST_COUNT" != "0" ] && STATS="🧪 Тестов: **${TEST_COUNT}**"
if [ -n "$COVERAGE" ] && [ "$COVERAGE" != "0" ]; then
  [ -n "$STATS" ] && STATS="${STATS} · "
  STATS="${STATS}📊 Покрытие: **${COVERAGE}%**"
fi
if [ -n "$STATS" ]; then
  echo "### ✅ Качество"
  echo ""
  echo "$STATS"
  echo ""
fi

if [ -n "$PREV_TAG" ]; then
  echo "**Полный список изменений:** [\`${PREV_TAG}...${TAG}\`](https://github.com/emvakar/EKNetwork/compare/${PREV_TAG}...${TAG})"
fi
echo ""
echo "📄 История всех версий — [CHANGELOG.md](https://github.com/emvakar/EKNetwork/blob/main/CHANGELOG.md)"
