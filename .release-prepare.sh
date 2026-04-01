#!/bin/bash
# Script pour mettre à jour la version dans build.gradle pour semantic-release

set -e

VERSION=$1

if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>"
  exit 1
fi

if [ ! -f build.gradle ]; then
  echo "Erreur: build.gradle non trouvé"
  exit 1
fi

# Mettre à jour la version dans build.gradle
sed -i.bak "s/^version = '[^']*'/version = '$VERSION'/" build.gradle

# Supprimer le fichier de sauvegarde (Windows: .bak.bak, Linux: .bak)
rm -f build.gradle.bak

echo "Version mise a jour vers $VERSION dans build.gradle"
