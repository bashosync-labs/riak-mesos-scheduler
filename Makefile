REPO            ?= riak-mesos-scheduler
RELDIR          ?= riak_mesos_scheduler
GIT_TAG_ISH     ?= $(shell git describe --tags)
PKG_VERSION	    ?= $(GIT_TAG_ISH)
MAJOR           ?= $(shell echo $(PKG_VERSION) | cut -d'.' -f1)
MINOR           ?= $(shell echo $(PKG_VERSION) | cut -d'.' -f2)
OS_FAMILY       ?= ubuntu
OS_VERSION      ?= 14.04
mesos           ?= 0.28.1
PKGNAME         ?= $(RELDIR)-$(PKG_VERSION)-mesos-$(mesos)-$(OS_FAMILY)-$(OS_VERSION).tar.gz
OAUTH_TOKEN     ?= $(shell cat oauth.txt)
GIT_TAG   	    ?= $(shell git describe --tags --abbrev=0)
RELEASE_ID      ?= $(shell curl -sS https://api.github.com/repos/basho-labs/$(REPO)/releases/tags/$(GIT_TAG)?access_token=$(OAUTH_TOKEN) | python -c 'import sys, json; print json.load(sys.stdin)["id"]')
DEPLOY_BASE     ?= "https://uploads.github.com/repos/basho-labs/$(REPO)/releases/$(RELEASE_ID)/assets?access_token=$(OAUTH_TOKEN)&name=$(PKGNAME)"
DOWNLOAD_BASE   ?= https://github.com/basho-labs/$(REPO)/releases/download/$(GIT_TAG)/$(PKGNAME)

ifeq ($(GIT_TAG_ISH),$(GIT_TAG))
# If these 2 are identical, there have been no commits since the last tag
BUILDING_EXACT_TAG = yes
else
BUILDING_EXACT_TAG = no
endif

BASE_DIR         = $(shell pwd)
ERLANG_BIN       = $(shell dirname $(shell which erl))
REBAR           ?= $(BASE_DIR)/rebar
OVERLAY_VARS    ?=

CT_SUITE        ?= rms_offer_helper
CT_CASE         ?= can_fit_hostname_constraints

ifneq (,$(shell whereis sha256sum | awk '{print $2}';))
SHASUM = sha256sum
else
SHASUM = shasum -a 256
endif

.PHONY: all compile recompile deps cleantest test rel relx clean relclean stage tarball

all: compile
compile: deps
	$(REBAR) compile
recompile:
	$(REBAR) compile skip_deps=true
clean: cleantest relclean
	$(REBAR) clean
	-rm -rf packages
clean-deps:
	-rm -rf deps
rebar.config.lock:
	$(REBAR) get-deps compile
	$(REBAR) lock-deps
clean-lock:
	-rm rebar.config.lock
lock: clean-lock distclean rebar.config.lock
deps: rebar.config.lock
	$(REBAR) -C rebar.config.lock get-deps
cleantest:
	-rm -rf .eunit/*
	-rm -rf ct_log/*
test: cleantest
	$(REBAR) skip_deps=true eunit
	$(REBAR) skip_deps=true ct
test-case: cleantest recompile
	$(REBAR) skip_deps=true ct suites=$(PWD)/test/$(CT_SUITE) cases=$(CT_CASE)
test-suite: cleantest recompile
	$(REBAR) skip_deps=true ct suites=$(PWD)/test/$(CT_SUITE)
rel: relclean compile relx
relx:
	./relx release
relclean:
	-rm -rf _rel/riak_mesos_scheduler
distclean: clean
	$(REBAR) delete-deps
stage: rel
	$(foreach dep,$(wildcard deps/*), rm -rf rel/riak_mesos_scheduler/lib/$(shell basename $(dep))-* && ln -sf $(abspath $(dep)) rel/riak_mesos_scheduler/lib;)
	$(foreach app,$(wildcard apps/*), rm -rf rel/riak_mesos_scheduler/lib/$(shell basename $(app))-* && ln -sf $(abspath $(app)) rel/riak_mesos_scheduler/lib;)

##
## Packaging targets
##
#tarball: clean-deps retarball
newtarball: relclean retarball
tarball: rel retarball
retarball: relx
	echo "Creating packages/"$(PKGNAME)
	mkdir -p packages
	tar -C _rel -czf $(PKGNAME) $(RELDIR)/
	mv $(PKGNAME) packages/
	cd packages && $(SHASUM) $(PKGNAME) > $(PKGNAME).sha
	cd packages && echo "$(DOWNLOAD_BASE)" > remote.txt
	cd packages && echo "$(BASE_DIR)/packages/$(PKGNAME)" > local.txt

prball: GIT_SHA = $(shell git log -1 --format='%h')
prball: PR_COMMIT_COUNT = $(shell git log --oneline master.. | wc -l)
prball: PKG_VERSION = PR-$(PULL_REQ)-$(PR_COMMIT_COUNT)-$(GIT_SHA)
prball: PKGNAME = $(RELDIR)-$(PKG_VERSION)-mesos-$(mesos)-$(OS_FAMILY)-$(OS_VERSION).tar.gz
prball: tarball

sync-test:
ifeq (yes,$(BUILDING_EXACT_TAG))
	@echo $(RELEASE_ID)
else
	@echo "Refusing to upload: not an exact tag: "$(GIT_TAG_ISH)
endif

sync:
ifeq (yes,$(BUILDING_EXACT_TAG))
	@echo "Uploading to "$(DOWNLOAD_BASE)
	@cd packages && \
		curl -sS -XPOST -H 'Content-Type: application/gzip' $(DEPLOY_BASE) --data-binary @$(PKGNAME) && \
		curl -sS -XPOST -H 'Content-Type: application/octet-stream' $(DEPLOY_BASE).sha --data-binary @$(PKGNAME).sha
else
	@echo "Refusing to upload: not an exact tag: "$(GIT_TAG_ISH)
endif

ASSET_ID        ?= $(shell curl -sS https://api.github.com/repos/basho-labs/$(REPO)/releases/$(RELEASE_ID)/assets?access_token=$(OAUTH_TOKEN) | python -c 'import sys, json; print "".join([str(asset["id"]) if asset["name"] == "$(PKGNAME)" else "" for asset in json.load(sys.stdin)])')
ASSET_SHA_ID    ?= $(shell curl -sS https://api.github.com/repos/basho-labs/$(REPO)/releases/$(RELEASE_ID)/assets?access_token=$(OAUTH_TOKEN) | python -c 'import sys, json; print "".join([str(asset["id"]) if asset["name"] == "$(PKGNAME).sha" else "" for asset in json.load(sys.stdin)])')
DELETE_DEPLOY_BASE     ?= "https://api.github.com/repos/basho-labs/$(REPO)/releases/assets/$(ASSET_ID)?access_token=$(OAUTH_TOKEN)"
DELETE_SHA_DEPLOY_BASE ?= "https://api.github.com/repos/basho-labs/$(REPO)/releases/assets/$(ASSET_SHA_ID)?access_token=$(OAUTH_TOKEN)"

sync-delete:
	echo "Deleting "$(DOWNLOAD_BASE)
	- $(shell curl -sS -XDELETE $(DELETE_DEPLOY_BASE))
	- $(shell curl -sS -XDELETE $(DELETE_SHA_DEPLOY_BASE))
