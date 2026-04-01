# Rapport exercice 2 — Étape 2 (Application Java)

## Objectif
Mettre en place un pipeline GitLab CI/CD avec un premier stage `test`, réutilisable sur les deux applications (Angular et Java), tout en publiant les rapports de tests dans GitLab.

## Ce qui a été mis en place

### 1) Fichier CI créé
- Fichier ajouté : `.gitlab-ci.yml`
- Structure du pipeline :
  - `stages: [test, quality]`
  - exécution sur `push` et `merge_request_event`

### 2) Pipeline générique avec adaptation automatique
Deux jobs de test existent dans le même fichier CI :
- `angular_tests` (activé seulement si `package.json` + `karma.conf.js` existent)
- `java_tests` (activé seulement si `build.gradle` existe)

Dans ce repository Java, seul `java_tests` s’exécute grâce aux règles `rules: exists`.

### 2.b) Stage quality (lint)
Un second stage `quality` a été ajouté pour exécuter les vérifications de lint sans attendre le stage `build`.

Jobs configurés :
- `angular_lint` : lance `npm run lint --if-present` quand un projet Angular est détecté.
- `java_lint` : lance Checkstyle quand un projet Java est détecté et que les tâches Checkstyle existent.

Dans ce repository Java, `java_lint` est le job concerné.

### 3) Scripts de test intégrés au repository
Les scripts de test ont été copiés dans le repo pour qu’ils soient disponibles dans le contexte GitLab Runner :
- `run-tests.sh`
- `run-tests.py`

Le job CI exécute `./run-tests.sh`.

### 4) Adaptation des scripts au mode mono-repo
Les scripts étaient initialement pensés pour un dossier parent multi-projets. Ils ont été adaptés pour aussi détecter un projet situé à la racine du repository.

Résultat : le script fonctionne aussi bien :
- dans un dossier parent contenant plusieurs apps,
- que dans un repo GitLab unique (cas actuel Java).

### 5) Cache des dépendances
Pour accélérer les builds :
- cache Gradle activé (`.gradle/caches/`, `.gradle/wrapper/`)
- clé de cache basée sur `build.gradle`, `settings.gradle` et `gradle-wrapper.properties`

### 6) Rapports de tests GitLab (JUnit)
Le pipeline publie :
- artifacts : `test-results/`, `build/reports/tests/test/`, `build/test-results/test/`
- rapports JUnit GitLab : `test-results/**/*.xml`

Les fichiers XML sont générés par JUnit/Gradle puis agrégés par le script dans `test-results/`.

### 6.b) Contenu des artefacts visibles dans GitLab
Dans l'interface GitLab, les jobs de test affichent en general deux types d'artefacts :
- `archive.zip` : archive des chemins declares dans `artifacts:paths` (par exemple `test-results/`, `build/reports/tests/test/`, `build/test-results/test/`).
- `junit.xml.gz` : archive interne des rapports declares dans `artifacts:reports:junit`, utilisee par GitLab pour alimenter l'onglet Tests.

Pour les jobs du stage `quality`, seul un artefact `archive.zip` est attendu, contenant le dossier `quality-reports/` (logs de lint).

## Validation locale réalisée
Exécution validée localement dans ce repo avec :
- `bash ./run-tests.sh`
- Résultat : succès des tests Java + génération/agrégation des XML JUnit

## Résultat attendu atteint
- Le fichier `.gitlab-ci.yml` contient un stage `test`.
- Le pipeline est structuré en stages distincts : `test` puis `quality`.
- Le pipeline s’adapte automatiquement au type de projet.
- Les dépendances sont mises en cache.
- Le rapport de test est intégré au pipeline GitLab (artifacts + reports JUnit).

## Points de vigilance appliqués
- Aucun secret n’est écrit dans les scripts ni exposé dans les logs.
- Recommandation suivie : tester sur une branche de développement avant merge sur `main`.

## Prochaine étape
Étape 3 : ajouter le stage `build` pour construire l’image Docker et la pousser dans GitLab Container Registry.
