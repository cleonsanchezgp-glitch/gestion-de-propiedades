FROM rust:1.95-bookworm AS build
ARG AELIUM_RELEASE_ID=local
ARG AELIUM_BUILD_ID=local
ARG AELIUM_API_CONTRACT=propiedades-v3
ENV AELIUM_RELEASE_ID=${AELIUM_RELEASE_ID} AELIUM_BUILD_ID=${AELIUM_BUILD_ID} AELIUM_API_CONTRACT=${AELIUM_API_CONTRACT}
WORKDIR /build
COPY Cargo.toml Cargo.lock build.rs ./
COPY src ./src
COPY migrations ./migrations
RUN cargo build --locked --release

FROM debian:bookworm-slim
LABEL org.opencontainers.image.source="https://github.com/cleonsanchezgp-glitch/gestion-de-propiedades"
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build /build/target/release/propiedades-backend /usr/local/bin/propiedades-backend
USER 65532:65532
ENV BACKEND_BIND=0.0.0.0:8080
EXPOSE 8080
ENTRYPOINT ["propiedades-backend"]
CMD ["--container-serve"]
