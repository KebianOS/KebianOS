#!/bin/bash
lb clean
lb config --distribution trixie --architectures amd64 --binary-images iso-hybrid --bootloaders "grub-efi syslinux" --archive-areas "main contrib non-free non-free-firmware" --iso-application "KebianOS" --iso-volume "KebianOS 1.1 Beta" --iso-publisher "KebianOS Team" --iso-preparer "KebianOS"
lb build
