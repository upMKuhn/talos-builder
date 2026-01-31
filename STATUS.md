# talos-builder v1.12.2 Upgrade

Branch: `talos_v_1-12-2`

## Version Bumps

| Component | Before | After |
|-----------|--------|-------|
| Talos | v1.11.5 | v1.12.2 |
| Pkgs | v1.11.0 | v1.12.0 |
| SBC Overlay | `main` (fork) | v0.1.8 (upstream) |
| Upstream kernel | 6.12.38 | 6.17.7 |

## Switch to Upstream SBC Overlay

Dropped the `talos-rpi5/sbc-raspberrypi5` fork in favour of the official `siderolabs/sbc-raspberrypi` repo at a pinned tag (v0.1.8). This means:

- Repository: `github.com/talos-rpi5/sbc-raspberrypi5` -> `github.com/siderolabs/sbc-raspberrypi`
- Directory: `checkouts/sbc-raspberrypi5` -> `checkouts/sbc-raspberrypi`
- Build target: `sbc-raspberrypi5` -> `sbc-raspberrypi`
- Overlay name: `--overlay-name=rpi5` -> `--overlay-name=rpi_5`

## Kernel Strategy Change

The RPi Linux fork (raspberrypi/linux) is stuck on 6.12.x. Talos pkgs v1.12.0 uses upstream 6.17.7. Rather than pinning to a stale fork, we now use the **upstream Talos kernel** and apply only the config-level changes needed for RPi5 support.

This means the 22 RPi-fork-only kernel configs (RP1, BCM2712, BCM2835_SMI, etc.) are **not included** -- they require kernel source patches that don't exist in upstream 6.17.

## Patches

### `patches/siderolabs/pkgs/0001` -- Kernel config (config-arm64)

Regenerated for pkgs v1.12.0 / kernel 6.17.7. No longer touches `Pkgfile` or `kernel/prepare/pkg.yaml` (no source URL swap).

Changes applied:
- **16K pages** -- `ARM64_4K_PAGES` -> `ARM64_16K_PAGES`
- **~100 module-to-builtin** -- network (Intel, Broadcom, Realtek, STMMAC/DWMAC, Mellanox, QLogic), storage (AHCI, NVMe, megaraid, smartpqi, mpt3sas), virtio, HID, MMC/SDHCI, USB serial, I2C, PATA all built as `=y`
- **IMA enabled** -- full Integrity Measurement Architecture with SHA-512, appraise, arch policy
- **Governor** -- default CPU freq governor set to ondemand
- **Disabled** -- ZSWAP, DRM_PANTHOR, BLK_CGROUP_IOLATENCY, NFT_CONNLIMIT
- **Enabled** -- NETWORK_PHY_TIMESTAMPING, SPI_GPIO, PWM_GPIO, PWM_BRCMSTB, BCM2835_THERMAL, PINCTRL_MCP23S08
- **Infiniband** -- disabled USER_MAD/USER_ACCESS (not needed)

### `patches/siderolabs/talos/0001` -- modules-arm64.txt (PLACEHOLDER)

Regenerated module list reflecting the m->y builtin changes. Removed ~112 modules that are now builtin, added ~15 new modules from v1.12.2 (vdpa, vhost, hkdf, idpf, sdhci-uhs2, etc.).

**This is a placeholder.** After the first kernel build, regenerate from actual build output.

### `patches/siderolabs/talos/0002` -- Skip NVRAM writes on arm64

Same logic, regenerated for v1.12.2 line offsets. Adds `|| opts.Arch == arm64` to the `--no-nvram` condition in `grub/install.go`.

### `patches/siderolabs/talos/0003` -- Force GRUB on arm64

Same logic, regenerated for v1.12.2 line offsets. Returns `grub.NewConfig()` early in `NewAuto()` when `GOARCH == "arm64"`.

## Post-Merge TODO

1. **Build kernel** -- `make clean && make checkouts && make patches && make kernel`
2. **Regenerate modules patch** -- after kernel build, extract actual module list and regenerate `talos/0001`
3. **Build overlay + installer** -- `make overlay && make installer`
4. **Test PXE boot** on RPi5 hardware
5. **Decide on RPi-fork kernel configs** -- if RP1/BCM2712 drivers are needed, either backport patches to 6.17 or wait for RPi fork to catch up
