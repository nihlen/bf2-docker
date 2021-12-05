docker stop bf2server
REM docker image rm bf2
REM docker image prune
docker container rm bf2server
docker image build -t bf2 ./images/default
docker run --name bf2server --restart on-failure -it -v e:/docker/container10/server:/home/bf2/srv -v e:/docker/container10/volume:/volume -p 8000:80/tcp -p 4711:4711/tcp -p 4712:4712/tcp -p 16567:16567/udp -p 27901:27901/udp -p 29900:29900/udp --env-file ./local.env bf2:latest
REM docker exec -i -t bf2server /bin/bash
