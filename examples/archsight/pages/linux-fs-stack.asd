theme "cozy"

application "app" { label "Application (read/write)" }

stack "io_stack" {
  label "Linux Kernel I/O Stack"

  component "syscall" { label "System Call Interface" }

  group "vfs_layer" {
    label "VFS"
    tint "blue"
    component "vfs" { label "Virtual Filesystem Switch" }
  }

  layer "filesystems" {
    label "Filesystem Drivers"
    tint "teal"
    component "ext4"  { label "ext4" }
    component "xfs"   { label "XFS" }
    component "btrfs" { label "Btrfs" }
  }

  component "page_cache" { label "Page Cache" }

  group "block_layer" {
    label "Block Layer"
    tint "purple"
    component "bio"         { label "bio / Block I/O Layer" }
    component "ioscheduler" { label "I/O Scheduler" }
  }

  layer "drivers" {
    label "Device Drivers"
    tint "orange"
    component "nvme_drv" { label "NVMe Driver" }
    component "scsi_drv" { label "SCSI/SATA Driver" }
  }

  layer "devices" {
    label "Block Devices"
    tint "brown"
    component "nvme_dev"  { label "NVMe SSD" }
    component "sata_disk" { label "SATA Disk" }
  }
}

app -> syscall
syscall -> vfs

vfs -> ext4
vfs -> xfs
vfs -> btrfs

ext4  -> page_cache
xfs   -> page_cache
btrfs -> page_cache

page_cache -> bio
bio -> ioscheduler

ioscheduler -> nvme_drv
ioscheduler -> scsi_drv

nvme_drv -> nvme_dev
scsi_drv -> sata_disk
