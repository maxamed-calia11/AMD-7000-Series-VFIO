# AMD-7000-Series-Single-GPU-Passthrough VFIO

## How I personally got vfio working with windows 11 using many different guides, inspired by [this guide](https://github.com/mike11207/single-gpu-passthrough-amd-gpu/tree/mainhttps:/)

After months of on and off strugling with getting my AMD 7600 XT 16gb to properly passthrough, I was able to narrow down my problems to a few issues with my linux configuration, specifically with trying to remove the amdgpu kernel module and properly detaching the gpu from the system with virsh.

## If you encounter any issues, want to improve my instructions, or enhance the scripts, feel free to do so! My memory was a bit fuzzy making this and my pc has had a lot of new packages and updates since I started this so I might've left out some packages or some instructions.

# Step 1: Enabling Hardware Virtualization

In your motherboard UEFI BIOS, if you're on an Intel platform, enable VT-x and VT-d, along with any other virtualization features

If you're on and AMD platform, enable SVM and any IOMMU options in your UEFI BIOS

# Step 2: GRUB Command Line

I'm only well-versed in booting linux with grub2, so if you're using systemd-boot, consult another guide to add these lines to your kernel command line:

If on AMD:

`amd_iommu=on iommu=pt`

If on Intel:

`intel_iommu=on iommu=pt`

# Step 3: Verifying that linux enabled IOMMU and added your devices

To check if IOMMU was correctly enabled, run this command:

`sudo dmesg | grep -i -e DMAR -e IOMMU`

If you get an output with the kernel adding pci devices to iommu groups, then IOMMU is correctly enabled.

# Step 4: apt packages

This will properly install all the required software, including a gui interface to connect to qemu and libvirtd to manage your VMs, disks, etc (make sure to update and upgrade all packages before proceeding!):

`sudo apt install qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager libguestfs-tools`

There may be more packages not installed here which add extra funcitonality to work with qemu and virtual machines, but this is enough to get virtual machines working with all necessary features with additional helper scripts for debugging should you encounter an error not adressed here.

# Step 5: Configuring qemu, libvirtd, and the local user

First, we must properly configure the libvirtd daemon, by going to `/etc/libvirt/libvirtd.conf` and uncomment the following lines:

```
unix_sock_group = "libvirt"

unix_sock_rw_perms = "0770"
```

Then, add these lines to the end of `/etc/libvirt/libvirtd.conf` to help aid in any error debugging that might arise:

```
log_filters="1:qemu"

log_outputs="1:file:/var/log/libvirt/libvirtd.log"
```


```
sudo usermod -aG libvirt $(whoami)
```

```
sudo usermod -aG $(whoami) kvm
```
The next commands are systemd specific

```
sudo systemctl start libvirtd
```

```
sudo systemctl enable libvirtd
```

## Editing qemu.conf

In any editor with root priveleges, go to `/etc/libvirt/qemu.conf`, and make sure libvirtd starts as your user and your group

Change `#user = "root"` to `user = "your username"`

and `#group = "root"` to `group = "your username"`

## Commit changes

Enable the libvirtd with `sudo systemctl enable libvirtd`

and enable internet for virtual machines with:

`sudo virsh net-autostart default` and `sudo virsh net-start default`

I intentionally did not start the daemon since the next steps need reboots which will allow libvirtd to start on boot, and we are not going to work with libvirtd until later in this guide.

# Step 6: Make a VM

Grab a modern windows 10, or windows 11 image and the [virtio-win](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso) drivers

Feel free to use any method to debloat the mess that has become of windows, it helps a TON for performance and SSD health!

Once you have both ISOs, consult any of the many guides online on how to create a windows qemu virtual machine, and make sure it's one that utilizes and installs the virtio drivers during pre and post-installation

Once windows boots to a desktop, make sure you have the virtio iso mounted in the VM as a cdrom and run the x64 msi installer to make sure all drivers are working and windows plays nice in it's environment.

# Step 7: Preparations for our scripts

First, we must make sure we have a properly accessible vBIOS for the virtual machine to use. While many guides recommend downloading your graphics card's bios from TechPowerUp, small changes between brands, skews, and revisions can cause issues later on, so by either using TechPowerUp's GPU-Z, or amdvbflash, dump your vBIOS and copy it to `/usr/share/vgabios/`

Here's what my folder looks like:

```
$ ls -al /usr/share/vgabios/
total 4120
drwxr-xr-x   2 root  root     4096 Dec 23 00:50  .
drwxr-xr-x 499 root  root    20480 Apr  2 18:57  ..
-rw-rw----   1 lando lando 2097152 Dec 23 00:50  nv33.rom
```

The nv33 stands for the name of my ASIC, Navi 33, but without spaces just in case. Navi 32 and 31 are for the higher end graphics cards of the 7000 series.

Now, run these 2 commands within `/usr/share/vgabios/` so that your qemu instances can properly access the file(replace ROM_NAME with your rom name and **username** with your local user):

```
chmod -R 660 ROM_NAME.rom
```

```
chown username:username ROM_NAME.rom
```

## Finding our GPU instance

Linux has a virtual sysfs filesystem for mapping pci devices for easy use by us, and this script will let us find our GPU's pci ID along with it's hdmi/DP audio path:

```
#!/bin/bash
shopt -s nullglob
for g in /sys/kernel/iommu_groups/*; do
    echo "IOMMU Group ${g##*/}:"
    for d in $g/devices/*; do
        echo -e "\t$(lspci -nns ${d##*/})"
    done;
done;
```

This will spit out a massive output listing all of our IOMMU Groups and what pci devices are in each group, what you are looking for is something similar within the output generated to my output below(The iommu and pci ID will vary):

```
IOMMU Group 18:
        2d:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 33 [Radeon RX 7600/7600 XT/7600M XT/7600S/7700S / PRO W7600] [1002:7480] (rev c0)
IOMMU Group 19:
        2d:00.1 Audio device [0403]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 31 HDMI/DP Audio [1002:ab30]

```

For me, the pci ID for my gpu is `2d:00.0`, and the audio is `2d:00.1`

If, for some reason, your gpu iommu group, or HDMI/DP Audio group have more than just one device, ALL of the devices in each group MUST be passed through to the VM or the VM will not work.

## Editing our VM XML

Go ahead and open virt-manager, open the vm, and go to the CPUs tab, verify that your config has both checkboxes for host-passthrough and topology checked, and under the topology drop down, set the info below:
Sockets: 1
Cores: (if hyperthreading, the most you can allocate is half the cores visible to the system)
Threads: (if hyperthreading, 2, if not, 1)

Also, I'm not sure how, but make sure that in the XML editor, the `<hyperv>...</hyperv>` tag is present, it helps gain massive performance in Windows.(Please let me know how to do this through filing an issue or a pull request)

Also, inside the `<hyperv>` tag, add this to enable display out:

`<vendor_id state="on" value="randomid"/>`

Next, we must passthrough our gpu, audio, and any USB devices you want to use in your vm. For each device in the IOMMU group with containing your GPU, click Add Hardware, select PCI Host device, and select by ID from there, repeat for your IOMMU group with your audio device. For any USB devices, add them as a USB host device.

After that, go to your gpu host device, and enable ROM bar, along, and make sure the rom xml tag below the `</source>` closing tag looks like this(replace BIOS_NAME with your vBIOS name from earlier):
`<rom bar="on" file="/usr/share/vgabios/BIOS_NAME.rom"/>`

Make sure to click apply and it will autoformat the xml.

Finally, we need to remove everything video related from the VM. Remove anything with spice, video, or channel spice or even QXL stuff as those video devices are no longer needed.

Personally, I have 2 separate VMs in virt-manager with the only difference being the gpu passthrough defined above for flexibility, and so that I can run both operating systems at the same time, but also get the full hardware acceleration when needed.

# Step 8: Hooks

When I first finished step 7, I was eager to try out my new vm, only to realize it locked up my entire system due to a lack of proper GPU detachment and resetting. Luckily, the 7000 series is not prone to the gpu reset bug, so no `vendor-reset` needed.

First, enter these commands to set up a qemu script to run our hooks:

`mkdir -p /etc/libvirt/hooks`

`sudo wget 'https://raw.githubusercontent.com/lando07/AMD-7000-Series-VFIO/refs/heads/main/qemu' -O /etc/libvirt/hooks/qemu`

Then, make the new qemu script executable:

`sudo chmod +x /etc/libvirt/hooks/qemu`

Now, we must create 6 new directories to store our VM startup and shutdown scripts, use `sudo mkdir` to create these directories, substituting YOUR_VM for the name of your virtual machine(case sensitive):

```
/etc/libvirt/hooks/qemu.d

/etc/libvirt/hooks/qemu.d/YOUR_VM

/etc/libvirt/hooks/qemu.d/YOUR_VM/prepare

/etc/libvirt/hooks/qemu.d/YOUR_VM/prepare/begin

/etc/libvirt/hooks/qemu.d/YOUR_VM/release

/etc/libvirt/hooks/qemu.d/YOUR_VM/release/end
```

Once created, in any text editor with root priveliges, edit a new file in this directory:

`/etc/libvirt/hooks/qemu.d/YOUR_VM/prepare/begin/start.sh`

and then add my start.sh text in this repo to that file. Then, make it executable:

`sudo chmod +x /etc/libvirt/hooks/qemu.d/YOUR_VM/prepare/begin/start.sh`

Repeat both steps above for this script:

`/etc/libvirt/hooks/qemu.d/win10/release/end/revert.sh`

Now, with that text editor with root priveliges, go to `/etc/libvirt/hooks/kvm.conf` and add these 2 lines, and replace xx with your gpu ID you passed through earler, it could be `01`, in my case it was `2d`, but it could be any 2-digit hexadecimal number:

```
VIRSH_GPU_VIDEO=pci_0000_xx_00_0

VIRSH_GPU_AUDIO=pci_0000_xx_00_1
```

# Step 9: Testing and debugging the hooks and the scripts

Now, this is what tripped me up for so many months, and it was all because I couldn't properly `rmmod amdgpu`. What we're about to do, you'll need a second way of interfacing with the computer that doesn't require a display, like an SSH session from another laptop, as we will lose complete control and dislplay output of the computer while debugging, but the computer will be running headless.

## Finding errors

The most common error(and the one that broke everything) is unloading the amdgpu kernel module. On an external console connected to your host computer (either thru serial, ssh, etc), Run the following command as root, keep in mind you will immediately lose all display out and control, so do not do this from the PC hosting the VM:

`/etc/libvirt/hooks/qemu.d/win10/prepare/begin/start.sh`

IF YOU SEE ANY ERRORS, IMMEDIATELY Ctrl+C, but DO NOT REBOOT, STAY IN THAT SHELL FOR TROUBLESHOOTING BELOW.

(Any vtconsole bind errors can be ignored)

In my case, I had this error:
`modprobe: FATAL: Module amdgpu is in use.`

This happens for usually one of 2 reasons, another kernel module is using amdgpu, and/or certian software and/or daemons are using amdgpu.

First, run this command:

`$ sudo lsmod | grep amdgpu`

You will get an output similar to this:
```
amdgpu              14434304  101
amdxcp                 12288  1 amdgpu
drm_exec               12288  1 amdgpu
gpu_sched              65536  1 amdgpu
drm_buddy              20480  1 amdgpu
drm_suballoc_helper    12288  1 amdgpu
drm_display_helper    274432  1 amdgpu
drm_ttm_helper         16384  2 amdgpu
i2c_algo_bit           16384  1 amdgpu
video                  81920  1 amdgpu
ttm                   106496  2 amdgpu,drm_ttm_helper
drm_kms_helper        253952  3 drm_display_helper,amdgpu,drm_ttm_helper
drm                   770048  38 gpu_sched,drm_kms_helper,drm_exec,drm_suballoc_helper,drm_display_helper drm_buddy,amdgpu,drm_ttm_helper,ttm,amdxcp
crc16                  12288  3 bluetooth,amdgpu,ext4

```

At the top is the amdgpu driver, and below are other modules, and the modules on the right are modules USED by the amdgpu driver. Since there are no modules USING the amdgpu driver, we do not need to remove any additional kernel modules to remove the amdgpu module.

### So, why can't we remove the kernel module?

That's what I was stuck wondering for so long, but I now know that processes and daemons can directly use the driver .ko file, and will NOT show up here, but still throw an error.

To find these services and processes, run this command (RUN THIS ONLY AFTER `start.sh` and after the modprobe error appears and you Ctrl+C'd the script):

`sudo lsof | grep amdgpu`

### If this gives a huge output that is more than a few lines, and includes stuff from your display manager, wayland, xorg, or other processes, then your display manager is not shut down, make sure it is fully shut down (for me I execute `sudo systemctl stop sddm`) before proceeding. If you're using gnome, there are other guides to show how to properly shut down gnome and it's display manager

In my case, a process which controls my fans, `coolercontrold` was using the amdgpu kernel driver, specifically the ko shared library file. By stopping this service, and re-running the script, SUCCESS! My gpu was successfully detatched! Any services or processes you find must be stopped in the `start.sh` (I have a comment where you need to place the commands in the file). Also, restart these processes and services in the `revert.sh` file so that your desktop and apps can be properly restored.

Once these changes are made, run the `start.sh` file, verify that it exits and does not hang(it may take up to 20-30 seconds for it to exit due to the sleep commands in the file), and do the same for `revert.sh`. If your login screen properly restores after `revert.sh` is executed, your single-gpu-passthrough VFIO VM is ready!

# Step 10: Installing the graphics drivers and finalizing the VM setup

### Before starting the VM for the first time with GPU passthrough, make sure windows update is not paused or hindered in any way. Once started, wait roughly 4 minutes for windows to boot and windows update to detect your card, during this time you will have no display output. Then, shut down, reboot without gpu passthrough(in my case I have a duplicate config already pre-configured without passthrough), go to windows update, install the AMD display driver that shows up, and ONLY once fully installed, shut down the vm.

After the first boot, you may have to wait up to 4 minutes(from my experience) for a display signal, or even longer if windows takes a hot second to pick up your gpu drivers and install them, and configure your gpu. I can confirm that multiple displays work, too. When shutting down, once windows shuts down, it may take up to 30 seconds to a minute for your display and login to restore, due to reloading the kernel driver and the delays to prevent race conditions. If you want to reduce these delays, see how long it takes your computer to carry out each task in the startup and shutdown script and adjust accordingly. The delays are intentionally long for extra safety and so that the GPU is not detatched in an unsafe state.