docker stop bf2server
docker container rm bf2server
docker image build -t bf2 .
docker run --name bf2server -it -v e:/docker/container6:/home/bf2/srv -p 4711:4711/tcp -p 4712:4712/tcp -p 16567:16567/udp -p 27901:27901/udp -p 29900:29900/udp bf2:latest
