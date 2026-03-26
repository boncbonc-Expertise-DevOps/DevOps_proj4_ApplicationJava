# Préparation image Docker App Java

## 1) Dockerfile multi-stage (Gradle build + JRE runtime) + `.dockerignore`

Points confirmés pour la conteneurisation :

- Build Java avec Gradle/JDK 21 :
  ```bash
  ./gradlew clean compileJava
  ```
- Tests :
  ```bash
  ./gradlew clean test
  ```
- Packaging :
  ```bash
  ./gradlew bootWar
  ```
- Base DB recommandée : PostgreSQL 13
- Lancement attendu via Compose :
  ```bash
  docker compose up -d
  ```

Variables DB côté app :

- `SPRING_DATASOURCE_URL`
- `SPRING_DATASOURCE_USERNAME`
- `SPRING_DATASOURCE_PASSWORD`

Architecture Docker retenue :

- Stage build : image JDK 21 (Alpine) pour compiler et packager (`./gradlew clean test bootWar`)
- Stage runtime : image Eclipse Temurin JRE (Alpine), copie du binaire final et lancement de l’app

Test :

```bash
docker build -t workshop-organizer:local .
```

Note : problème de fin de ligne sur `gradlew`, corrigé avec :

```bash
sed -i 's/\r$//' gradlew
```

Résultat : compilation OK.

Remarque : exécuter l’image seule reste limité sans `docker-compose` (réseau + DB manquants).

---

## 2) Docker Compose avec 2 services (app + postgres)

Configuration :

- Service `db` (`postgres:13`) + variables `POSTGRES_*`
- Service `app` + variables :
  - `SPRING_DATASOURCE_URL`
  - `SPRING_DATASOURCE_USERNAME`
  - `SPRING_DATASOURCE_PASSWORD`

Vérification :

```bash
docker compose config
```

Extrait attendu (résumé) :

```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    image: workshop-organizer:local
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://db:5432/workshopsdb
      SPRING_DATASOURCE_USERNAME: workshops_user
      SPRING_DATASOURCE_PASSWORD: oc2024
    ports:
      - "8080:8080"
    networks:
      - workshop-net

  db:
    image: postgres:13
    environment:
      POSTGRES_DB: workshopsdb
      POSTGRES_USER: workshops_user
      POSTGRES_PASSWORD: oc2024
    networks:
      - workshop-net

networks:
  workshop-net:
    name: workshop-net
```

Attendu : services `app` + `db` présents, variables visibles.

---

## 3) Persistance PostgreSQL

Ajout d’un volume nommé `workshop-db-data` monté sur `/var/lib/postgresql/data`.

Vérification :

```bash
docker compose config
docker compose up -d db
docker volume ls | grep workshop
```

Extrait attendu (résumé) :

```yaml
services:
  db:
    image: postgres:13
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
    name: workshop-db-data
```

Attendu : volume bien créé et persistant.

---

## 4) Healthcheck PostgreSQL + orchestration de démarrage

Ajouts :

- `healthcheck` sur `db` via `pg_isready`
- `depends_on` côté `app` avec condition `service_healthy`

Vérification :

```bash
docker compose config
docker compose up -d --build
docker compose ps
```

Extrait attendu (résumé) :

```yaml
services:
  app:
    depends_on:
      db:
        condition: service_healthy

  db:
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U workshops_user -d workshopsdb"]
      interval: 10s
      timeout: 5s
      retries: 5
```

Sortie attendue de `docker compose ps` :

- `db` : healthy
- `app` : Up

---

## 5) Validation bout en bout

```bash
docker compose up -d --build
curl -i http://localhost:8080
docker compose logs -f app db
```

Critère final : API accessible sur `http://localhost:8080`.

---

## 6) Nettoyage / relance

Arrêt :

```bash
docker compose down
```

Reset complet (si nécessaire) :

```bash
docker compose down -v --remove-orphans
```

Relance :

```bash
docker compose up -d --build
curl -i http://localhost:8080
```
## 6) Scan Trivy sur image locale workshop-organizer:local

workshop-organizer:local (alpine 3.23.3)
========================================
Image OS Alpine de l’app : 8 vulnérabilités (1 critique, 3 hautes, 4 moyennes).
Dépendances Java dans app.war : 34 vulnérabilités (1 critique, 14 hautes, 11 moyennes, 8 basses).

## 6) Scan Trivy sur image locale postgres
Image postgres:13 (Debian 13.1) : 204 vulnérabilités (3 critiques, 24 hautes, 52 moyennes, 124 basses, 1 inconnue).
Binaire gosu : 19 vulnérabilités.
1 secret détecté : /etc/ssl/private/ssl-cert-snakeoil.key.


