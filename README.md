# Tonie

A web app for searching YouTube Music and podcasts, then uploading them to your [Creative Tonie](https://tonies.com).

## Features

- Search YouTube Music for albums and artists
- Search and download podcast episodes
- Upload audio to any Creative Tonie on your account
- Reorder and manage Tonie chapters
- Save favorite artists and podcasts
- PWA support (install as a mobile app)
- German and English UI

## Requirements

- Elixir 1.18+ / OTP 27+
- A [tonie.cloud](https://my.tonies.com) account with Creative Tonies
- ffmpeg (`brew install ffmpeg`) — downloaded automatically in Docker

## Setup

```bash
cp .env.example .env
# Edit .env with your tonie.cloud credentials

mix setup
mix phx.server
```

Visit [localhost:4000](http://localhost:4000).

## Configuration

All configuration is via environment variables (or `.env` file):

| Variable | Required | Default | Description |
|---|---|---|---|
| `TONIE_USERNAME` | Yes | — | Your tonie.cloud email |
| `TONIE_PASSWORD` | Yes | — | Your tonie.cloud password |
| `LANGUAGE` | No | `de` | UI language: `de` or `en` |
| `SECRET_KEY_BASE` | Prod | — | Generate with `mix phx.gen.secret` |
| `PHX_HOST` | Prod | — | Public hostname |
| `PORT` | No | `4000` | HTTP port |

## Deploy with Docker

```bash
# Build the image
docker build -t tonie .

# Run with docker compose
docker compose up -d
```

Make sure your `.env` file includes `SECRET_KEY_BASE` and `PHX_HOST` for production.

You can also use `./deploy.sh` which builds and restarts in one step.
