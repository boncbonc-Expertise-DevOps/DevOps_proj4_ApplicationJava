#!/bin/bash
# Script pour taguer l'image Docker avec la version sémantique après une release semantic-release
set -e

VERSION=$1

if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>"
  exit 1
fi

if [ -z "$CI_REGISTRY_IMAGE" ] || [ -z "$CI_REGISTRY_USER" ] || [ -z "$CI_REGISTRY_PASSWORD" ] || [ -z "$CI_REGISTRY" ]; then
  echo "Variables Docker registry non définies, le retag Docker est ignoré."
  exit 0
fi

if [ -z "$CI_COMMIT_SHORT_SHA" ]; then
  echo "CI_COMMIT_SHORT_SHA non défini, impossible de déterminer l'image source."
  exit 1
fi

SOURCE_IMAGE="$CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA"
VERSION_IMAGE="$CI_REGISTRY_IMAGE:$VERSION"
LATEST_IMAGE="$CI_REGISTRY_IMAGE:latest"

echo "Connexion au registry $CI_REGISTRY..."
echo "$CI_REGISTRY_PASSWORD" | docker login -u "$CI_REGISTRY_USER" --password-stdin "$CI_REGISTRY"

echo "Récupération de l'image source : $SOURCE_IMAGE..."
docker pull "$SOURCE_IMAGE"

echo "Tagage de $SOURCE_IMAGE en $VERSION_IMAGE..."
docker tag "$SOURCE_IMAGE" "$VERSION_IMAGE"
docker push "$VERSION_IMAGE"

echo "Tagage de $SOURCE_IMAGE en $LATEST_IMAGE..."
docker tag "$SOURCE_IMAGE" "$LATEST_IMAGE"
docker push "$LATEST_IMAGE"

echo "Images Docker taguées avec la version $VERSION"
