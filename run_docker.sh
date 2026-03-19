#!/bin/bash
set -e

docker build -t toniedownloader .
docker compose down && docker compose up -d