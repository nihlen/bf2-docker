bf2-docker
===

Dockerized Battlefield 2. Based on [insanity54/bf42-dock](https://github.com/insanity54/bf42-dock) by Chris Grimmett.


Prerequisites
---

* [Docker](https://docker.com/)


Building
---

    docker image build -t bf2 .
    docker run --name bf2server --hostname bf2server --network bridge --interactive --volume <host directory>:/home/bf2/srv --privileged=true -p 4711:4711/tcp -p 4712:4712/tcp -p 16567:16567/udp -p 27901:27901/udp -p 29900:29900/udp bf2:latest
