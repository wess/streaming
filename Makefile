export DOCKER_BUILDKIT=0
export COMPOSE_DOCKER_CLI_BUILD=0

ROOT_DIR 	   := $(abspath $(lastword $(MAKEFILE_LIST)))
PROJECT_DIR	 := $(notdir $(patsubst %/,%,$(dir $(ROOT_DIR))))
PROJECT 		 := $(lastword $(PROJECT_DIR))
VERSION_FILE 	= VERSION
VERSION			 	= `cat $(VERSION_FILE)`
SRC_VOLUME 		= "${PWD}/app"

default: run

.PHONY: help
help: ## Print all the available commands
	@echo "" \
	&& echo "Alloy ${VERSION}" \
	&& echo "" \
	&& grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}' \
	&& echo ""
	
build: ## Build the Docker environment
	@echo \
	&& echo "Building environment..." \
	&& docker build --rm --tag ${PROJECT}:${VERSION} .

run: build ## Run live environment
	@echo \
	&& echo "Connecting to environment" \
	&& docker run -it --privileged=true -p 3000:3000 -p 1935:1935 -p 8000:8000 --rm --volume ${SRC_VOLUME}:/app  ${PROJECT}:${VERSION}

clean: ## Clean the environment
	@echo \
	&& echo "Cleaning environment..." \
	&& docker rmi ${PROJECT}:${VERSION}


release:  ## Build the project in release mode
	@echo "Release"

setup:  ## Setup for development
	@echo "Setup Env"