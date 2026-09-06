# PoE1 Path of Building MCP server — headless, real calculation engine.
#
# Builds:
#   1. LuaJIT, from the exact upstream commit PathOfBuildingCommunity's own
#      official Dockerfile pins (this is the commit where compound-assignment
#      syntax, e.g. `count += 1`, landed upstream — PoB's Lua code needs it,
#      and Debian/Ubuntu's packaged LuaJIT predates it).
#   2. lua-utf8, the native module PoB's Windows runtime ships as a .dll but
#      that has no Linux build in the repo — compiled here from source.
#   3. A PoE1 PathOfBuildingCommunity checkout (dev branch = the live game data
#      + the real Lua calculation engine, MIT-licensed, no game client needed).
#   4. ianderse/pob-mcp, the MCP server that drives that engine headlessly.
#
# This server speaks MCP over stdio only (no HTTP/SSE transport) — see
# README.md for what that means for how you actually run this container.

# ---- Stage 1: LuaJIT, pinned to the commit PoB's own Dockerfile uses ----
FROM ubuntu:24.04 AS luajit-build
RUN apt-get update && apt-get install -y --no-install-recommends \
      git build-essential ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /opt
RUN git clone https://github.com/LuaJIT/LuaJIT.git \
    && cd LuaJIT \
    && git checkout 2460b3ff93a1c955de3d62cfc825de7d68dc272e \
    && make -j"$(nproc)" \
    && make install PREFIX=/usr/local

# ---- Stage 2: lua-utf8 native module, built against the LuaJIT headers above ----
FROM luajit-build AS luautf8-build
WORKDIR /opt
RUN git clone --depth 1 https://github.com/starwing/luautf8.git \
    && cd luautf8 \
    && gcc -O2 -fPIC -I/usr/local/include/luajit-2.1 -c lutf8lib.c -o lutf8lib.o \
    && gcc -shared -o lua-utf8.so lutf8lib.o

# ---- Stage 3: final image ----
FROM node:22-bookworm-slim AS final
RUN apt-get update && apt-get install -y --no-install-recommends \
      git ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && ldconfig

# LuaJIT runtime (binary + headers + bundled jit/*.lua modules)
COPY --from=luajit-build /usr/local/bin/luajit* /usr/local/bin/
COPY --from=luajit-build /usr/local/lib/libluajit* /usr/local/lib/
COPY --from=luajit-build /usr/local/include/luajit-2.1 /usr/local/include/luajit-2.1
COPY --from=luajit-build /usr/local/share/luajit-2.1 /usr/local/share/luajit-2.1
RUN ldconfig

# lua-utf8 native module, placed where LUA_CPATH (set below) will find it
COPY --from=luautf8-build /opt/luautf8/lua-utf8.so /opt/lua-modules/lua-utf8.so

# PoE1 Path of Building — official PathOfBuildingCommunity repo, dev branch.
# ARG lets you pin a specific commit/tag at build time instead of always
# tracking the moving `dev` branch (see README.md "Updating for a new league").
ARG POB_REF=dev
RUN git clone https://github.com/PathOfBuildingCommunity/PathOfBuilding.git /opt/PathOfBuilding \
    && cd /opt/PathOfBuilding && git checkout "${POB_REF}"

# pob-mcp itself
RUN git clone https://github.com/ianderse/pob-mcp.git /opt/pob-mcp
WORKDIR /opt/pob-mcp
RUN npm install && npm run build

ENV POB_LUA_ENABLED=true \
    POB_PATH=/opt/PathOfBuilding/src \
    POB_CMD=luajit \
    POB_DIRECTORY=/data/builds \
    LUA_CPATH="/opt/lua-modules/?.so;;" \
    POB_AUTO_UPDATE=true

VOLUME ["/data/builds"]

COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

WORKDIR /opt/pob-mcp
ENTRYPOINT ["/opt/entrypoint.sh"]
