#!/usr/bin/env python3

"""
Script unifié de tests (Angular + Java).

Rôle du script :
- détecter automatiquement le type de projet,
- lancer les tests unitaires,
- nettoyer les anciens artefacts,
- centraliser les rapports JUnit XML dans test-results/.

Important :
- les rapports XML JUnit sont générés par les outils de test eux-mêmes
    (Karma/Jasmine côté Angular, JUnit/Gradle côté Java),
- ce script n'écrit pas le contenu JUnit ; il copie/agrège les fichiers pour GitLab CI.
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import os
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent
RESULTS_DIR = ROOT_DIR / "test-results"
FAILED = False
EXECUTED_PROJECTS = 0
IS_WINDOWS = sys.platform.startswith("win")
EXIT_CODE = 0

EXIT_SUCCESS = 0
EXIT_GENERAL_ERROR = 1
EXIT_CANNOT_EXECUTE = 126
EXIT_COMMAND_NOT_FOUND = 127


# Affiche un message d'information standard.
def log(message: str) -> None:
    print(f"[run-tests] {message}")


# Affiche un message d'erreur standard.
def fail(message: str) -> None:
    print(f"[run-tests] ERROR: {message}", file=sys.stderr)


# Conserve le code d'erreur le plus utile pour la sortie finale.
def set_exit_code(candidate: int) -> None:
    global EXIT_CODE

    if EXIT_CODE == EXIT_SUCCESS:
        EXIT_CODE = candidate
        return

    if candidate in (EXIT_COMMAND_NOT_FOUND, EXIT_CANNOT_EXECUTE):
        EXIT_CODE = candidate


# Vérifie qu'une commande système est disponible.
def require_command(command_name: str) -> bool:
    if shutil.which(command_name) is None:
        fail(f"Missing required command: {command_name}")
        return False
    return True


def copy_xml_reports(source_dir: Path, destination_dir: Path) -> bool:
    """Copie les rapports JUnit XML d'une application vers l'agrégat CI."""
    destination_dir.mkdir(parents=True, exist_ok=True)
    xml_files = sorted(source_dir.rglob("*.xml")) if source_dir.exists() else []

    if not xml_files:
        fail(f"No JUnit XML report found in {source_dir}")
        return False

    for report_file in xml_files:
        shutil.copy2(report_file, destination_dir / report_file.name)

    return True


# Exécute une commande dans un dossier donné et retourne succès/échec.
def run_command(command: list[str], cwd: Path) -> bool:
    completed = subprocess.run(command, cwd=str(cwd), check=False, shell=False)
    return completed.returncode == 0


# Construit la commande de test Angular selon l'OS.
def angular_test_command() -> list[str]:
    if IS_WINDOWS:
        npm_cmd = shutil.which("npm.cmd") or shutil.which("npm") or "npm.cmd"
        return [npm_cmd, "test"]
    return ["npm", "test"]


# Résout le chemin de cmd.exe sous Windows.
def windows_cmd_executable() -> str:
    comspec = os.environ.get("ComSpec")
    if comspec and Path(comspec).exists():
        return comspec

    system_root = os.environ.get("SystemRoot", "C:\\Windows")
    cmd_path = Path(system_root) / "System32" / "cmd.exe"
    return str(cmd_path)


# Construit la commande Gradle selon l'OS.
def gradle_test_command() -> list[str]:
    if IS_WINDOWS:
        # Sous Windows, on passe explicitement par cmd.exe pour exécuter gradlew.bat
        # de façon fiable (PowerShell, Git Bash, GitLab Runner shell, etc.).
        cmd_exe = windows_cmd_executable()
        return [cmd_exe, "/d", "/c", "gradlew.bat", "clean", "test", "--no-daemon"]
    return ["./gradlew", "clean", "test", "--no-daemon"]


# Lance les tests d'une application Angular.
def run_angular_tests(project_dir: Path) -> bool:
    project_name = project_dir.name
    log(f"Running Angular tests for {project_name}")

    if not require_command("npm"):
        set_exit_code(EXIT_COMMAND_NOT_FOUND)
        return False

    if not (project_dir / "node_modules").is_dir():
        fail(f"Missing npm dependencies in {project_name}. Run 'npm ci' first.")
        set_exit_code(EXIT_GENERAL_ERROR)
        return False

    # Nettoyage des rapports Angular précédents (source JUnit).
    reports_dir = project_dir / "reports"
    if reports_dir.exists():
        shutil.rmtree(reports_dir)

    destination_dir = RESULTS_DIR / project_name
    destination_dir.mkdir(parents=True, exist_ok=True)

    if not run_command(angular_test_command(), project_dir):
        fail(f"Angular tests failed for {project_name}")
        copy_xml_reports(reports_dir, destination_dir)
        set_exit_code(EXIT_GENERAL_ERROR)
        return False

    if not copy_xml_reports(reports_dir, destination_dir):
        set_exit_code(EXIT_GENERAL_ERROR)
        return False

    return True


# Lance les tests d'une application Java/Spring Boot.
def run_java_tests(project_dir: Path) -> bool:
    project_name = project_dir.name
    log(f"Running Java tests for {project_name}")

    if not require_command("java"):
        set_exit_code(EXIT_COMMAND_NOT_FOUND)
        return False

    gradlew = project_dir / "gradlew"
    if not gradlew.is_file():
        fail(f"Missing Gradle wrapper in {project_name}")
        set_exit_code(EXIT_COMMAND_NOT_FOUND)
        return False

    wrapper_properties = project_dir / "gradle" / "wrapper" / "gradle-wrapper.properties"
    if not wrapper_properties.is_file():
        fail(f"Missing Gradle wrapper configuration in {project_name}")
        set_exit_code(EXIT_GENERAL_ERROR)
        return False

    if not IS_WINDOWS:
        gradlew.chmod(0o755)
        if not os.access(gradlew, os.X_OK):
            fail(f"Gradle wrapper cannot execute in {project_name}")
            set_exit_code(EXIT_CANNOT_EXECUTE)
            return False

    # Nettoyage des rapports Java précédents (source JUnit).
    java_reports_dir = project_dir / "build" / "test-results" / "test"
    if java_reports_dir.exists():
        shutil.rmtree(java_reports_dir)

    destination_dir = RESULTS_DIR / project_name
    destination_dir.mkdir(parents=True, exist_ok=True)

    if not run_command(gradle_test_command(), project_dir):
        fail(f"Java tests failed for {project_name}")
        copy_xml_reports(java_reports_dir, destination_dir)
        set_exit_code(EXIT_GENERAL_ERROR)
        return False

    if not copy_xml_reports(java_reports_dir, destination_dir):
        set_exit_code(EXIT_GENERAL_ERROR)
        return False

    return True


# Détecte le type de projet puis appelle le bon runner.
def run_project_tests(project_dir: Path) -> None:
    global EXECUTED_PROJECTS
    global FAILED

    if (project_dir / "angular.json").is_file():
        EXECUTED_PROJECTS += 1
        if not run_angular_tests(project_dir):
            FAILED = True
        return

    if (project_dir / "build.gradle").is_file():
        EXECUTED_PROJECTS += 1
        if not run_java_tests(project_dir):
            FAILED = True


# Point d'entrée: nettoie, parcourt les projets, puis retourne un code CI.
def main() -> int:
    # Nettoyage de l'agrégat global pour garantir une exécution propre.
    log("Cleaning previous aggregated test artifacts")
    if RESULTS_DIR.exists():
        shutil.rmtree(RESULTS_DIR)
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)

    # Exécution éventuelle du projet situé à la racine.
    run_project_tests(ROOT_DIR)

    for project_dir in sorted(path for path in ROOT_DIR.iterdir() if path.is_dir()):
        run_project_tests(project_dir)

    if EXECUTED_PROJECTS == 0:
        fail(f"No supported project found under {ROOT_DIR}")
        return EXIT_COMMAND_NOT_FOUND

    if FAILED:
        fail("At least one test suite failed")
        return EXIT_CODE

    log(f"All test suites passed. Aggregated JUnit XML reports available in {RESULTS_DIR}")
    return EXIT_SUCCESS


if __name__ == "__main__":
    sys.exit(main())
