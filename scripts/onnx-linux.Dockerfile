FROM ubuntu:24.04@sha256:69cecf4bbf72d2d44a9eef1b71fb98c7fb973d78af11399deccef19beb008ad9

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install --no-install-recommends -y \
    ca-certificates clang-18 cmake g++-13 git ninja-build patch \
    python3 python3-jinja2 python3-packaging && \
    rm -rf /var/lib/apt/lists/*
ENV CC=clang-18 CXX=clang++-18