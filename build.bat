docker stop bf2server
docker container rm bf2server
docker image build -t test .
docker run --name bf2server --hostname bf2server --network bridge --interactive --volume /E/Docker/container:/home/bf2/srv --privileged=true -p 4711:4711/tcp -p 4712:4712/tcp -p 16567:16567/udp -p 27901:27901/udp -p 29900:29900/udp test:latest