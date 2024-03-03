FROM golang:latest
LABEL maintainer="Chris Schmich <schmch@gmail.com>"
RUN go install -a -v github.com/go-bindata/go-bindata/...@latest
COPY . /src
WORKDIR /src
CMD ["/bin/bash", "-c", "/src/build-linux.sh"]
