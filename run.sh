#!/usr/bin/env bash
# TeachFi landing page — build & serve helper
#
# Usage:
#   ./run.sh           build the site into _site/
#   ./run.sh serve     build and start the dev server (auto-frees the port)
#   ./run.sh stop      kill anything listening on the dev-server port
#   ./run.sh clean     remove _site/ and .jekyll-cache/
#   ./run.sh pdf       regenerate the all-pages PDF
#
# Environment:
#   PORT=5000 ./run.sh serve    use a custom port (default: 4000)
#
set -euo pipefail

# Always run from the script's own directory so relative paths work
cd "$(dirname "$0")"

# Silence the harmless Nix-Ruby "already initialized constant Gem::Platform" warnings
export RUBYOPT="-W0"

CMD="${1:-build}"
PORT="${PORT:-4000}"

# Free up $PORT if something is already listening on it (usually a previous
# `jekyll serve` from another copy of the site). Prints a friendly note.
free_port() {
  local port="$1"
  local pids
  pids=$(lsof -ti tcp:"$port" 2>/dev/null || true)
  if [ -n "$pids" ]; then
    echo "→ Port $port is in use by PID(s): $pids — stopping them..."
    kill $pids 2>/dev/null || true
    sleep 1
    # Force-kill if still alive
    pids=$(lsof -ti tcp:"$port" 2>/dev/null || true)
    if [ -n "$pids" ]; then
      kill -9 $pids 2>/dev/null || true
      sleep 1
    fi
  fi
}

ensure_deps() {
  if [ ! -d vendor/bundle ]; then
    echo "→ Installing Ruby gems (first run)..."
    bundle config set --local path 'vendor/bundle'
    bundle install
  fi
}

case "$CMD" in
  build)
    ensure_deps
    echo "→ Building site..."
    bundle exec jekyll build
    echo "✓ Done. Output in _site/"
    ;;

  serve)
    ensure_deps
    free_port "$PORT"
    echo "→ Starting dev server at http://127.0.0.1:$PORT"
    bundle exec jekyll serve --host 127.0.0.1 --port "$PORT" --livereload
    ;;

  stop)
    free_port "$PORT"
    echo "✓ Port $PORT is free."
    ;;

  clean)
    echo "→ Cleaning build artifacts..."
    rm -rf _site .jekyll-cache
    echo "✓ Clean."
    ;;

  pdf)
    ensure_deps
    echo "→ Building site..."
    bundle exec jekyll build

    # Start a temporary server if 4000 isn't already responding
    if ! curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:4000/ | grep -q '^2'; then
      echo "→ Starting temporary server..."
      bundle exec jekyll serve --host 127.0.0.1 --port 4000 --no-watch --skip-initial-build >/dev/null 2>&1 &
      SERVER_PID=$!
      trap 'kill $SERVER_PID 2>/dev/null || true' EXIT
      # Wait up to 10s for server to answer
      for _ in $(seq 1 20); do
        if curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:4000/ | grep -q '^2'; then
          break
        fi
        sleep 0.5
      done
    fi

    echo "→ Generating PDF (requires Playwright + pdfunite)..."
    python3 /tmp/gen_pdf.py
    ;;

  *)
    cat <<EOF >&2
Usage: $0 <command>

Commands:
  build     Build the site into _site/ (default)
  serve     Build and start the dev server at http://127.0.0.1:\$PORT
  stop      Free the dev-server port (kills any listener)
  clean     Remove _site/ and .jekyll-cache/
  pdf       Regenerate assets/teachfi-website.pdf

Environment:
  PORT      Dev-server port (default: 4000)
EOF
    exit 1
    ;;
esac
