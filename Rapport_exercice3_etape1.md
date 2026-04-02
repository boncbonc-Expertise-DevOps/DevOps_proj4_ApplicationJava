# Rapport exercice 3 — Etape 1 (Kubernetes sur Minikube)

## Objectif
Deployer les deux applications sur un cluster Kubernetes local (Minikube) a partir des manifestes du dossier `k8s/`.

## Contexte
- Projet frontend : Angular
- Projet backend : Java Spring Boot + PostgreSQL
- Images publiees dans GitLab Container Registry

## Travail realise

### 1) Revue et completion des manifestes
Les TODO ont ete completes dans les dossiers `k8s/` des deux projets.

#### Frontend Angular
Fichiers mis a jour :
- `DevOps_proj4_ApplicationAngular/k8s/deployment-app.yaml`
- `DevOps_proj4_ApplicationAngular/k8s/service-app.yaml`

Actions appliquees :
- Ajout de l'image GitLab Registry dans le Deployment
- Ajout de `imagePullSecrets` pour les images privees
- Correction du port applicatif cible : `targetPort: 8080` (coherent avec le conteneur)

#### Backend Java + PostgreSQL
Fichiers mis a jour :
- `DevOps_proj4_ApplicationJava/k8s/deployment-app.yaml`
- `DevOps_proj4_ApplicationJava/k8s/deployment-db.yaml`
- `DevOps_proj4_ApplicationJava/k8s/pvc-db.yaml` (nouveau)
- `deploy-minikube.sh`
- `.env_minikube`

Actions appliquees :
- Ajout des images GitLab Registry dans les Deployments
- Ajout de `imagePullSecrets` pour l'application Java
- Configuration des variables `SPRING_DATASOURCE_*`
- Configuration des variables Postgres `POSTGRES_*`
- Creation dynamique du Secret DB et de la ConfigMap DB via `deploy-minikube.sh`
- Ajout d'un `PersistentVolumeClaim` pour la persistence PostgreSQL
- Montage du volume sur `/var/lib/postgresql/data`

### 2) Verification des marqueurs techniques dans les YAML
- Plus aucun TODO dans les manifests
- Selectors des Services alignes avec les labels de Pods
- Variables DB frontend/backend conformes
- PVC present et reference par le Deployment PostgreSQL

## Etapes d'execution Minikube (a lancer)

Le deploiement final a ete valide via un script local unique qui centralise les namespaces, les secrets, les manifests et les verifications de rollout.

### 1) Demarrer le cluster
```bash
minikube start --driver=docker --cpus=4 --memory=8192 --kubernetes-version=v1.30.11 --wait=apiserver,system_pods --wait-timeout=10m
kubectl get nodes
```

### 2) Preparer les variables locales
```bash
notepad .env_minikube
```

Variables renseignees :
- `GITLAB_USER`
- `GITLAB_EMAIL`
- `GITLAB_REGISTRY_TOKEN` (ou saisie masquee au lancement)
- `POSTGRES_DB`
- `POSTGRES_USER`
- `POSTGRES_PASSWORD`

### 3) Lancer le deploiement complet
```bash
bash deploy-minikube.sh
```

Le script effectue :
- creation des namespaces `angular-app` et `java-app`
- creation du secret `gitlab-registry-secret`
- creation du secret `workshop-organizer-db-secret`
- creation de la ConfigMap `workshop-organizer-db-config`
- application des manifests Angular, PostgreSQL et Java
- verification des rollouts

### 4) Verifier l'etat du cluster
```bash
kubectl get pods -n angular-app
kubectl get pods -n java-app
kubectl get svc -n angular-app
kubectl get svc -n java-app
```

Pods valides observes :
- `olympic-games-app-deployment` : `Running`
- `workshop-organizer-app-deployment` : `Running`
- `workshop-organizer-db-deployment` : `Running`

### 5) Tester l'acces local

Sous Windows avec Minikube + driver Docker, `minikube service --url` ouvre un tunnel temporaire et garde le terminal occupe. Pour un acces stable en developpement, le port-forward a ete retenu.

```bash
kubectl port-forward -n angular-app svc/olympic-games-app-service 8081:80
kubectl port-forward -n java-app svc/workshop-organizer-app-service 8080:8080
```

URLs stables de validation :
- Angular : `http://localhost:8081`
- Java : `http://localhost:8080`

## Operations Minikube (arreter/supprimer proprement)

### Arret propre du cluster
```bash
minikube stop
```

### Suppression propre du cluster (reset complet)
```bash
minikube delete -p minikube
```

### Redemarrage propre (version Kubernetes stable)
```bash
minikube start --driver=docker --cpus=4 --memory=8192 --kubernetes-version=v1.30.11 --wait=apiserver,system_pods --wait-timeout=10m
minikube status
kubectl get nodes
```

### Si le cluster est casse (apiserver/kubelet down)
```bash
minikube delete -p minikube
minikube start --driver=docker --cpus=4 --memory=8192 --kubernetes-version=v1.30.11 --wait=apiserver,system_pods --wait-timeout=10m
kubectl get nodes
```

## Debug rapide
```bash
kubectl logs deployment/olympic-games-app-deployment -n angular-app
kubectl logs deployment/workshop-organizer-db-deployment -n java-app
kubectl logs deployment/workshop-organizer-app-deployment -n java-app
kubectl describe pod -n angular-app
kubectl describe pod -n java-app
```

## Validation des attendus de l'etape 1
- Minikube et kubectl installes et fonctionnels
- TODO complets dans les manifests
- Frontend Angular deploye et accessible
- Backend Spring Boot deploye avec PostgreSQL
- Services relies aux bons selectors
- Variables de connexion DB configurees
- Persistence PostgreSQL active via PVC
- Applications testables independamment

## Resultat observe
- Frontend Angular accessible en local via `http://localhost:8081`
- Backend Java accessible en local via `http://localhost:8080`
- Base PostgreSQL demarree dans le namespace `java-app`
- Deploiement local reproductible via `deploy-minikube.sh`

## Suite prevue
Etape 2 : Transformer ces manifests en charts Helm variabilises (values par environnement).