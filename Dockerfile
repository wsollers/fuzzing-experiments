# fuzzing-experiments — Linux build + fuzz container
# Clang 17 | CMake | Ninja | CodeQL CLI | OpenGrep | LLVM coverage tools

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LLVM_VERSION=17
ENV CODEQL_VERSION=2.16.6
ENV CC=clang-17
ENV CXX=clang++-17

# ── Base packages ────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget curl git ca-certificates gnupg lsb-release \
    build-essential ninja-build cmake \
    python3 python3-pip \
    jq unzip zip \
    libssl-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# ── LLVM / Clang 17 ──────────────────────────────────────────────────────────
RUN wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key \
      | gpg --dearmor -o /usr/share/keyrings/llvm-archive-keyring.gpg \
  && echo "deb [signed-by=/usr/share/keyrings/llvm-archive-keyring.gpg] \
      https://apt.llvm.org/jammy/ llvm-toolchain-jammy-${LLVM_VERSION} main" \
    > /etc/apt/sources.list.d/llvm.list \
  && apt-get update && apt-get install -y --no-install-recommends \
    clang-${LLVM_VERSION} \
    llvm-${LLVM_VERSION} \
    llvm-${LLVM_VERSION}-tools \
    lld-${LLVM_VERSION} \
    libfuzzer-${LLVM_VERSION}-dev \
    clang-tools-${LLVM_VERSION} \
  && rm -rf /var/lib/apt/lists/* \
  && update-alternatives --install /usr/bin/clang   clang   /usr/bin/clang-${LLVM_VERSION}   100 \
  && update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-${LLVM_VERSION} 100 \
  && update-alternatives --install /usr/bin/llvm-cov      llvm-cov      /usr/bin/llvm-cov-${LLVM_VERSION}      100 \
  && update-alternatives --install /usr/bin/llvm-profdata llvm-profdata /usr/bin/llvm-profdata-${LLVM_VERSION} 100

# ── CodeQL CLI ────────────────────────────────────────────────────────────────
RUN ARCH=$(uname -m | sed 's/x86_64/linux64/;s/aarch64/linux-arm64/') \
  && wget -q \
    "https://github.com/github/codeql-action/releases/download/codeql-bundle-v${CODEQL_VERSION}/codeql-bundle-${ARCH}.tar.gz" \
    -O /tmp/codeql.tar.gz \
  && tar -xzf /tmp/codeql.tar.gz -C /opt \
  && rm /tmp/codeql.tar.gz
ENV PATH="/opt/codeql:${PATH}"

# ── OpenGrep (Semgrep-compatible, open-source fork) ───────────────────────────
RUN pip3 install --no-cache-dir opengrep-cli || pip3 install --no-cache-dir semgrep

# ── lcov for HTML coverage (supplementary to llvm-cov) ───────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends lcov \
  && rm -rf /var/lib/apt/lists/*

# ── Project sources ───────────────────────────────────────────────────────────
WORKDIR /workspace
COPY . /workspace

# ── Build (fuzzer + sanitizer instrumented) ───────────────────────────────────
RUN cmake -S . -B build \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DENABLE_FUZZING=ON \
      -DENABLE_ASAN=ON \
      -DENABLE_UBSAN=ON \
  && cmake --build build --parallel $(nproc)

# ── Entry point ───────────────────────────────────────────────────────────────
ENTRYPOINT ["/workspace/scripts/run_fuzz.sh"]
