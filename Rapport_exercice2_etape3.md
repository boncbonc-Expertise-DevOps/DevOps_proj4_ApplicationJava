# Rapport exercice 2 — Étape 3 (Application Java)

## Objectif
Ajouter un stage `build` au pipeline GitLab CI/CD afin de construire l'image Docker de l'application et de la publier dans le GitLab Container Registry avec des tags lisibles.

## Ce qui a été mis en place

### 1) Nouveau stage `build`
Le fichier `.gitlab-ci.yml` contient maintenant trois stages :
- `test`
- `quality`
- `build`

Le stage `build` s'exécute après les vérifications de tests et de qualité.

### 2) Construction Docker dans GitLab CI
Un job `build_image` a été ajouté.

Ce job utilise :
- l'image `docker:27.5.1-cli`
- le service `docker:27.5.1-dind`
- une connexion au démon Docker via `DOCKER_HOST=tcp://docker:2375`

Le job construit l'image à partir du `Dockerfile` du repository puis la pousse dans le registre de conteneur GitLab.

### 3) Utilisation des variables CI/CD
Le pipeline s'appuie sur les variables GitLab fournies automatiquement :
- `CI_REGISTRY`
- `CI_REGISTRY_USER`
- `CI_REGISTRY_PASSWORD`
- `CI_REGISTRY_IMAGE`
- `CI_COMMIT_SHORT_SHA`
- `CI_COMMIT_REF_SLUG`

Variables de confort ajoutées dans le pipeline :
- `IMAGE_TAG_SHA` = image taguée avec le SHA court du commit
- `IMAGE_TAG_REF_SHA` = image taguée avec le nom de branche + SHA court

### 4) Tags des images publiées
Deux tags sont poussés dans le GitLab Container Registry :
- `${CI_COMMIT_SHORT_SHA}`
- `${CI_COMMIT_REF_SLUG}-${CI_COMMIT_SHORT_SHA}`

Exemple de tag lisible :
- `dev-test-ci-a1b2c3d4`

Ce format permet d'identifier rapidement :
- la branche source
- le commit à l'origine de l'image

### 5) Artefact du stage build
Le job `build_image` publie un artefact `archive.zip` contenant :
- `build-metadata/pushed-images.txt`

Ce fichier liste les tags effectivement poussés vers le registre GitLab.

## Différences de configuration avec le projet Angular
Dans le projet Java :
- l'image Docker contient une application Spring Boot empaquetée en `.war` ;
- le `Dockerfile` réalise une phase de build Java puis une image runtime JRE ;
- le démarrage complet de l'image dépend d'un environnement applicatif plus riche qu'un front statique, notamment pour la base de données.

Cette différence explique pourquoi la validation fonctionnelle de l'image Java en CI est plus sensible à l'environnement que celle de l'image Angular.

## Points de vigilance appliqués
- Les identifiants du registre GitLab ne sont pas écrits en dur dans le pipeline.
- La connexion au registre passe par les variables CI/CD fournies par GitLab.
- Le push des images est limité aux pipelines déclenchés par `push`.
- La branche de test `dev/test_ci` peut être conservée pour valider ce stage avant merge sur `main`.

## Gestion des differences d'environnement entre local et CI
Le contexte local et le contexte GitLab CI presentent plusieurs differences qu'il faut anticiper pour produire une image portable. En local, l'application peut s'appuyer sur un fichier `.env`, sur des conteneurs lances manuellement et sur des services accessibles depuis le poste du developpeur. En CI, chaque job s'execute dans un conteneur ephemere et ne lit pas automatiquement les fichiers d'environnement locaux. Pour l'application Java, cela signifie en particulier que la base de donnees ne doit pas etre referencee en `localhost` dans un contexte conteneurise : il faut fournir une URL adaptee, basee sur le nom du service ou du conteneur PostgreSQL, via des variables d'environnement. Cette approche permet d'avoir un comportement coherent entre execution locale, test Docker et pipeline GitLab CI.

## Limite actuelle
Le stage `build` construit et publie l'image, mais il ne réalise pas encore de smoke test automatique du conteneur. Cette vérification pourra être ajoutée ensuite pour confirmer que l'image produite démarre correctement dans l'environnement CI.

## Validation locale de l'image Java (branche dev)
La validation locale permet de verifier que l'image publiee depuis la branche `dev/test_ci` demarre correctement avec sa base PostgreSQL avant merge sur `main`.

### Prerequis
- Docker Desktop demarre en local.
- Un compte GitLab avec acces au projet.
- Un token GitLab (PAT) avec au minimum le scope `read_registry`.

### Commandes de validation
1. Se connecter au GitLab Container Registry :

```bash
docker login registry.gitlab.com
```

Renseigner :
- Username : utilisateur GitLab
- Password : token PAT

2. Recuperer l'image Java de la branche de dev :

```bash
docker pull registry.gitlab.com/boncbonc-devops/proj4/devops_proj4_applicationjava:dev-test-ci-ee13efcb
```

3. Creer un reseau Docker local pour relier l'application et la base :

```bash
docker network create java-test-net
```

4. Lancer PostgreSQL avec les variables attendues par l'application :

```bash
docker run -d --name pg-test-local --network java-test-net -e POSTGRES_USER=workshops_user -e POSTGRES_PASSWORD=oc2026project4 -e POSTGRES_DB=workshopsdb postgres:13
```

5. Lancer l'application Java en pointant vers la base Docker :

```bash
docker run -d --name java-test-local --network java-test-net -p 8080:8080 -e SPRING_DATASOURCE_URL=jdbc:postgresql://pg-test-local:5432/workshopsdb -e SPRING_DATASOURCE_USERNAME=workshops_user -e SPRING_DATASOURCE_PASSWORD=oc2026project4 registry.gitlab.com/boncbonc-devops/proj4/devops_proj4_applicationjava:dev-test-ci-ee13efcb
```

6. Verifier le demarrage de l'application :

```bash
docker logs --tail 200 java-test-local
docker ps
```

Points attendus dans les logs :
- `Tomcat started on port 8080`
- `Started JavaBasicAppApplication`
- aucune erreur de connexion PostgreSQL

7. Verifier la reponse HTTP de l'application :

```bash
curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/
```

Code attendu : `200`

### Critere de succes
L'image Java de la branche de dev est validee si :
- le conteneur PostgreSQL demarre correctement ;
- le conteneur Java demarre sans erreur bloquante ;
- l'application se connecte a la base ;
- une requete HTTP locale retourne un code `200`.

### Nettoyage local

```bash
docker rm -f java-test-local pg-test-local
docker network rm java-test-net
```

## Résultat attendu atteint
- Le pipeline construit une image Docker.
- L'image est poussée dans le GitLab Container Registry.
- Les tags contiennent le SHA du commit et le nom de la branche.
- Le pipeline reste configurable via les variables GitLab CI/CD.

## Prochaine étape
Étape 4 : automatiser la release et la gestion de version, puis éventuellement compléter le pipeline avec un smoke test d'image ou un scan Trivy après build.
