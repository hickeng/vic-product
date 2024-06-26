# Copyright 2016 VMware, Inc. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

SHELL=/bin/bash

GO ?= go
SED ?= sed
RM ?= rm
OS := $(shell uname | tr '[:upper:]' '[:lower:]')

BASE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

BIN ?= bin

export GOPATH ?= $(shell echo $(CURDIR) | sed -e 's,/src/.*,,')
DEP ?= $(GOPATH)/bin/dep$(BIN_ARCH)
GAS ?= $(GOPATH)/bin/gas$(BIN_ARCH)
GOLINT ?= $(GOPATH)/bin/golint$(BIN_ARCH)

.PHONY: gas ova

LDFLAGS := $(shell BUILD_NUMBER=${BUILD_NUMBER} TAG=${TAG} $(BASE_DIR)/scripts/version-linker-flags.sh)

ovfenv := $(BIN)/ovfenv
vic-ova-ui := $(BIN)/vic-ova-ui
ova-webserver := $(BIN)/ova-webserver
ova-landing-server := $(BIN)/ova-landing-server
toolbox := $(BIN)/toolbox
rpctool := $(BIN)/rpctool
gas: $(GAS)
ovfenv: $(ovfenv)
vic-ova-ui: $(vic-ova-ui)
ova-webserver: $(ova-webserver)
ova-landing-server: $(ova-landing-server)
toolbox: $(toolbox)
rpctool: $(rpctool)
tools: $(DEP) $(GOLINT) $(GAS)
all: golint gofmt govet gas $(ovfenv) $(vic-ova-ui) $(ova-webserver) $(ova-landing-server) $(toolbox) $(rpctool)

vendor: $(DEP)
	@echo restoring vendor
	$(DEP) ensure

gas: $(GAS)
	@echo running go AST tool
	# @$(GAS) -quiet fileserver/... landing_server/... lib/... ovatools/... pkg/... toolbox/... 2> /dev/null

golint: $(GOLINT)
	@echo checking go lint...
	@$(call golintf,github.com/vmware/vic-product/installer/fileserver/...)
	@$(call golintf,github.com/vmware/vic-product/installer/landing_server/...)
	@$(call golintf,github.com/vmware/vic-product/installer/lib/...)
	@$(call golintf,github.com/vmware/vic-product/installer/ovatools/...)
	@$(call golintf,github.com/vmware/vic-product/installer/pkg/...)
	@$(call golintf,github.com/vmware/vic-product/installer/toolbox/...)

gofmt:
	@echo checking gofmt...
	@! gofmt -d -e -s $$(find . -mindepth 1 -maxdepth 1 -type d -not -name vendor) 2>&1 | egrep -v '^$$'

govet:
	@echo checking go vet...
	@$(GO) tool vet -all -lostcancel -tests $$(find . -mindepth 1 -maxdepth 1 -type d -not -name vendor)

# Generate Go package dependency set, skipping if the only targets specified are clean and/or distclean
# Caches dependencies to speed repeated calls
define godeps
	$(call assert,$(call gmsl_compatible,1 1 7), Wrong GMSL version) \
	$(if $(filter-out clean distclean mrrobot mark sincemark .DEFAULT,$(MAKECMDGOALS)), \
		$(if $(call defined,dep_cache,$(dir $1)),,$(info Generating dependency set for $(dir $1))) \
		$(or \
			$(if $(call defined,dep_cache,$(dir $1)), $(info Using cached Go dependencies) $(wildcard $1) $(call get,dep_cache,$(dir $1))),
			$(call set,dep_cache,$(dir $1),$(shell $(BASE_DIR)scripts/go-deps.sh $(dir $1) $(MAKEFLAGS))),
			$(info Cached Go dependency for $(dir $1): $(call get,dep_cache,$(dir $1))),
			$(wildcard $1) $(call get,dep_cache,$(dir $1))
		) \
	)
endef

clean:
	@echo removing binaries
	rm -rf $(BIN)

# exit 1 if golint complains about anything other than comments
golintf = $(GOLINT) $(1) | sh -c "! grep -v 'lib/apiservers/portlayer/restapi/operations'" | sh -c "! grep -v 'lib/config/dynamic/admiral/client'" | sh -c "! grep -v 'should have comment'" | sh -c "! grep -v 'comment on exported'" | sh -c "! grep -v 'by other packages, and that stutters'" | sh -c "! grep -v 'error strings should not be capitalized'"

$(ovfenv): $(call godeps,ovatools/ovfenv/*.go)
	@echo building ovfenv linux...
	@GOARCH=amd64 GOOS=linux $(TIME) $(GO) build $(RACE) -ldflags "$(LDFLAGS)" -o ./$@ ./$(dir $<)

$(vic-ova-ui): $(call godeps,ovatools/vic-ova-ui/*.go)
	@echo building vic-ova-ui
	@GOARCH=amd64 GOOS=linux $(TIME) $(GO) build $(RACE) -ldflags "$(LDFLAGS)" -o ./$@ ./$(dir $<)

$(ova-webserver): $(call godeps,fileserver/*.go)
	@echo building ova-webserver
	@GOARCH=amd64 GOOS=linux $(TIME) $(GO) build $(RACE) -ldflags "$(LDFLAGS)" -o ./$@ ./$(dir $<)

$(ova-landing-server): $(call godeps,landing_server/*.go)
	@echo building ova-landing-server
	@GOARCH=amd64 GOOS=linux $(TIME) $(GO) build $(RACE) -ldflags "$(LDFLAGS)" -o ./$@ ./$(dir $<)

$(toolbox): $(call godeps,toolbox/*.go)
	@echo building toolbox
	@GOARCH=amd64 GOOS=linux $(TIME) $(GO) build $(RACE) -ldflags "$(LDFLAGS)" -o ./$@ ./$(dir $<)

$(rpctool): $(call godeps,ovatools/rpctool/*.go)
	@echo building rpctool
	@GOARCH=amd64 GOOS=linux $(TIME) $(GO) build $(RACE) -ldflags "$(LDFLAGS)" -o ./$@ ./$(dir $<)

# utility targets
$(GAS): Gopkg.lock Gopkg.toml
	@echo installing $(GAS)...
	@echo "Skip..."

$(DEP): Gopkg.lock Gopkg.toml
	@echo building $(DEP)...
	@$(GO) build $(RACE) -o $(DEP) ./vendor/github.com/golang/dep/cmd/dep

$(GOLINT): Gopkg.lock Gopkg.toml
	@echo building $(GOLINT)...
	@$(GO) build $(RACE) -o $(GOLINT) ./vendor/github.com/golang/lint/golint
