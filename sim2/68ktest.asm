	section .text

    org $400000

vector:
	dc.l $1234
    dc.l main

main:
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	move.w #$1234,d0
	loop:
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	move.w d0,6
	move.w 6,d1
	cmp.w d0,d1
	bne error
	nop
	nop
	bra loop

error:
	bra error
