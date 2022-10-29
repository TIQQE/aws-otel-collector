-include .env

AOC_IMPORT_PATH=github.com/aws-observability/aws-otel-collector
VERSION := $(shell cat VERSION)
PROJECTNAME := $(shell basename "$(PWD)")

GIT_SHA=$(shell git rev-parse HEAD)
DATE=$(shell date -u +'%Y-%m-%dT%H:%M:%SZ')
# All source code excluding any third party code and excluding the testbed.
# This is the code that we want to run tests for and lint, staticcheck, etc.
ALL_SRC := $(shell find . -name '*.go' \
							-not -path './testbed/*' \
							-not -path '*/third_party/*' \
							-not -path './.github/*' \
							-not -path './pkg/devexporter/*' \
							-not -path './pkg/lambdacomponents/*' \
							-not -path './bin/*' \
							-not -path './build/*' \
							-not -path './tools/linters/*' \
							-not -path './tools/release/*' \
							-not -path './e2etest/clean/*' \
							-type f | sort)
# ALL_PKGS is the list of all packages where ALL_SRC files reside.
ALL_PKGS := $(shell go list $(sort $(dir $(ALL_SRC))))

# ALL_MODULES includes ./* dirs (excludes . dir)
ALL_MODULES := $(shell find . -type f -name "go.mod" -exec dirname {} \; | sort | egrep  '^./' )

GOTEST_OPT?= -short -coverprofile coverage.txt -v -race -timeout 180s
GOTEST=go test

BUILD_INFO_IMPORT_PATH=$(AOC_IMPORT_PATH)/tools/version

GOBUILD=GO111MODULE=on CGO_ENABLED=0 installsuffix=cgo go build -trimpath

# Use linker flags to provide version/build settings
LDFLAGS=-ldflags "-s -w -X $(BUILD_INFO_IMPORT_PATH).GitHash=$(GIT_SHA) \
-X github.com/open-telemetry/opentelemetry-collector-contrib/exporter/awsxrayexporter.collectorDistribution=aws-otel-collector \
-X github.com/open-telemetry/opentelemetry-collector-contrib/exporter/awsemfexporter.collectorDistribution=aws-otel-collector \
-X $(BUILD_INFO_IMPORT_PATH).Version=$(VERSION) -X $(BUILD_INFO_IMPORT_PATH).Date=$(DATE)"

GOOS=$(shell go env GOOS)
GOARCH=$(shell go env GOARCH)


###test repo
DOCKER_NAMESPACE=240536350385.dkr.ecr.eu-north-1.amazonaws.com
##prod repo
#DOCKER_NAMESPACE=291960307719.dkr.ecr.eu-north-1.amazonaws.com


COMPONENT=awscollector

TOOLS_MOD_DIR := $(abspath ./tools/linters)
TOOLS_BIN_DIR := $(abspath ./bin)

GOIMPORTS_OPT?= -w -local $(AOC_IMPORT_PATH)
GOIMPORTS = $(TOOLS_BIN_DIR)/goimports

MULTIMOD = $(TOOLS_BIN_DIR)/multimod
$(TOOLS_BIN_DIR)/multimod: $(TOOLS_MOD_DIR)/go.mod $(TOOLS_MOD_DIR)/go.sum $(TOOLS_MOD_DIR)/tools.go
	cd $(TOOLS_MOD_DIR) && \
	go build -o $(TOOLS_BIN_DIR)/multimod go.opentelemetry.io/build-tools/multimod

STATIC_CHECK = $(TOOLS_BIN_DIR)/staticcheck
$(TOOLS_BIN_DIR)/staticcheck: $(TOOLS_MOD_DIR)/go.mod $(TOOLS_MOD_DIR)/go.sum $(TOOLS_MOD_DIR)/tools.go
	cd $(TOOLS_MOD_DIR) && \
	GOBIN=$(TOOLS_BIN_DIR) go install honnef.co/go/tools/cmd/staticcheck

LINT = $(TOOLS_BIN_DIR)/golangci-lint
$(TOOLS_BIN_DIR)/golangci-lint: $(TOOLS_MOD_DIR)/go.mod $(TOOLS_MOD_DIR)/go.sum $(TOOLS_MOD_DIR)/tools.go
	cd $(TOOLS_MOD_DIR) && \
	GOBIN=$(TOOLS_BIN_DIR) go install github.com/golangci/golangci-lint/cmd/golangci-lint

SHFMT = $(TOOLS_BIN_DIR)/shfmt
$(TOOLS_BIN_DIR)/shfmt: $(TOOLS_MOD_DIR)/go.mod $(TOOLS_MOD_DIR)/go.sum $(TOOLS_MOD_DIR)/tools.go
	cd $(TOOLS_MOD_DIR) && \
	GOBIN=$(TOOLS_BIN_DIR) go install mvdan.cc/sh/v3/cmd/shfmt

DBOTCONF = $(TOOLS_BIN_DIR)/dbotconf

all-modules:
	@echo $(ALL_MODULES) | tr ' ' '\n' | sort

all-pkgs:
	@echo $(ALL_PKGS) | tr ' ' '\n' | sort

all-srcs:
	@echo $(ALL_SRC) | tr ' ' '\n' | sort


DEPENDABOT_CONFIG = .github/dependabot.yml
.PHONY: dependabot-check
dependabot-check: install-dbotconf
	@$(DBOTCONF) verify $(DEPENDABOT_CONFIG) || echo "(run: make dependabot-generate)"

.PHONY: dependabot-generate
dependabot-generate: install-dbotconf
	@$(DBOTCONF) generate > $(DEPENDABOT_CONFIG);

.PHONY: build
build: install-tools lint multimod-verify
	GOOS=darwin GOARCH=amd64 $(GOBUILD) $(LDFLAGS) -o ./build/darwin/amd64/aoc ./cmd/awscollector
	GOOS=linux GOARCH=amd64 $(GOBUILD) $(LDFLAGS) -o ./build/linux/amd64/aoc ./cmd/awscollector
	GOOS=linux GOARCH=arm64 $(GOBUILD) $(LDFLAGS) -o ./build/linux/arm64/aoc ./cmd/awscollector
	GOOS=windows GOARCH=amd64 $(GOBUILD) $(LDFLAGS) -o ./build/windows/amd64/aoc ./cmd/awscollector

.PHONY: amd64-build
amd64-build: install-tools lint multimod-verify
	GOOS=linux GOARCH=amd64 $(GOBUILD) $(LDFLAGS) -o ./build/linux/amd64/aoc ./cmd/awscollector

.PHONY: arm64-build
arm64-build: install-tools lint multimod-verify
	GOOS=linux GOARCH=arm64 $(GOBUILD) $(LDFLAGS) -o ./build/linux/arm64/aoc ./cmd/awscollector

.PHONY: windows-build
windows-build: install-tools lint multimod-verify
	GOOS=windows GOARCH=amd64 $(GOBUILD) $(LDFLAGS) -o ./build/windows/amd64/aoc ./cmd/awscollector

# For building container image during development, no lint nor other platforms
.PHONY: amd64-build-only
amd64-build-only:
	GOOS=linux GOARCH=amd64 $(GOBUILD) $(LDFLAGS) -o ./build/linux/amd64/aoc ./cmd/awscollector

.PHONY: awscollector
awscollector:
	GOOS=linux GOARCH=amd64 $(GOBUILD) $(LDFLAGS) -o ./bin/awscollector_$(GOOS)_$(GOARCH) ./cmd/awscollector
	GOOS=windows GOARCH=amd64 EXTENSION=.exe $(GOBUILD) $(LDFLAGS) -o ./bin/windows/aoc_windows_amd64.exe ./cmd/awscollector

.PHONY: package-rpm
package-rpm: build
	ARCH=x86_64 SOURCE_ARCH=amd64 DEST=build/packages/linux/amd64 tools/packaging/linux/create_rpm.sh

.PHONY: package-deb
package-deb: build
	ARCH=amd64 DEST=build/packages/debian/amd64 tools/packaging/debian/create_deb.sh
	ARCH=arm64 DEST=build/packages/debian/arm64 tools/packaging/debian/create_deb.sh

.PHONY: docker-build
docker-build: amd64-build
	if [ ! $(certs-path) ]; then echo "Please input certs-path";exit 1; fi
	if [ ! -d $(certs-path) ]; then echo "This folder is not exist: $(certs-path) ";exit 1; fi
	if [ -e $(certs-path)/ca.pem ]; then echo "Check file ca.pem";else echo "ca.pem is not exist";exit 1; fi;
	if [ -e $(certs-path)/collector.pem ]; then echo "Check file collector.pem";else echo "collector.pem is not exist";exit 1; fi;
	if [ -e $(certs-path)/collector-key.pem ]; then echo "Check file collector-key.pem";else echo "collector-key.pem is not exist";exit 1; fi;
	if [ -e $(certs-path)/collector-config.yaml ]; then echo "Check file collector-config.yaml";else echo "collector-config.yaml is not exist";exit 1; fi;

	cp $(certs-path)/ca.pem ca.pem
	cp $(certs-path)/collector.pem collector.pem
	cp $(certs-path)/collector-key.pem collector-key.pem
	cp $(certs-path)/collector-config.yaml collector-config.yaml

	docker buildx build  --platform linux/amd64 --build-arg CACHEBUST=$(date +%s) --build-arg BUILDMODE=copy --load -t $(DOCKER_NAMESPACE)/$(COMPONENT):$(VERSION) -f ./cmd/$(COMPONENT)/Dockerfile .

.PHONY: docker-build-arm
docker-build-arm: arm64-build
	docker buildx build --platform linux/arm64  --build-arg BUILDMODE=copy --load -t $(DOCKER_NAMESPACE)/$(COMPONENT):$(VERSION) -f ./cmd/$(COMPONENT)/Dockerfile .

.PHONY: docker-push
docker-push:
	docker push $(DOCKER_NAMESPACE)/$(COMPONENT):$(VERSION)

.PHONY: docker-run
docker-run:
	docker run --rm -p 4317:4317 -p 55679:55679 -p 8889:8888 \
            -v "${PWD}/config.yaml":/otel-local-config.yaml \
            --name awscollector $(DOCKER_NAMESPACE)/$(COMPONENT):$(VERSION) \
            --config otel-local-config.yaml; \

.PHONY: docker-compose
docker-compose:
	cd examples/docker; docker-compose up -d

.PHONY: docker-stop
docker-stop:
	docker stop $(shell docker ps -aq)

.PHONY: test
test:
	echo $(ALL_PKGS) | xargs -n 10 $(GOTEST) $(GOTEST_OPT)

.PHONY: fmt
fmt:
	go fmt ./...
	echo $(ALL_SRC) | xargs -n 10 $(GOIMPORTS) $(GOIMPORTS_OPT)

.PHONY: fmt-sh
fmt-sh: $(SHFMT)
	$(SHFMT) -w -d -i 4 .

.PHONY: lint-static-check
lint-static-check: | $(LINT) $(STATIC_CHECK)
	@STATIC_CHECK_OUT=`$(STATIC_CHECK) $(ALL_PKGS) 2>&1`; \
		if [ "$$STATIC_CHECK_OUT" ]; then \
			echo "$(STATIC_CHECK) FAILED => static check errors:\n"; \
			echo "$$STATIC_CHECK_OUT\n"; \
			exit 1; \
		else \
			echo "Static check finished successfully"; \
		fi

.PHONY: lint
lint: lint-static-check
	$(LINT) run --timeout 5m --enable gosec

.PHONY: multimod-verify
multimod-verify: | $(MULTIMOD)
	@echo "Validating versions.yaml"
	$(MULTIMOD) verify

COREPATH ?="../opentelemetry-collector"

.PHONY: multimod-sync-core
multimod-sync-core: multimod-verify
	@[ ! -d COREPATH ] || ( echo ">> Path to core repository must be set in COREPATH and must exist"; exit 1 )
	$(MULTIMOD) sync -a -o ${COREPATH}

CONTRIBPATH ?="../opentelemetry-collector-contrib"

.PHONY: multimod-sync-contrib
multimod-sync-contrib: multimod-verify
	@[ ! -d CONTRIBPATH ] || ( echo ">> Path to contrib repository must be set in CONTRIBPATH and must exist"; exit 1 )
	$(MULTIMOD) sync -a -o ${CONTRIBPATH}

COMMIT ?= "HEAD"
.PHONY: multimod-tags
multimod-tags: multimod-verify
	@[ "${MODSET}" ] || ( echo ">> env var MODSET is not set"; exit 1 )
	$(MULTIMOD) tag -m ${MODSET} -c ${COMMIT}

.PHONY: install-tools
install-tools:
	cd $(TOOLS_MOD_DIR) && GOBIN=$(TOOLS_BIN_DIR) go install golang.org/x/tools/cmd/goimports
	cd $(TOOLS_MOD_DIR) && GOBIN=$(TOOLS_BIN_DIR) go install go.opentelemetry.io/build-tools/multimod
	cd $(TOOLS_MOD_DIR) && GOBIN=$(TOOLS_BIN_DIR) go install honnef.co/go/tools/cmd/staticcheck
	cd $(TOOLS_MOD_DIR) && GOBIN=$(TOOLS_BIN_DIR) go install github.com/golangci/golangci-lint/cmd/golangci-lint
	cd $(TOOLS_MOD_DIR) && GOBIN=$(TOOLS_BIN_DIR) go install mvdan.cc/sh/v3/cmd/shfmt
	cd $(TOOLS_MOD_DIR) && GOBIN=$(TOOLS_BIN_DIR) go install go.opentelemetry.io/build-tools/dbotconf

.PHONY: install-dbotconf
install-dbotconf:
	if [ ! -f "$(DBOTCONF)" ]; then \
		cd $(TOOLS_MOD_DIR) && GOBIN=$(TOOLS_BIN_DIR) go install go.opentelemetry.io/build-tools/dbotconf; \
	fi

.PHONY: clean
clean:
	rm -rf ./build
