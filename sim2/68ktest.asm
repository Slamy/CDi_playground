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
	bra main
