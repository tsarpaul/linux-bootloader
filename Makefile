BUILD_DIR=build
BOOTLOADER_BUILD_DIR=$(BUILD_DIR)/bootloader
BOOTLOADER=$(BOOTLOADER_BUILD_DIR)/bootloader.o
DISK_IMG=disk.img
KERNEL_IMG=./ubuntu16-vmlinuz
INITRD_IMG=./custom-initramfs


all: bootdisk

.PHONY: bootdisk bootloader

bootloader:
	mkdir -p $(BOOTLOADER_BUILD_DIR)
	make -C bootloader

bootdisk: bootloader
	dd conv=notrunc if=$(BOOTLOADER) of=$(DISK_IMG) bs=512 count=1 seek=0 
	dd conv=notrunc if=$(KERNEL_IMG) of=$(DISK_IMG) bs=512 count=$$(($(shell stat --printf="%s" $(KERNEL_IMG))/512+1)) seek=1
	dd conv=notrunc if=$(INITRD_IMG) of=$(DISK_IMG) bs=512 count=$$(($(shell stat --printf="%s" $(INITRD_IMG))/512)) seek=$$(($(shell stat --printf="%s" $(KERNEL_IMG))/512+2))
	dd if=/dev/zero bs=512 count=1 >> $(DISK_IMG)
	echo "Done!"

clean:
	make -C bootloader clean

qemu:
	qemu-system-i386 -machine q35 -hdd $(DISK_IMG)

qemu-debug:
	qemu-system-i386 -machine q35 -hdd $(DISK_IMG) -gdb tcp::26000 -S

