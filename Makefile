NO_COLOR=\033[0m
OK_COLOR=\033[32;01m
ERROR_COLOR=\033[31;01m
WARN_COLOR=\033[33;01m

VERSION ?= "0.0.0-dev-$(shell git rev-parse --short HEAD)"

GOOGLEAPIS_DIR ?= "../googleapis"

.PHONY: all clean test-unit build

all: clean test-unit build

# Cleans our project: deletes binaries
clean:
	@printf "$(OK_COLOR)==> Cleaning project$(NO_COLOR)\n"
	@if [ -d bin ] ; then rm -rf bin/* ; fi

# Runs unit-tests
test-unit:
	@printf "$(OK_COLOR)==> Running unit tests$(NO_COLOR)\n"
	@CGO_ENABLED=0 go test -short ./...

# Runs integration-tests
test-integration:
	@printf "$(OK_COLOR)==> Running integration tests$(NO_COLOR)\n"
	@CGO_ENABLED=1 go test -race -p=1 -cover ./... -coverprofile=coverage.txt -covermode=atomic

# Builds the project
build:
	@printf "$(OK_COLOR)==> Building v${VERSION}$(NO_COLOR)\n"
	@CGO_ENABLED=0 go build -ldflags "-s -w" -ldflags "-X main.version=${VERSION}" -o "bin/kangal"

# Apply CRD
apply-crd:
	@printf "$(OK_COLOR)==> Applying Kangal CRD to the current cluster $(NO_COLOR)\n"
	@kubectl delete crd loadtests.kangal.hellofresh.com || true
	@kubectl apply -f charts/kangal/crd.yaml

protoc:
	@printf "$(OK_COLOR)==> Compiling ProtoBuf$(NO_COLOR)\n"
	@if [ -z ${GOOGLEAPIS_DIR} ] || [ ! -d ${GOOGLEAPIS_DIR} ]; then printf "$(ERROR_COLOR)==> GOOGLEAPIS_DIR is not set or does not exist$(NO_COLOR)\n"; exit 1; fi
	@protoc \
		--proto_path ${GOOGLEAPIS_DIR} \
		--proto_path $(CURDIR)/proto \
		--go_opt=paths=source_relative \
		--go_out=$(CURDIR)/pkg/proxy/rpc/pb \
		--go-grpc_out=$(CURDIR)/pkg/proxy/rpc/pb \
		--grpc-gateway_out=$(CURDIR)/pkg/proxy/rpc/pb \
		--grpc-gateway_opt=logtostderr=true \
		--grpc-gateway_opt=paths=source_relative \
		--openapiv2_out=$(CURDIR)/pkg/proxy/rpc/pb \
		--openapiv2_opt=logtostderr=true \
		$(CURDIR)/proto/*/*/*/*.proto

dev-buf:
	@printf "$(OK_COLOR)==> Linting ProtoBuf$(NO_COLOR)\n"
	@printf "$(ERROR_COLOR)==> Does not work yet, look inside for details$(NO_COLOR)\n"
	@exit 1
	# this command fails with the error "could not read file: open /app/buf.yaml: no such file or directory",
	# I could not find how to fix it, so for now use the command below to run buf locally half-manually
	@docker run -it --rm -v ${GOOGLEAPIS_DIR}:/googleapis -v $(pwd):/app -w /app bufbuild/buf:0.31.0 check lint --config=/app/.github/buf.yaml
	# run buf container with the deps and source code mounted (fix path to cloned googleapis repo)
	# docker run -it --rm -v $(pwd):/app -v /Users/vladimir.garvardt/Projects/googleapis:/app/googleapis -w /app --entrypoint /bin/sh bufbuild/buf:0.31.0
	# run buf from the container
	# buf check lint --config=/app/.github/buf.yaml

# === Tools ===

# This controls the version of buf to install and use.
BUF_VERSION := 0.31.1

UNAME_OS := $(shell uname -s)
UNAME_ARCH := $(shell uname -m)
# Buf will be cached to ~/.cache/buf-example.
CACHE_BASE := $(HOME)/.cache/$(PROJECT)
# This allows switching between i.e a Docker container and your local setup without overwriting.
CACHE := $(CACHE_BASE)/$(UNAME_OS)/$(UNAME_ARCH)
# The location where buf will be installed.
CACHE_BIN := $(CACHE)/bin

# BUF points to the marker file for the installed version.
#
# If BUF_VERSION is changed, the binary will be re-downloaded.
BUF := $(CACHE_VERSIONS)/buf/$(BUF_VERSION)
$(BUF):
	curl -sSL \
		"https://github.com/bufbuild/buf/releases/download/v$(BUF_VERSION)/buf-$(UNAME_OS)-$(UNAME_ARCH)" \
		-o "$(CACHE_BIN)/buf"
	chmod +x "$(CACHE_BIN)/buf"

buf-lint: $(BUF)
	buf check lint --config=./.github/buf.yaml
