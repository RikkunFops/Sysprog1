# When the PC starts, the processor is essentially emulating an 8086 processor, i.e. 
# a 16-bit processor.  So our initial boot loader code is 16-bit code that will 
# eventually switch the processor into 32-bit mode.

# This code is linked to assume a starting address of 0x7C00 which is where the BIOS
# will load a boot segment.

.code16                         # Assemble for 16-bit mode
.globl start
start:
    jmp     real_start

# Write to the console using BIOS.
# 
# Input: SI contains the address of the null-terminated string to be displayed

cons_write:
    movb    $0x0e, %ah           # 0x0e is the INT 10h BIOS call to output the value contained in AL to screen

cons_write_rpt:
    movb    (%si), %al          # Load the byte at the location contained in the SI register into AL   
    inc     %si                 # Add 1 to the value in SI
    cmp     $0, %al             # Compare the value in AL with 0
    jz      cons_write_done     # If it is zero, then we are done
    int     $0x10               # Output the character in AL to the screen
    jmp     cons_write_rpt      # and continue

cons_write_done:                # Something that is called will never return 
    ret                         # until a 'ret' instruction is encountered.  Labels do 
                                # not give a program any structure.  They just give a 
                                # memory location a name that we can use in our code. 

cons_write_crlf:
    movb    $0x0e, %ah          # Output CR
    movb    $0x0d, %al
    int     $0x10
    movb    $0x0a, %al          # Output LF
    int     $0x10
    ret

cons_writeline:
    call    cons_write
    call    cons_write_crlf
    ret    


reset_sequence:
    call    cons_write_crlf
    xorw    %ax, %ax                 # Set %ax to zero
    movw    %ax, %bx                  # -> Clear bx
    movw    %ax, %cx                 # -> Clear cx
    movw    %ax, %dx                 # -> Clear dx
    
    #movw    $0, %sp                  # Set the stack to the top of the segment

get_selection:
    xorw    %cx, %cx
    movw    $sector_choice, %si
    call    cons_writeline

ThousandNumber: 
    movb    $0x10, %ah
    int     $0x16                       # Interrupt to get keyboard input
    cmpb    $8, %al                     # Check if backspace was pressed
    jz      reset_sequence              # If it was pressed, jump back to the start

    movb    $0x0e, %ah
    int     $0x10

    movb    %al, %cl
    sub     $48, %cl   
                    
    #imul    $1000, %cx                 
    pushw   %cx

HundredNumber: 
    movb    $0x10, %ah
    int     $0x16                       # Interrupt to get keyboard input
    cmpb    $8, %al                     # Check if backspace was pressed
    jz      reset_sequence              # If it was pressed, jump back to the start

    movb    $0x0e, %ah
    int     $0x10

    movb    %al, %cl
    sub     $48, %cl   
                    
    #imul    $100, %cx                   # Multiply the register to get 100 digit
    pushw   %cx
    

TenNumber: 
    movb    $0x10, %ah
    int     $0x16                       # Interrupt to get keyboard input
    cmp     $8, %al                     # Check if backspace was pressed
    jz      reset_sequence              # If it was pressed, jump back to the start

    movb    $0x0e, %ah
    int     $0x10

    movb    %al, %cl
    sub     $48, %cl   
    
                    
    #imul    $10, %cx                    # Multiply the register to get 10 digit
    pushw   %cx

OneNumber: 
    movb    $0x10, %ah
    int     $0x16                       # Interrupt to get keyboard input
    cmp     $8, %al                     # Check if backspace was pressed
    jz      reset_sequence              # If it was pressed, jump back to the start

    movb    $0x0e, %ah
    int     $0x10
    pushw   %ax 
    call    cons_write_crlf
    popw    %ax

    movb    %al, %cl
    sub     $48, %cl
    pushw   %cx


       
reassemble:
    popw    %ax
    
    imul    $1, %ax                       # Multiply the register to get the 1 digit
    add     %ax, %bx

    popw    %ax
    
    imul    $10, %ax                    # Multiply the register to get the 10 digit
    add     %ax, %bx

    popw    %ax
 
    imul    $100, %ax                   # Multiply the register to get the 100 digit
    add     %ax, %bx

    popw    %ax

    imul    $1000, %ax                  # Multiply the register to get the 1000 digit
    add     %ax, %bx


read_sector:
    movw    $disk_address_packet, %si   # Move address of the disk address packet into SI
    movw    $1, 2(%si)                  # Set the number of blocks to read to be 1
    movw    $0xd000, 4(%si)             # Set the address to read into to be 0x9000
    movw    %bx, 8(%si)                  # Set the first block to read to be block 1
    movb    $0x42, %ah                  # 0x42 is the int 13h BIOS function to read the disk using LBA addressing	
    movb    (boot_device), %dl
    int     $0x13                       # Read the disk
    jc      read_failed	                # The carry flag will be set if an error occured

    movb    (0xd000), %al               # Check that what we loaded is not empty
    cmpb    $0, %al
    #je      read_failed
    movw    $0xd000, %si                # Loads 0x0d00 memory address into the %si Register
    

init_offset:
    imul    $512, %bx                   # Multiply the starting sector by 512 to get the starting offset in decimal
    movw    %bx, %dx    
    movw    $3, %cx

check_block:                            # Tracks how many times this loop has been run
    loop    init_loop
    jmp     is_finished
                    

init_loop:
    push    %cx
    movw    $16, %cx                    # Used to keep track of how many times this function has looped
    
 
loop_16:                                # Will loop through the write_hex function 16 times before returing 
    push    %cx                         # Stores the master loop at the top of the stack so it can be retrieved later
    movw    $16, %cx

cons_write_offset:                      # Prepare to write the current offset
    pushw   %si
    pushw   %cx
    movw    $4, %cx
    movb    $0x0e, %ah                  # Prepares %ah to for the printing interrupt
    movw    %dx, %bx                    # Starting offset in decimal

print_offset:                           # Calculates the offset in hex, and then prints it
    rol     $4, %bx
    movw    %bx, %si
    and     $0x000F, %si
    movb    hex_chars(%si), %al  
    int     $0x10
    loop    print_offset
    addw    $16, %dx

    movw    $space_char, %si            # Prints a space character for formatting
    call    cons_write
    popw    %cx
    popw    %si

cons_write_hex:
    pushw   %cx
    
    movw    $2, %cx             # Prepares the loop for the oncoming hexloop       
    movw    (%si), %bx
    pushw   %si

hexloop:
    rol     $4, %bx             # Rotates the bits to the left 4 times
    movw    %bx, %si            # Moves the value into %si 
    rol     $8, %si             # Places the desired value into the right place to be printed
    and     $0x000F, %si        # Performs the logical AND operation on the bytes in %si  
    movb    hex_chars(%si), %al # Moves the appropriate hex character into al so it can be printed
    int     $0x10               # Print to screen interrupt        
    loop    hexloop             # Loops until all of %bx is translated
    
    movw    $space_char, %si    # Prints a space character for formatting
    call    cons_write
    popw    %si                 # Retrieves the memory address from the stack
    inc     %si                 # Increments the memory address pointer
    popw    %cx                 # Retrieves the cons_write_hex counter
    loop    cons_write_hex      # Loops 16 times



cons_write_ascii:     
               
    movw    $16, %cx
    subw    $16, %si            # Subtracts 16 from %si so it starts at the correct position

ascii_loop:
    movb    $0x0e, %ah
    movb    (%si), %al
    cmp     $32, %al            # Ensures the value contained in al can be safely printed
    jle     print_underscore    # If not, will instead print an underscore
    int     $0x10
    inc     %si
    loop    ascii_loop
    call    cons_write_crlf
    jmp     pause_output

print_underscore:
    movb    $95, %al
    int     $0x10
    inc     %si
    loop    ascii_loop

    call    cons_write_crlf

    
pause_output:
    popw    %cx
    loop    loop_16
    push    %si
    movw    $continue_button, %si
    call    cons_writeline
    pop     %si
    movb    $0x10, %ah                  # Prepare the interrupt to wait for keyboard input
    int     $0x16                       # Interrupt to wait for input
    pop     %cx
    jmp     check_block
    
is_finished:
    movw    $finished_string, %si
    call    cons_writeline
    movb    $0x10, %ah
    int     $0x16
    jmp     reset_sequence

 

read_failed:	                      # Display error messages
    movw    $2, %cx
    movb    %al, %dl
    movb    $0x0e, %ah

fail_loop:
    rol     $4, %dx
    mov     %dx, %si
    and     $0x000F, %si
    movb    hex_chars(%si), %al  
    int     $0x10
    loop    fail_loop
    call    cons_writeline

	movw 	$read_failed_msg, %si
    call    cons_writeline
	
	mov 	$cannot_continue, %si	
    call    cons_writeline

    jmp     endless_loop

real_start:
    movb    %dl, (boot_device) # Boot device number is passed in DL from BIOS. Save it hear since DL might get trashed

    movw    $boot_message, %si  # Display our boot message
    call    cons_writeline

    movw    $booted_from_msg, %si
    call    cons_write

    movb    (boot_device), %dl
    cmp     $0x80, %dl
    jge     harddrive

    movw    $fd, %si
    

harddrive:
    movw    $hd, %si

finish:
    call    cons_writeline

    xorw    %ax, %ax                 # Set %ax to zero
    movw    %ax, %ds                 # -> Data Segment
    movw    %ax, %es                 # -> Extra Segment
    movw    %ax, %ss                 # -> Stack Segment
    movw    %ax, %si                 # -> Source Index Register
    movw    $0, %sp                  # Set the stack to the top of the segment

    jmp     get_selection

endless_loop:                   # Loop forever more
    jmp     endless_loop    


boot_device:
    .byte   0

#  Format of disk address packet
# Offset	Size	Description
#  0          1     
#  1          1     always 0
#  2          2     number of sectors to transfer (max 127 on some BIOSes)
#  4          4     transfer buffer (first 2 bytes is 16-bit offset, next 2 bytes is 16 bit segment)
#  8          4     lower 32-bits of 48-bit starting LBA (starting from 0)
#  12         4     upper 16-bits of 48-bit starting LBA (will always be 0 for us)

disk_address_packet:
    .byte   0x10
    .byte   0
    .word   0
    .long   0
    .long   0
    .long   0
offset:

hex_chars: 
    .ascii "0123456789ABCDEF"           # Used as an index for writing the hex offsets

space_char: 
    .string " "     # Used as a blank character for formatting

finished_string:
    .string "You have read the whole sector. Press any button to start over."

input_exception_msg:
    .string "Only numerical values are accepted. Please try again."

accessed_label:
    .string "this is a test string"

sector_choice:
    .string "What sector do you wish to view? (0000-9999) Press backspace to restart"
continue_button:
    .string "Please press a button other than the power putton to continue!"

boot_message:     
    .string "Boot Loader Stage 2 loaded"             
booted_from_msg:
    .string "Booting from "
fd: .string "floppy disk"
hd: .string "hard drive"
get_sector:
    .string "Input desired sector to read: "

read_failed_msg:
    .string "Unable to read stage 2 of the boot process"
cannot_continue:
    .string "Cannot continue boot process"
