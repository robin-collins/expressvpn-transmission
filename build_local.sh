#!/bin/bash
# Build both images locally (no registry push). Run from the repo root.
set -e
docker build --pull -t speeddemonau/expressvpn:latest expressvpn
docker build -t speeddemonau/expressvpn-transmission:latest expressvpn-transmission
