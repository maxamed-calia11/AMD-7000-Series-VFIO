#!/bin/bash
set -x

#reboot now

source "/etc/libvirt/hooks/kvm.conf"

modprobe -r vfio_pci
modprobe -r vfio_iommu_type1
modprobe -r vfio

sleep 10

virsh nodedev-reattach $VIRSH_GPU_VIDEO
virsh nodedev-reattach $VIRSH_GPU_AUDIO

echo 1 > /sys/class/vtconsole/vtcon0/bind
echo 1 > /sys/class/vtconsole/vtcon1/bind

sleep 3

#echo "efi-framebuffer.0" > /sys/bus/platform/drivers/efi-framebuffer/bind

modprobe amdgpu
modprobe snd_hda_intel

sleep 3

#Add additional services that use the amdgpu driver below this line
#replace sddm with your display manager, or consult other guides for how to do VFIO with those display managers
systemctl start sddm
