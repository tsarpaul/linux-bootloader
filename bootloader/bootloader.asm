bits 16
start: jmp boot

%define KERNEL_SETUP_START_SEG 0x7e0
%define KERNEL_SETUP_ENTRY_SEG 0x800
%define KERNEL_SETUP_START 0x7e00
%define KERNEL_START_SEG 0x10000
%define setup_sects 0x1f1
%define root_flags 0x1f2
%define INITRD_SIZE 0x54e000		; TODO: Make this configurable
%define cmd_line_addr 0xff00
errStr db "Error!"			; must be before newline
newline db 0xa, 0xd, 0
cmdline db "auto", 0
cmdlineLen equ $-cmdline

; dh = x, dl = y
MovCursor:
	mov ah, 0x2
	int 0x10
	ret

; si = zero-terminated string addr
Print:
	mov ah, 0xe
	mov bh, 0
	mov bl, 4
	mov cx, 1

	.loop:
		mov al, byte [si]
		inc si

		cmp al, 0
		jz Print.done

		int 0x10
		jmp Print.loop
	.done:
	ret

dap:
	db 0x10			; dap size
	db 0			; reserved
.count:
	dw 0
.offset:
	dw 0
.segment:
	dw 0
.start:
	dd 1			; LBA low bits
	dd 0			; LBA high bits
	
; ax -> sectors count, dx -> destination offset, bx -> segment
ReadDisk:
	push ax				; for MoveHigh
	mov word [dap.count], ax
	mov word [dap.offset], dx
	mov word [dap.segment], bx

	mov ah, 0x42
	mov dl, 0x80
	lea si, [dap]
	int 0x13
	jc err

	; add newly read sectors
	mov edx, [dap.start]
	movzx eax, word [dap.count]
	add edx, eax
	mov [dap.start], edx

	pop ax
	ret

unreal_mode:
	.a20_line:
	mov ax, 0x2401
	int 0x15
	jc err

	.protected_mode:
	lgdt [gdt_desc]
	mov eax, cr0
	or al, 1
	mov cr0, eax
	mov bx, 0x8
	mov ds, bx
	mov es, bx

	.enter_unreal:
	mov eax, cr0
	and al, 0xFE
	mov cr0, eax

	xor bx, bx 		; new limits were cached, restore segment values
	mov ds, bx
	mov es, bx
	ret

highaddr dd 0x100000
MoveHigh:
	mov esi, 0x20000
	mov edi, [highaddr]
	shl eax, 9

	.loop:
	mov edx, [ds:esi]
	mov [ds:edi], edx

	add edi, 4
	add esi, 4
	sub eax, 4
	jnz MoveHigh.loop

	mov [highaddr], edi
	ret

; eax - sectors to move
LoadHigh:
	shr eax, 9
	inc eax

	mov ecx, 0x7f
	xor edx, edx
	div ecx				; ax = batches of 127 sectors, dx = remainder
	push dx

	.loop:
	push ax
	mov ax, 0x7f
	mov bx, 0x2000
	xor dx, dx
	call ReadDisk
	call MoveHigh
	pop ax
	dec ax
	jnz LoadHigh.loop

	pop ax
	test ax, ax
	jz LoadHigh.done

	mov bx, 0x2000
	xor dx, dx
	call ReadDisk
	call MoveHigh
	
	.done:
	ret

err:
	lea si, [errStr]
	call Print
	hlt

boot:
	cli 			; disable interrupts
	cld
	xor bx, bx
	mov ds, bx
	mov ss, bx
	mov sp, 0xe000		; setup stack
	call unreal_mode

setup_cmdline:
	lea si, [cmdline]
	mov cx, cmdlineLen
	mov di, cmd_line_addr
	rep movsb

read_kernel_setup:
	mov bx, KERNEL_SETUP_START_SEG
	mov es, bx
	xor dx, dx 
	mov ax, 1 			; read setup header sector
	call ReadDisk

setup_boot_params:
	
	mov al, [es:0x1f1] 		; setup_sects
	mov dx, 0x200			; load in memory after 1 sectors
	call ReadDisk

	mov bx, [es:0x20e]
	cmp bx, 0			; TODO: Also check setup_sects > 15
	jz load_params

print_kernel_version:
	add bx, 0x200
	add bx, KERNEL_SETUP_START
	mov si, bx
	call Print
	lea si, [newline]
	call Print

load_params:
	mov byte [es:0x210], 0xff 		; type_of_loader
	mov byte [es:0x211], 0x80		; loadflags - CAN_USE_HEAP
	mov word [es:0x224], 0xde00		; heap_end_ptr
	mov dword [es:0x228], cmd_line_addr	; cmd_line_ptr

read_kernel:
	mov eax, [es:0x1f4] 			; syssize
	shl eax, 4
	call LoadHigh

read_initrd:
	mov eax, INITRD_SIZE
	mov dword [es:0x21c], eax 		; ramdisk_size

	mov ebx, 0x2fab000			; qemu load address
	mov dword [es:0x218], ebx		; ramdisk_image
	mov [highaddr], ebx
	call LoadHigh

enter_kernel:
	mov sp, 0xe000
	mov bx, KERNEL_SETUP_START_SEG
	mov es, bx
	mov ds, bx
	mov fs, bx
	mov gs, bx
	jmp KERNEL_SETUP_ENTRY_SEG:0	
	hlt

gdt_desc:
	dw gdt_end - gdt 
	dd gdt

gdt:
gdt_null:
	dq 0			; null entry 0
gdt_data:
	dw 0FFFFh
	dw 0
	db 0
	db 10010010b		; code bit unset
	db 11001111b
	db 0
gdt_end:

# $ - assembly position at the beginning of the line
# $$ - section beginning
times 510 - ($-$$) db 0
dw 0xAA55

