# Rapport exercice 2 — Étape 4 (Application Java)

## Objectif
Mettre en place un stage `release` au pipeline GitLab CI/CD pour générer automatiquement les versions et releases GitLab basées sur les commits respectant la convention Conventional Commits, en utilisant semantic-release avec les plugins GitLab et une stratégie custom pour build.gradle.

## Concepts fondamentaux

### Conventional Commits
La convention Conventional Commits structure les messages de commit selon un format standard :

```
<type>(<scope>): <subject>

<body>

<footer>
```

Types acceptés (utilisés pour la versioning) :
- `feat:` → version mineure (MINOR)
- `fix:` → version patch (PATCH)
- `BREAKING CHANGE:` → version majeure (MAJOR)
- `docs:`, `style:`, `refactor:`, `perf:`, `test:`, `chore:` → aucun impact de version

Exemple côté Java :
- `fix(db): corriger migration Hibernate` → version 0.2.5 (patch)
- `feat(api): endpoint workshops` → version 0.3.0 (minor)
- `BREAKING CHANGE: changement format API` → version 1.0.0 (major)

### Semantic Versioning (SemVer)
Le format X.Y.Z représente :
- X = version majeure (breaking changes)
- Y = version mineure (features)
- Z = version patch (fixes)

## Ce qui a été mis en place

### 1) Installation de semantic-release

Un fichier `package.json` minimal a été créé dans le dépôt Java pour gérer les dépendances CI/CD uniquement.

Dépendances ajoutées :
- `semantic-release` — moteur principal
- `@semantic-release/changelog` — génération CHANGELOG.md
- `@semantic-release/exec` — exécution de scripts custom (mise à jour build.gradle)
- `@semantic-release/git` — commit + push auto des mises à jour
- `@semantic-release/gitlab` — création de releases GitLab

### 2) Fichier de configuration `.releaserc.json`

Le fichier `.releaserc.json` définit :
- **branches** : `main` en produit, `dev/test_ci` en prerelease (version rc)
- **plugins** : ordre d'exécution (analyze, generate, changelog, exec, git, gitlab)
- **exec.prepareCmd** : commande shell pour mettre à jour build.gradle
- **assets** : fichiers à commiter (build.gradle, CHANGELOG.md)
- **message** : format du commit auto généré

### 3) Script de mise à jour build.gradle

Le fichier `.release-prepare.sh` :
- Reçoit la nouvelle version en paramètre : `${nextRelease.version}`
- Utilise `sed` pour remplacer la ligne `version = '...'` dans build.gradle
- Valide et nettoie les fichiers temporaires

Exemple :
```bash
./.release-prepare.sh 0.3.0
# Remplace: version = '0.2.4'
# Par:      version = '0.3.0'
```

### 4) Stage `release` au pipeline

Un job `release_java` a été ajouté au `.gitlab-ci.yml` :
- Déclenché **manuellement** sur la branche `main` (sécurité)
- Règle spéciale : n'exécute pas si commit commence par `chore(release):` (évite boucles)
- Utilise l'image `node:22` pour exécuter semantic-release + script bash
- Rend le script exécutable avant de lancer semantic-release
- Injecte `CI_JOB_TOKEN` automatique pour authentifier les push vers GitLab

### 5) Comportement du release

Quand le job `release_java` s'exécute :
1. **Analyzer** : lit les commits depuis la dernière version (actuellement 0.2.4)
2. **Release Notes** : génère la liste des changements
3. **Changelog** : ajoute/met à jour CHANGELOG.md
4. **Exec** : lance `./.release-prepare.sh 0.3.0` (ou version calculée)
5. **Git** : commit + push build.gradle et CHANGELOG.md sur main
6. **GitLab** : crée une release GitLab avec tags et notes

## Variables CI/CD requises

### Token GitLab (GITLAB_TOKEN)

À créer dans GitLab > Project > Settings > CI/CD > Variables :

**Propriétés** :
- Clé : `GITLAB_TOKEN`
- Valeur : Personal Access Token (PAT)
- Visibilité : **Masked and hidden**
- Protection : Checked (main seulement)
- Scopes recommandés : `api` + `read_repository` + `write_repository`

Alternative locale en environnement GitLab CI :
- Utiliser `CI_JOB_TOKEN` automatique (fourni par GitLab CI)
- Valable seulement dans le contexte du pipeline
- Aucune configuration supplémentaire requise

## Comment utiliser le release en CI

### Avant de déclencher

Vérifier que les commits récents respectent Conventional Commits :
```bash
git log --oneline -n 10
# Attendu : des lignes comme "fix(...):", "feat(...):)", etc.
```

### Déclencher manuellement un release

Dans GitLab UI :
1. Aller à CI/CD > Pipelines
2. Créer une nouvelle pipeline (ou attendre un push) sur `main`
3. Le job `release_java` apparaît avec un bouton **Play** (manual job)
4. Cliquer pour lancer le release

Avant l'execution, il est possible de verifier la syntaxe du pipeline avec l'outil integre GitLab **Validate your GitLab CI configuration** (CI Lint). Cet ecran permet de valider le fichier `.gitlab-ci.yml` et de detecter rapidement les erreurs YAML ou de structure des jobs avant de lancer une pipeline reelle.

### Logs et résultat

Le job `release_java` affiche :
- `npm ci` : installation des dépendances semantic-release
- `chmod +x` : rend le script exécutable
- Analyse des commits : `Found X commits since last release`
- Exécution du script : `Version mise a jour vers X.Y.Z dans build.gradle`
- Version générée : `Publishing version X.Y.Z`
- URL de la release : lien GitLab Releases

### Résultat visible dans GitLab

Après un release réussi :
- Project > Releases : nouvelle entry avec tag versionné (ex: 0.3.0), changelog, sources
- Project > Tags : nouveau tag de version (0.3.0)
- Commits : commit auto généré `chore(release): 0.3.0`
- Repository > Files : build.gradle mis à jour avec version = '0.3.0'

## Synchronisation de version

### Java

La version dans `build.gradle` est mise à jour automatiquement par le script `.release-prepare.sh` appelé via le plugin `@semantic-release/exec`.

Version actuelle de départ : `0.2.4`  
Prochain release exemple : `0.3.0` (si 1 ou plus de commits `feat:`) ou `0.2.5` (si uniquement `fix:`)

### Images Docker

Les images publiées dans le stage `build` gardent les tags basés sur le SHA du commit et le nom de branche.  
Option future : retaguer les images avec la version sémantique après release (ex: `registry.gitlab.com/groupe/proj:0.3.0`).

## Points de vigilance appliqués

- Le token GitLab n'est pas exprimé en dur dans le pipeline.
- L'authentification passe via `CI_JOB_TOKEN` (automatique) ou `GITLAB_TOKEN` (variable de projet).
- Le job `release_java` ne se déclenche **que manuellement** pour éviter les releases accidentelles.
- Les commits auto-générés par semantic-release commencent par `chore(release):` pour éviter une loop.
- Le script `.release-prepare.sh` doit être exécutable via `chmod +x`.
- La branche `dev/test_ci` peut produire des prerelease (version rc) sans interferer avec les releases main.
- Le validateur integre GitLab CI Lint est utile pour controler le `.gitlab-ci.yml` avant execution du pipeline.

## Différence avec Angular

Contrairement à Angular qui utilise `@semantic-release/npm` natif et ne nécessite pas de script de préparation, Java dépend d'un script custom `.release-prepare.sh` pour mettre à jour `build.gradle`. Cela est nécessaire car Gradle ne dispose pas d'un plugin semantic-release officiel équivalent.

## Limite actuelle

Le release génère une version sémantique et une release GitLab, mais il ne retagge pas automatiquement les images Docker avec cette version. Cette étape pourrait être ajoutée via un job supplémentaire `retag_images` après `release_java`.

## Résultat attendu atteint

- semantic-release est configuré pour Java (dépendances npm, .releaserc.json, script custom).
- Un stage `release` est présent au pipeline avec un job `release_java` manuel.
- La convention Conventional Commits est documentée et adoptée.
- À chaque release, GitLab Releases crée une entry avec changelog.
- Les versions sont synchronisées dans build.gradle via le script `.release-prepare.sh`.
- Un token GITLAB_TOKEN peut être configuré pour une utilisation autonome en production.

## Prochaines étapes

1. Configurer le token GitLab si accès projet complet.
2. Mettre en place le Conventional Commits dans les futurs commits.
3. Tester un premier release manuel sur main.
4. Vérifier la génération de la release GitLab, du changelog et de la mise à jour build.gradle.
5. (Futur) Ajouter automatisation images Docker avec tag sémantique.
