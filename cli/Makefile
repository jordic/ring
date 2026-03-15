build:
	go build -o dist/ring ./cmd/

build-arm64:
	GOOS=darwin GOARCH=arm64 go build -o dist/ring-arm64 ./cmd/

build-amd64:
	GOOS=darwin GOARCH=amd64 go build -o dist/ring-amd64 ./cmd/

build-all: build-arm64 build-amd64

install: build
	cp dist/ring /usr/local/bin/ring

vet:
	go vet ./...

.PHONY: build build-arm64 build-amd64 build-all install vet
