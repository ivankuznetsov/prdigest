FROM golang:1.22-alpine AS build
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 go build -o /out/prdigest ./cmd/prdigest
FROM alpine:3.20
RUN adduser -D -H prdigest
COPY --from=build /out/prdigest /usr/local/bin/prdigest
USER prdigest
ENTRYPOINT ["prdigest"]
CMD ["serve", "--config", "/etc/prdigest/config.yml"]
