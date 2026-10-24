# Multiplayer server in a container (a grown-up runs this on a cloud computer).
#   docker build -t blockcraft-server .
#   docker run -d --restart unless-stopped -p 22122:22122/udp blockcraft-server
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends love && rm -rf /var/lib/apt/lists/*
COPY . /game
ENV SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy XDG_DATA_HOME=/data
EXPOSE 22122/udp
VOLUME ["/data"]
CMD ["love", "/game", "--server"]
