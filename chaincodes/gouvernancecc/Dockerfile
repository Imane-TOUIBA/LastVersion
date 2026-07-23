FROM golang:1.22-alpine AS builder
WORKDIR /chaincode
COPY . .
RUN go mod tidy && go build -o chaincode .
FROM alpine:latest
WORKDIR /root/
COPY --from=builder /chaincode/chaincode .
EXPOSE 9999
CMD ["./chaincode"]
