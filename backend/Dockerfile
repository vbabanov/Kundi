FROM golang:1.25-alpine AS builder

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .

ARG TARGET=./cmd/api
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /out/app ${TARGET}

FROM alpine:3.20
RUN adduser -D -h /app appuser
WORKDIR /app
COPY --from=builder /out/app /app/app
COPY --from=builder /src/migrations /app/migrations
USER appuser
EXPOSE 8080
ENTRYPOINT ["/app/app"]
