FROM ubuntu:24.04@sha256:69cecf4bbf72d2d44a9eef1b71fb98c7fb973d78af11399deccef19beb008ad9

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install --no-install-recommends -y \
    ca-certificates clang curl g++ git libc6-dev libfontconfig1-dev libgl1-mesa-dev \
    libglib2.0-dev libpci-dev libx11-dev libxcb1-dev libxext-dev lld llvm ninja-build \
    pkg-config python3 unzip xz-utils && rm -rf /var/lib/apt/lists/*
