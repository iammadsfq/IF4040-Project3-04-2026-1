#!/usr/bin/env bash
set -e

mkdir -p data/raw
curl -L -C - -o data/raw/indonesia-latest.osm.pbf https://download.geofabrik.de/asia/indonesia-latest.osm.pbf