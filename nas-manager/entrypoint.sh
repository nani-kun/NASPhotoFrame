#!/bin/sh
set -eu

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
if [ ! -f "$SSH_DIR/id_rsa" ]; then
    ssh-keygen -q -t rsa -b 2048 -N '' -f "$SSH_DIR/id_rsa"
fi
touch "$SSH_DIR/known_hosts"
chmod 600 "$SSH_DIR/id_rsa" "$SSH_DIR/known_hosts"
exec python3 /app/server.py
