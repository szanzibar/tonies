#!/bin/bash
set -e

docker build -t tonie .
docker compose down && docker compose up -d
