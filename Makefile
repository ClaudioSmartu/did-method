.PHONY: all
.DEFAULT_GOAL := help
BINARY_NAME=didctl
DOCKER_IMAGE=didctl
VERSION_TAG=0.4.0

# Custom compilation tags
LD_FLAGS="\
-X github.com/bryk-io/did-method/client/cli/cmd.coreVersion=$(VERSION_TAG) \
-X github.com/bryk-io/did-method/client/cli/cmd.buildCode=`git log --pretty=format:'%H' -n1` \
-X github.com/bryk-io/did-method/client/cli/cmd.buildTimestamp=`date +'%s'` \
"

## help: Prints this help message
help:
	@echo "Commands available"
	@sed -n 's/^##//p' ${MAKEFILE_LIST} | column -t -s ':' | sed -e 's/^/ /' | sort

## test: Run all tests excluding the vendor dependencies
test:
	# Formatting and static analysis
	helm lint helm/*
	golangci-lint run ./...
	go-consistent -v ./...

	# Unit tests
	go test -race -cover -v -failfast ./...

## release: Prepare assets for a new tagged release
release:
	@-rm -rf release-$(VERSION_TAG)
	mkdir release-$(VERSION_TAG)
	make build-for os=linux arch=amd64 dest=release-$(VERSION_TAG)/
	make build-for os=darwin arch=amd64 dest=release-$(VERSION_TAG)/
	make build-for os=windows arch=amd64 suffix=".exe" dest=release-$(VERSION_TAG)/
	@make ci-conf

## build: Build for the current architecture in use, intended for devevelopment
build:
	go build -v -ldflags $(LD_FLAGS) -o $(BINARY_NAME) github.com/bryk-io/did-method/client/cli

## build-for: Build the availabe binaries for the specified 'os' and 'arch'
build-for:
	CGO_ENABLED=0 GOOS=$(os) GOARCH=$(arch) \
	go build -v -ldflags $(LD_FLAGS) \
	-o $(dest)$(BINARY_NAME)_$(VERSION_TAG)_$(os)_$(arch)$(suffix) github.com/bryk-io/did-method/client/cli

## install: Install the binary to GOPATH and keep cached all compiled artifacts
install:
	@go build -v -ldflags $(LD_FLAGS) -i -o ${GOPATH}/bin/$(BINARY_NAME) github.com/bryk-io/did-method/client/cli

## clean: Verify dependencies and remove intermediary products
clean:
	go clean
	go mod tidy
	go mod verify
	go mod vendor

## updates: List available updates for direct dependencies
updates:
	# https://github.com/golang/go/wiki/Modules#how-to-upgrade-and-downgrade-dependencies
	go list -u -f '{{if (and (not (or .Main .Indirect)) .Update)}}{{.Path}}: {{.Version}} -> {{.Update.Version}}{{end}}' -m all 2> /dev/null

## proto: Compile protocol buffers and RPC services
proto:
	docker run --rm -t -v `pwd`:/work proto-builder:1.9.0 prototool lint proto
	docker run --rm -t -v `pwd`:/work proto-builder:1.9.0 prototool format -w -f proto
	docker run --rm -t -v `pwd`:/work proto-builder:1.9.0 prototool generate
	docker run --rm -t -v `pwd`:/work proto-builder:1.9.0 prototool descriptor-set --include-imports --include-source-info -o proto/descriptor.bin proto

	# Fix gRPC-Gateway generated code
    # https://github.com/grpc-ecosystem/grpc-gateway/issues/229
	sed -i '' "s/empty.Empty/types.Empty/g" proto/*.pb.gw.go

## ca-roots: Generate the list of valid CA certificates
ca-roots:
	@docker run -dit --rm --name ca-roots debian:stable-slim
	@docker exec --privileged ca-roots sh -c "apt update"
	@docker exec --privileged ca-roots sh -c "apt install -y ca-certificates"
	@docker exec --privileged ca-roots sh -c "cat /etc/ssl/certs/* > /ca-roots.crt"
	@docker cp ca-roots:/ca-roots.crt ca-roots.crt
	@docker stop ca-roots

## docker: Build docker image
docker:
	@-rm $(BINARY_NAME)_$(VERSION_TAG)_linux_amd64 ca-roots.crt
	@make build-for os=linux arch=amd64
	@-docker rmi $(DOCKER_IMAGE):$(VERSION_TAG)
	@docker build --build-arg VERSION_TAG="$(VERSION_TAG)" --rm -t $(DOCKER_IMAGE):$(VERSION_TAG) .
	@-rm $(BINARY_NAME)_$(VERSION_TAG)_linux_amd64 ca-roots.crt

## ci-conf: Update CI/CD configuration file
ci-conf:
	drone lint .drone.yml
	@DRONE_SERVER=${BRYK_DRONE_SERVER} DRONE_TOKEN=${BRYK_DRONE_TOKEN} drone sign --save bryk-io/did-method
