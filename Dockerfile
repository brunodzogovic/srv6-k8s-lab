# Stage 1: Build FRR from source
FROM ubuntu:24.04 as builder

ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    git autoconf automake libtool make gcc \
    libreadline-dev texinfo libjson-c-dev \
    bison flex python3-dev libsystemd-dev \
    libcap-dev libsnmp-dev perl pkg-config cmake \
    libunbound-dev libzmq3-dev libprotobuf-c-dev \
    protobuf-c-compiler libpam0g-dev libgcrypt20-dev \
    libelf-dev iproute2 wget ca-certificates \
    libpcre2-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Build latest libyang (>=2.1.128 required for FRR 10.3)
WORKDIR /usr/src
RUN git clone https://github.com/CESNET/libyang.git && \
    cd libyang && \
    git checkout v2.1.148 && \
    mkdir build && cd build && \
    cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib .. && \
    make -j$(nproc) && \
    make install

# Clone FRR source
WORKDIR /usr/src
RUN git clone https://github.com/FRRouting/frr.git
WORKDIR /usr/src/frr

# Checkout stable 10.3 branch
RUN git checkout stable/10.3

# Bootstrap and configure
RUN ./bootstrap.sh
RUN ./configure \
    --prefix=/usr \
    --sysconfdir=/etc/frr \
    --sbindir=/usr/lib/frr \
    --localstatedir=/var/run/frr \
    --enable-user=frr \
    --enable-multipath=64 \
    --enable-vtysh

# Build and install
RUN make -j$(nproc)
RUN make install

# Optional: Strip binaries to reduce image size
RUN strip /usr/lib/frr/* || true
RUN strip /usr/bin/vtysh || true

# Stage 2: Runtime container
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    iproute2 libjson-c5 libreadline8 libprotobuf-c1 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create required users and groups
RUN groupadd -r frr && useradd -r -g frr frr && groupadd -r frrvty

# Create necessary runtime directories with correct permissions
RUN mkdir -p /etc/frr /var/run/frr /var/tmp/frr /var/log/frr && \
    chown -R frr:frr /etc/frr /var/run/frr /var/tmp/frr /var/log/frr

# Copy only needed FRR binaries
COPY --from=builder /usr/lib/frr /usr/lib/frr
COPY --from=builder /usr/bin/vtysh /usr/bin/vtysh
COPY --from=builder /usr/lib/systemd/system /usr/lib/systemd/system

# Copy FRR shared libraries
COPY --from=builder /usr/lib/libfrr.so.0 /usr/lib/libfrr.so.0
COPY --from=builder /usr/lib/libfrr.so /usr/lib/libfrr.so

# Copy libyang shared libraries (clean)
COPY --from=builder /usr/lib/libyang.so* /usr/lib/

# Copy example daemons file
COPY --from=builder /usr/src/frr/tools/etc/frr/daemons /etc/frr/daemons

# Environment for FRR
ENV FRR_USER=frr
ENV FRR_GROUP=frr

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/entrypoint.sh"]
