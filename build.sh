#!/bin/bash
lb clean
lb config --distribution trixie --architectures amd64 --binary-images iso-hybrid --bootloaders "grub-efi syslinux" --archive-areas "main contrib non-free non-free-firmware"
lb build