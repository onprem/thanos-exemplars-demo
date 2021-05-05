include .bingo/Variables.mk

MANIFESTS_DIR ?= manifests

JSONNET_SRC = $(shell find . -type f -not -path './*vendor/*' \( -name '*.libsonnet' -o -name '*.jsonnet' \))

all: generate

vendor: $(JB)
	$(JB) install

${MANIFESTS_DIR}: jsonnet/main.jsonnet vendor $(JSONNET) $(GOJSONTOYAML) $(JSONNET_SRC)
	-rm -rf $(MANIFESTS_DIR)
	-mkdir -p $(MANIFESTS_DIR)
	$(JSONNET) -J vendor -m $(MANIFESTS_DIR) jsonnet/main.jsonnet | xargs -I{} sh -c 'cat {} | $(GOJSONTOYAML) > {}.yaml' -- {}
	find $(MANIFESTS_DIR) -type f ! -name '*.yaml' -delete

.PHONY: generate
generate: $(MANIFESTS_DIR)
