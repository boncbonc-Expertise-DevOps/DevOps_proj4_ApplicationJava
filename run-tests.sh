#!/usr/bin/env bash

# Script unifié de tests (Angular + Java)
#
# Rôle du script :
# - détecter automatiquement le type de projet,
# - lancer les tests unitaires,
# - nettoyer les anciens artefacts,
# - centraliser les rapports JUnit XML dans test-results/.
#
# Important :
# - les fichiers XML JUnit sont générés par les frameworks de tests
#   (Karma/Jasmine côté Angular, JUnit/Gradle côté Java),
# - ce script ne "fabrique" pas le XML, il l'agrège pour GitLab CI.

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="$ROOT_DIR/test-results"
FAILED=0
EXECUTED_PROJECTS=0
EXIT_CODE=0

EXIT_SUCCESS=0
EXIT_GENERAL_ERROR=1
EXIT_CANNOT_EXECUTE=126
EXIT_COMMAND_NOT_FOUND=127

# Affiche un message d'information standard.
log() {
  printf '[run-tests] %s\n' "$1"
}

# Affiche un message d'erreur standard.
fail() {
  printf '[run-tests] ERROR: %s\n' "$1" >&2
}

# Conserve le code d'erreur le plus utile pour la sortie finale.
set_exit_code() {
  local candidate="$1"
  if [[ "$EXIT_CODE" -eq 0 ]]; then
    EXIT_CODE="$candidate"
    return
  fi

  if [[ "$candidate" -eq "$EXIT_COMMAND_NOT_FOUND" || "$candidate" -eq "$EXIT_CANNOT_EXECUTE" ]]; then
    EXIT_CODE="$candidate"
  fi
}

# Vérifie qu'une commande système est disponible.
require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    fail "Missing required command: $command_name"
    return "$EXIT_COMMAND_NOT_FOUND"
  fi
}

# Copie tous les rapports JUnit XML vers le dossier agrégé CI.
copy_xml_reports() {
  local source_dir="$1"
  local destination_dir="$2"
  local copied=0

  mkdir -p "$destination_dir"

  while IFS= read -r report_file; do
    cp "$report_file" "$destination_dir/"
    copied=1
  done < <(find "$source_dir" -type f -name '*.xml' 2>/dev/null)

  if [[ "$copied" -eq 0 ]]; then
    fail "No JUnit XML report found in $source_dir"
    return "$EXIT_GENERAL_ERROR"
  fi

  return "$EXIT_SUCCESS"
}

# Lance les tests d'une application Angular.
run_angular_tests() {
  local project_dir="$1"
  local project_name
  project_name="$(basename "$project_dir")"

  log "Running Angular tests for $project_name"

  require_command npm || return 1

  if [[ ! -d "$project_dir/node_modules" ]]; then
    fail "Missing npm dependencies in $project_name. Run 'npm ci' first."
    return "$EXIT_GENERAL_ERROR"
  fi

  # Nettoyage des rapports Angular précédents (source JUnit).
  rm -rf "$project_dir/reports"
  mkdir -p "$RESULTS_DIR/$project_name"

  if ! (cd "$project_dir" && npm test); then
    fail "Angular tests failed for $project_name"
    copy_xml_reports "$project_dir/reports" "$RESULTS_DIR/$project_name" || true
    return "$EXIT_GENERAL_ERROR"
  fi

  copy_xml_reports "$project_dir/reports" "$RESULTS_DIR/$project_name"
}

# Lance les tests d'une application Java/Spring Boot.
run_java_tests() {
  local project_dir="$1"
  local project_name
  project_name="$(basename "$project_dir")"

  log "Running Java tests for $project_name"

  require_command java || return 1

  if [[ ! -f "$project_dir/gradlew" ]]; then
    fail "Missing Gradle wrapper in $project_name"
    return "$EXIT_COMMAND_NOT_FOUND"
  fi

  if [[ ! -f "$project_dir/gradle/wrapper/gradle-wrapper.properties" ]]; then
    fail "Missing Gradle wrapper configuration in $project_name"
    return "$EXIT_GENERAL_ERROR"
  fi

  chmod +x "$project_dir/gradlew"
  if [[ ! -x "$project_dir/gradlew" ]]; then
    fail "Gradle wrapper cannot execute in $project_name"
    return "$EXIT_CANNOT_EXECUTE"
  fi

  # Nettoyage des rapports Java précédents (source JUnit).
  rm -rf "$project_dir/build/test-results/test"
  mkdir -p "$RESULTS_DIR/$project_name"

  if ! (cd "$project_dir" && ./gradlew clean test --no-daemon); then
    fail "Java tests failed for $project_name"
    copy_xml_reports "$project_dir/build/test-results/test" "$RESULTS_DIR/$project_name" || true
    return "$EXIT_GENERAL_ERROR"
  fi

  copy_xml_reports "$project_dir/build/test-results/test" "$RESULTS_DIR/$project_name"
}

# Détecte le type de projet puis appelle le bon runner.
run_project_tests() {
  local project_dir="$1"

  if [[ -f "$project_dir/package.json" ]]; then
    EXECUTED_PROJECTS=$((EXECUTED_PROJECTS + 1))
    run_angular_tests "$project_dir"
    local status=$?
    if [[ "$status" -ne 0 ]]; then
      FAILED=1
      set_exit_code "$status"
    fi
    return
  fi

  if [[ -f "$project_dir/build.gradle" ]]; then
    EXECUTED_PROJECTS=$((EXECUTED_PROJECTS + 1))
    run_java_tests "$project_dir"
    local status=$?
    if [[ "$status" -ne 0 ]]; then
      FAILED=1
      set_exit_code "$status"
    fi
  fi
}

# Point d'entrée: nettoie, parcourt les projets, puis retourne un code CI.
main() {
  # Nettoyage de l'agrégat global pour éviter les faux positifs CI.
  log "Cleaning previous aggregated test artifacts"
  rm -rf "$RESULTS_DIR"
  mkdir -p "$RESULTS_DIR"

  # Exécution éventuelle du projet situé à la racine.
  run_project_tests "$ROOT_DIR"

  while IFS= read -r project_dir; do
    run_project_tests "$project_dir"
  done < <(find "$ROOT_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

  if [[ "$EXECUTED_PROJECTS" -eq 0 ]]; then
    fail "No supported project found under $ROOT_DIR"
    exit "$EXIT_COMMAND_NOT_FOUND"
  fi

  if [[ "$FAILED" -ne 0 ]]; then
    fail "At least one test suite failed"
    exit "$EXIT_CODE"
  fi

  log "All test suites passed. Aggregated JUnit XML reports available in $RESULTS_DIR"
  exit "$EXIT_SUCCESS"
}

main "$@"
