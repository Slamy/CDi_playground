	section .text

    org $400000

vector:
	dc.l $1234
    dc.l main

main:

	; Make a pause at the start to relax the UART on the linux side
	move #4000,d0
start_delay:
	add #-1,d0
	bne start_delay

	lea string,a0
loop:

wait_til_ready:
	move.b $80002013,d0
	btst.l #$2,d0
	beq wait_til_ready

	move.b (a0),d0
	beq end
	move.b d0,$80002019
	adda #1,a0

	bra loop

end:
wait_for_char:
	move.b $80002013,d0
	btst.l #0,d0
	beq wait_for_char

	move.b $8000201b,d0

wait_til_ready2:
	move.b $80002013,d1
	btst.l #$2,d1
	beq wait_til_ready2

	add #1,d0
	move.b d0,$80002019

	bra end

string:
	dc.b "Hallo Welt!"
	dc.b 0
