bf2-docker
===

Dockerized Battlefield 2. Based on [insanity54/bf42-dock](https://github.com/insanity54/bf42-dock) by Chris Grimmett. It runs the Battlefield 2 server 1.5 installer and adds the BF2Hub server files to support online play.


Prerequisites
---

* [Docker](https://docker.com/)


Building
---

    docker build -t nihlen/bf2-docker https://github.com/nihlen/bf2-docker.git
    docker run --name bf2server --interactive --volume <host directory>:/home/bf2/srv -p 4711:4711/tcp -p 4712:4712/tcp -p 16567:16567/udp -p 27901:27901/udp -p 29900:29900/udp nihlen/bf2-docker:latest
