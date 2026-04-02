# Rapport exercice 2 — Étape 4 (Application Java)

## Objectif
Mettre en place un stage `release` dans le pipeline GitLab CI/CD pour générer automatiquement les versions, les releases GitLab et les images Docker versionnées, à partir des commits Conventional Commits. La version est synchronisée dans `build.gradle` via un script custom.

## Concepts fondamentaux

### Conventional Commits
Les messages de commit suivent ce format :

```
<type>(<scope>): <subject>
```

Types et impact sur la version :
- `feat:` → version mineure (MINOR)
- `fix:` → version patch (PATCH)
- `BREAKING CHANGE:` → version majeure (MAJOR)
- `docs:`, `chore:`, `refactor:`, etc. → aucun impact

### Semantic Versioning (SemVer)
Format `X.Y.Z` : X = majeur, Y = mineur, Z = patch.

---

## Ce qui a été mis en place

### 1) Fichier `package.json` minimal

Un `package.json` minimal a été ajouté à la racine du projet Java pour gérer les dépendances semantic-release uniquement.

Plugins configurés :
| Plugin | Version | Rôle |
|---|---|---|
| `semantic-release` | `^24.2.3` | Moteur principal |
| `@semantic-release/commit-analyzer` | `^13.0.1` | Détermine le type de version |
| `@semantic-release/release-notes-generator` | `^14.1.0` | Génère les notes de release |
| `@semantic-release/changelog` | `^6.0.0` | Met à jour `CHANGELOG.md` |
| `@semantic-release/exec` | `^7.1.0` | Lance les scripts custom (build.gradle + Docker) |
| `@semantic-release/git` | `^10.0.0` | Commite et pousse les fichiers mis à jour |
| `@semantic-release/gitlab` | `^13.3.2` | Crée la release GitLab |

### 2) Configuration `.releaserc.json`

- **branches** : `main` (production), `dev/test_ci` (prerelease `rc`)
- **prepareCmd** : appelle `.release-prepare.sh` pour mettre à jour `build.gradle`
- **publishCmd** : appelle `.release-docker-tag.sh` pour retagger l'image Docker
- **assets commités** : `build.gradle`, `CHANGELOG.md`
- **message de commit** : `chore(release): X.Y.Z [skip ci]`

### 3) Script de mise à jour Gradle `.release-prepare.sh`

Appelé en phase `prepare` par semantic-release. Il remplace la version dans `build.gradle` avec `sed` :

```bash
./.release-prepare.sh 0.3.0
# Remplace : version = '0.2.4'
# Par :      version = '0.3.0'
```

### 4) Script de retag Docker `.release-docker-tag.sh`

Appelé en phase `publish` par semantic-release. Il :
1. Récupère l'image buildée au SHA courant (`CI_COMMIT_SHORT_SHA`)
2. La retague avec la version sémantique et `latest`
3. Pousse les deux tags dans le Container Registry GitLab

```
registry.gitlab.com/groupe/app-java:abc123f   → entrée (build_image)
registry.gitlab.com/groupe/app-java:0.3.0     → sortie (release)
registry.gitlab.com/groupe/app-java:latest    → sortie (release)
```

### 5) Job `release_java` dans le pipeline

Ajouté dans `.gitlab-ci.yml`, stage `release` :
- **Déclenchement** : manuel sur `main`, uniquement si `RELEASE_ENABLED == "true"`
- **Anti-boucle** : le job est sauté si le message de commit commence par `chore(release):`
- **Image** : `node:22-bullseye` + service `docker:27.5.1-dind`
- `docker.io` installé en `before_script` pour le retag
- `GIT_DEPTH: "0"` pour que semantic-release lise tout l'historique

### 6) Déroulement d'une release

1. Analyse des commits depuis le dernier tag
2. Génération des notes et du changelog
3. Mise à jour de `build.gradle` via `.release-prepare.sh`
4. Retag de l'image Docker avec la version et `latest`
5. Commit des fichiers mis à jour + push sur `main`
6. Création de la release et du tag dans GitLab

---

## Variables CI/CD requises

| Variable | Valeur | Options |
|---|---|---|
| `GITLAB_TOKEN` | Personal Access Token | Masked, Protected, scopes : `api` + `read_repository` + `write_repository` |
| `RELEASE_ENABLED` | `true` / `false` | Interrupteur manuel |

---

## Déclencher une release

```bash
# 1. Vérifier que les commits sont en Conventional Commits
git log --oneline -n 10

# 2. Pousser sur main
git push gitlab main

# 3. Dans GitLab → CI/CD → Pipelines → cliquer Play sur release_java
```

Le CI Lint GitLab (`CI/CD > Pipelines > Validate`) permet de valider la syntaxe du `.gitlab-ci.yml` avant de lancer une vraie pipeline.

---

## Synchronisation de version

| Fichier | Mécanisme |
|---|---|
| `build.gradle` | Script `.release-prepare.sh` via `@semantic-release/exec prepareCmd` |
| `CHANGELOG.md` | Plugin `@semantic-release/changelog` (automatique) |

---

## Images Docker versionnées

| Tag | Créé quand | Exemple |
|---|---|---|
| `<SHA>` | Chaque push | `registry.../app:abc123f` |
| `<branche>-<SHA>` | Chaque push | `registry.../app:main-abc123f` |
| `<version>` | Chaque release | `registry.../app:0.3.0` |
| `latest` | Chaque release | `registry.../app:latest` |

### Récupérer une image versionnée

```bash
# Tirer la dernière image de production
docker pull registry.gitlab.com/<namespace>/<projet>:latest

# Tirer une version spécifique
docker pull registry.gitlab.com/<namespace>/<projet>:0.3.0
```

### Retagger manuellement une release passée

Si une release a été créée avant la mise en place du retag automatique, les tags versionnés n'existent pas. Les créer manuellement :

```bash
export REGISTRY=registry.gitlab.com/<namespace>/<projet>
export SHA=<sha_court_du_commit_build>
export VERSION=2.0.1

docker pull $REGISTRY:$SHA
docker tag $REGISTRY:$SHA $REGISTRY:$VERSION
docker tag $REGISTRY:$SHA $REGISTRY:latest
docker push $REGISTRY:$VERSION
docker push $REGISTRY:latest
```

Le SHA du commit se trouve dans GitLab → Repository → Commits, ou via :
```bash
git log --oneline | grep -B1 "chore(release): 2.0.1"
```

---

## Différence avec Angular

Angular utilise `@semantic-release/npm` natif pour mettre à jour `package.json`. Java n'a pas d'équivalent pour Gradle, d'où le script custom `.release-prepare.sh`. Le mécanisme de retag Docker est identique dans les deux projets.

---

## Erreurs rencontrées et corrections

**`@semantic-release/gitlab@^14` n'existe pas.** La version 14 n'a jamais été publiée sur npm. Corrigé en utilisant `^13.3.2`.

**Les tests Angular s'exécutaient dans le pipeline Java.** La détection du type de projet reposait sur `package.json`. Comme ce fichier existe aussi dans le repo Java (pour semantic-release), les tests Angular se lançaient. Corrigé en détectant `angular.json` à la place.

**YAML invalide dans le script CI.** The syntaxe `test -n "$VAR" || (echo ... && exit 1)` n'est pas acceptée dans un bloc YAML multi-lignes. Corrigé en utilisant un bloc `if/fi` standard.

**Deux pipelines "Skipped" après une release.** Comportement normal : semantic-release pousse un commit et un tag, chacun peut déclencher une pipeline GitLab. Les deux ont `[skip ci]` donc sont automatiquement sautés.

---

## Résultat

- ✅ semantic-release installé et configuré pour GitLab
- ✅ Stage `release` présent dans le pipeline
- ✅ Convention Conventional Commits adoptée
- ✅ Releases GitLab générées automatiquement avec changelog
- ✅ Images Docker taguées avec la version sémantique et `latest`
- ✅ Déclenchement manuel via `RELEASE_ENABLED`
- ✅ Version synchronisée dans `build.gradle`


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
- `semantic-release` `^24.2.3` — moteur principal
- `@semantic-release/changelog` `^6.0.0` — génération CHANGELOG.md
- `@semantic-release/exec` `^7.1.0` — exécution de scripts custom (mise à jour build.gradle + retag Docker)
- `@semantic-release/git` `^10.0.0` — commit + push auto des mises à jour
- `@semantic-release/gitlab` `^13.3.2` — création de releases GitLab
- `@semantic-release/commit-analyzer` `^13.0.1`
- `@semantic-release/release-notes-generator` `^14.1.0`

> **Note** : Les versions pinned sont importantes car certaines versions publiées n'existent pas (ex: `@semantic-release/gitlab@^14` inexistant).

### 2) Fichier de configuration `.releaserc.json`

Le fichier `.releaserc.json` définit :
- **branches** : `main` en produit, `dev/test_ci` en prerelease (version rc)
- **plugins** : ordre d'exécution (analyze, generate, changelog, exec, git, gitlab)
- **exec.prepareCmd** : commande shell pour mettre à jour build.gradle
- **exec.publishCmd** : commande shell pour retagger l'image Docker avec la version sémantique
- **assets** : fichiers à commiter (build.gradle, CHANGELOG.md)
- **message** : format du commit auto généré

### 3) Script de mise à jour build.gradle `.release-prepare.sh`

Le fichier `.release-prepare.sh` :
- Reçoit la nouvelle version en paramètre : `${nextRelease.version}`
- Utilise `sed` pour remplacer la ligne `version = '...'` dans build.gradle
- Valide et nettoie les fichiers temporaires (`.bak`)

Exemple :
```bash
./.release-prepare.sh 0.3.0
# Remplace: version = '0.2.4'
# Par:      version = '0.3.0'
```

### 4) Script de retag Docker `.release-docker-tag.sh`

Le fichier `.release-docker-tag.sh` est appelé par semantic-release via `@semantic-release/exec publishCmd` :
- Reçoit la version en paramètre : `${nextRelease.version}`
- Se connecte au GitLab Container Registry (`docker login`)
- Récupère l'image taguée SHA du commit courant (`CI_COMMIT_SHORT_SHA`)
- La retague avec le numéro de version sémantique et `latest`
- Pousse les deux tags dans le registry

Exemple :
```bash
# Source (créée par build_image)
registry.gitlab.com/groupe/app-java:abc123f

# Tags créés après release
registry.gitlab.com/groupe/app-java:0.3.0
registry.gitlab.com/groupe/app-java:latest
```

### 5) Stage `release` au pipeline

Un job `release_java` a été ajouté au `.gitlab-ci.yml` :
- Déclenché **manuellement** sur la branche `main` (sécurité)
- Règle spéciale : n'exécute pas si commit commence par `chore(release):` (évite boucles)
- Utilise l'image `node:22-bullseye` avec un service **Docker-in-Docker** (`docker:27.5.1-dind`)
- Installe `docker.io` en `before_script` pour pouvoir appeler Docker CLI
- Variables `DOCKER_HOST` et `DOCKER_TLS_CERTDIR` configurées pour le dind
- Injecte `GITLAB_TOKEN` pour authentifier les push vers GitLab

### 6) Comportement du release

Quand le job `release_java` s'exécute :
1. **Analyzer** : lit les commits depuis la dernière version (actuellement 0.2.4)
2. **Release Notes** : génère la liste des changements
3. **Changelog** : ajoute/met à jour CHANGELOG.md
4. **Exec** (`prepareCmd`) : lance `./.release-prepare.sh 0.3.0` — mise à jour build.gradle
5. **Exec** (`publishCmd`) : lance `./.release-docker-tag.sh 0.3.0` — retag Docker
6. **Git** : commit + push build.gradle et CHANGELOG.md sur main
7. **GitLab** : crée une release GitLab avec tags et notes

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

Les images publiées dans le stage `build` reçoivent deux tags basés sur le SHA : `<sha>` et `<branche>-<sha>`.  
**À chaque release**, le script `.release-docker-tag.sh` retaggue automatiquement l'image avec la version sémantique et `latest` :

| Tag | Quand | Exemple |
|---|---|---|
| `<SHA>` | À chaque push | `registry.../app:abc123f` |
| `<branche>-<SHA>` | À chaque push | `registry.../app:main-abc123f` |
| `<version>` | À chaque release | `registry.../app:0.3.0` |
| `latest` | À chaque release | `registry.../app:latest` |

### Récupération manuelle des images d'une release passée

Si une release a été effectuée **avant** la mise en place du retag automatique, les images versionnées n'ont pas été créées. Pour les créer manuellement :

**Étape 1** — Identifier le SHA du commit de build correspondant :
```bash
git log --oneline | grep -B5 "chore(release): 2.0.1"
```

**Étape 2** — Retagger manuellement depuis votre poste :
```bash
export REGISTRY=registry.gitlab.com/<namespace>/<projet>
export SHA=<sha_court_du_commit>
export VERSION=2.0.1

docker pull $REGISTRY:$SHA
docker tag $REGISTRY:$SHA $REGISTRY:$VERSION
docker tag $REGISTRY:$SHA $REGISTRY:latest
docker push $REGISTRY:$VERSION
docker push $REGISTRY:latest
```

## Points de vigilance appliqués

- Le token GitLab n'est pas exprimé en dur dans le pipeline.
- L'authentification passe via `GITLAB_TOKEN` (variable de projet maskée).
- Le job `release_java` ne se déclenche **que manuellement** pour éviter les releases accidentelles.
- Les commits auto-générés par semantic-release commencent par `chore(release):` pour éviter une loop.
- Le script `.release-prepare.sh` est rendu exécutable via `chmod +x` dans le script CI.
- Le `publishCmd` de `@semantic-release/exec` n'est exécuté que si une release est réellement générée (pas de retag inutile).
- La branche `dev/test_ci` peut produire des prerelease (version rc) sans interférer avec les releases main.
- Le validateur intégré GitLab CI Lint est utile pour contrôler le `.gitlab-ci.yml` avant exécution.

## Différence avec Angular

Contrairement à Angular qui utilise `@semantic-release/npm` natif pour la mise à jour de version, Java dépend d'un script custom `.release-prepare.sh` pour mettre à jour `build.gradle` (Gradle n'a pas de plugin semantic-release officiel équivalent). Les deux projets partagent le même mécanisme de retag Docker via `.release-docker-tag.sh`.

## Résultat attendu atteint

- ✅ semantic-release est installé et configuré pour GitLab.
- ✅ Un stage `release` est présent au pipeline avec un job `release_java` manuel.
- ✅ La convention Conventional Commits est documentée et adoptée.
- ✅ Les releases GitLab sont générées automatiquement avec changelog.
- ✅ Les images Docker sont taguées avec la version sémantique (ex: `0.3.0`, `latest`).
- ✅ Le job de release se déclenche manuellement sur `main` (gate `RELEASE_ENABLED`).
- ✅ La version est synchronisée dans `build.gradle` via le script `.release-prepare.sh`.

## Prochaines étapes

1. Déclencher `release_java` manuellement (bouton Play sur `main` avec `RELEASE_ENABLED=true`).
2. Vérifier la génération de la release GitLab, du changelog, de la mise à jour build.gradle et des images versionnées.
3. Mettre en place le Conventional Commits pour tous les futurs commits.
