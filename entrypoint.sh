#!/bin/sh
set -e

# Keep the PoE1 game-data checkout current at container start, so you don't
# have to rebuild the image every league. Set POB_AUTO_UPDATE=false to pin
# to whatever was baked in at build time instead (e.g. if you built with
# --build-arg POB_REF=<a specific tag/commit>).
if [ "${POB_AUTO_UPDATE:-true}" = "true" ] && [ -d /opt/PathOfBuilding/.git ]; then
  echo "[entrypoint] updating PathOfBuilding checkout..." >&2
  git -C /opt/PathOfBuilding fetch --depth 1 origin dev 2>&1 | sed 's/^/[entrypoint] /' >&2 || true
  git -C /opt/PathOfBuilding checkout dev 2>&1 | sed 's/^/[entrypoint] /' >&2 || true
  git -C /opt/PathOfBuilding reset --hard origin/dev 2>&1 | sed 's/^/[entrypoint] /' >&2 || \
    echo "[entrypoint] warning: could not update PathOfBuilding checkout, continuing with the version baked into the image" >&2
fi

mkdir -p "${POB_DIRECTORY:-/data/builds}"

exec node build/index.js "$@"
