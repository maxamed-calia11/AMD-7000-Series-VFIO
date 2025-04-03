#!/bin/bash

# Helpful to read output when debugging
set -x

source "/etc/libvirt/hooks/kvm.conf"

systemctl stop sddm coolercontrold

echo 0 > /sys/class/vtconsole/vtcon0/bind
echo 0 > /sys/class/vtconsole/vtcon1/bind

#uncomment the next line if you're getting a black screen
#echo efi-framebuffer.0 > /sys/bus/platform/drivers/efi-framebuffer/unbind

sleep 10


virsh nodedev-detach $VIRSH_GPU_VIDEO
virsh nodedev-detach $VIRSH_GPU_AUDIO

modprobe -r amdgpu
modprobe -r snd_hda_intel

sleep 10

modprobe vfio
modprobe vfio_pci
modprobe vfio_iommu_type1
