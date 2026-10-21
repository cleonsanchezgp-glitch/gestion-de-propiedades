FROM rust:1.95-bookworm AS build
WORKDIR /build
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY migrations ./migrations
RUN cargo build --locked --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build /build/target/release/propiedades-backend /usr/local/bin/propiedades-backend
USER 65532:65532
ENV BACKEND_BIND=0.0.0.0:8080
EXPOSE 8080
ENTRYPOINT ["propiedades-backend"]
