PKG_VERSION = v1.12.0
TALOS_VERSION = v1.12.2
SBCOVERLAY_VERSION = v0.1.8

REGISTRY ?= ghcr.io
REGISTRY_USERNAME ?= talos-rpi5

TAG ?= $(shell git describe --tags --exact-match)

EXTENSIONS_ISCSI ?= ghcr.io/siderolabs/iscsi-tools:v0.2.0
EXTENSIONS_TAILSCALE ?= ghcr.io/siderolabs/tailscale:1.88.3
EXTENSIONS_UTIL_LINUX ?= ghcr.io/siderolabs/util-linux-tools:2.41.1

PKG_REPOSITORY = https://github.com/siderolabs/pkgs.git
TALOS_REPOSITORY = https://github.com/siderolabs/talos.git
SBCOVERLAY_REPOSITORY = https://github.com/siderolabs/sbc-raspberrypi.git

CHECKOUTS_DIRECTORY := $(PWD)/checkouts
PATCHES_DIRECTORY := $(PWD)/patches
PROFILES_DIRECTORY := $(PWD)/profiles

PKGS_TAG = $(shell cd $(CHECKOUTS_DIRECTORY)/pkgs && git describe --tag --always --dirty --match v[0-9]\*)
TALOS_TAG = $(shell cd $(CHECKOUTS_DIRECTORY)/talos && git describe --tag --always --dirty --match v[0-9]\*)
SBCOVERLAY_TAG = $(shell cd $(CHECKOUTS_DIRECTORY)/sbc-raspberrypi && git describe --tag --always --dirty)-$(PKGS_TAG)

#
# Help
#
.PHONY: help
help:
	@echo "checkouts : Clone repositories required for the build"
	@echo "patches   : Apply all patches"
	@echo "kernel    : Build kernel"
	@echo "overlay   : Build Raspberry Pi 5 overlay"
	@echo "installer : Build installer docker image and disk image"
	@echo "release   : Use only when building the final release, this will tag relevant images with the current Git tag."
	@echo "clean     : Clean up any remains"



#
# Checkouts
#
.PHONY: checkouts checkouts-clean
checkouts:
	git clone -c advice.detachedHead=false --branch "$(PKG_VERSION)" "$(PKG_REPOSITORY)" "$(CHECKOUTS_DIRECTORY)/pkgs"
	git clone -c advice.detachedHead=false --branch "$(TALOS_VERSION)" "$(TALOS_REPOSITORY)" "$(CHECKOUTS_DIRECTORY)/talos"
	git clone -c advice.detachedHead=false --branch "$(SBCOVERLAY_VERSION)" "$(SBCOVERLAY_REPOSITORY)" "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi"

checkouts-clean:
	rm -rf "$(CHECKOUTS_DIRECTORY)/pkgs"
	rm -rf "$(CHECKOUTS_DIRECTORY)/talos"
	rm -rf "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi"



#
# Patches
#
.PHONY: patches-pkgs patches-talos patches
patches-pkgs:
	cd "$(CHECKOUTS_DIRECTORY)/pkgs" && \
		git am "$(PATCHES_DIRECTORY)/siderolabs/pkgs/0001-Patched-for-Raspberry-Pi-5.patch"

patches-talos:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		git am "$(PATCHES_DIRECTORY)/siderolabs/talos/0001-Patched-for-Raspberry-Pi-5.patch" && \
		git am "$(PATCHES_DIRECTORY)/siderolabs/talos/0002-Skip-NVRAM-writes-for-GRUB-on-arm64.patch" && \
		git am "$(PATCHES_DIRECTORY)/siderolabs/talos/0003-Force-GRUB-bootloader-on-arm64.patch"

patches: patches-pkgs patches-talos



#
# Kernel
#
.PHONY: kernel
kernel:
	cd "$(CHECKOUTS_DIRECTORY)/pkgs" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=true \
			PLATFORM=linux/arm64 \
			kernel



#
# Overlay
#
.PHONY: overlay
overlay:
	@echo SBCOVERLAY_TAG = $(SBCOVERLAY_TAG)
	cd "$(CHECKOUTS_DIRECTORY)/sbc-raspberrypi" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) IMAGE_TAG=$(SBCOVERLAY_TAG) PUSH=true \
			PKGS_PREFIX=$(REGISTRY)/$(REGISTRY_USERNAME) PKGS=$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 \
			sbc-raspberrypi



#
# Installer/Image
#
.PHONY: installer
installer:
	cd "$(CHECKOUTS_DIRECTORY)/talos" && \
		$(MAKE) \
			REGISTRY=$(REGISTRY) USERNAME=$(REGISTRY_USERNAME) PUSH=true \
			PKG_KERNEL=$(REGISTRY)/$(REGISTRY_USERNAME)/kernel:$(PKGS_TAG) \
			INSTALLER_ARCH=arm64 PLATFORM=linux/arm64 \
			IMAGER_ARGS="--overlay-name=rpi_5 --overlay-image=$(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi:$(SBCOVERLAY_TAG) --system-extension-image=$(EXTENSIONS_ISCSI) --system-extension-image=$(EXTENSIONS_TAILSCALE) --system-extension-image=$(EXTENSIONS_UTIL_LINUX)" \
			kernel initramfs imager installer-base installer && \
		sed \
			-e 's|__BASE_INSTALLER__|$(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_TAG)|' \
			-e 's|__OVERLAY_IMAGE__|$(REGISTRY)/$(REGISTRY_USERNAME)/sbc-raspberrypi:$(SBCOVERLAY_TAG)|' \
			-e 's|__EXTENSIONS_ISCSI__|$(EXTENSIONS_ISCSI)|' \
			-e 's|__EXTENSIONS_TAILSCALE__|$(EXTENSIONS_TAILSCALE)|' \
			-e 's|__EXTENSIONS_UTIL_LINUX__|$(EXTENSIONS_UTIL_LINUX)|' \
			"$(PROFILES_DIRECTORY)/rpi5-metal.yaml" \
		| docker run --rm -i -v ./_out:/out -v /dev:/dev --privileged $(REGISTRY)/$(REGISTRY_USERNAME)/imager:$(TALOS_TAG) -



#
# Release
#
.PHONY: release
release:
	docker pull $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_TAG) && \
		docker tag $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TALOS_TAG) $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TAG) && \
		docker push $(REGISTRY)/$(REGISTRY_USERNAME)/installer:$(TAG)



#
# Clean
#
.PHONY: clean
clean: checkouts-clean
