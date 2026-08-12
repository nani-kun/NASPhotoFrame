FROM continuumio/miniconda3:latest

# This image is already present on the NAS and includes Python plus the
# OpenSSH client, so deployment does not depend on the failing fnOS mirror.
RUN command -v python3 && command -v ssh
WORKDIR /app
COPY server.py index.html ./
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

ENV PORT=8787 IPAD_HOST=192.168.1.100 IPAD_USER=root SSH_DIR=/data/ssh
EXPOSE 8787
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
