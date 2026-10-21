#!/bin/bash
# Build both images locally (no registry push). Run from the repo root.
# Tagged :local, which does not exist on Docker Hub: a stray pull fails instead of
# silently replacing these with the stale (non fail-closed) 2023 Hub images.
set -e
docker build --pull -t speeddemonau/expressvpn:local expressvpn
docker build -t speeddemonau/expressvpn-transmission:local expressvpn-transmission
