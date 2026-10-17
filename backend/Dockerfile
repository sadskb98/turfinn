FROM golang:1.25-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /turfinn-api ./cmd/api
RUN CGO_ENABLED=0 GOOS=linux go build -o /turfinn-worker ./cmd/worker

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata
WORKDIR /app
COPY --from=builder /turfinn-api .
COPY --from=builder /turfinn-worker .
COPY --from=builder /app/.env.example .env
EXPOSE 8080
CMD ["./turfinn-api"]
