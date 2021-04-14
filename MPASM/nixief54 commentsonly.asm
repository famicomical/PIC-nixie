;
;********************************************************************
	LIST    P = 16F54, n = 66
;
;                      Clock
;*********************************************************************
;
;			PROGRAM DESCRIPTION
; 
; This program emulates a clock and generates output signals to display the time on
; four common-anode nixie tubes. the programs runs on a PIC16F54 MCU. (16C54 is deprecated)
; Adapted from CLOCK54.ASM contained within the Microchip Application Note AN590 
; herein reproduced and modified by Rony Ballouz
;
;                       Hardware Description
;
;  DISPLAYS
; Four IN-14 Nixie Neon Tubes are multiplexed. The cathodes are tied together, with
; the anode pins broken out separately.  The display appears as a clock
; with an optional center neon bulb ( 12:34 ).  The digits are output to the upper 4
; bits of Port B in binary-coded decimal (BCD) for interfacing the K155ID1 driver. The
; colon is controlled by RB0, while RB1-3 act as inputs for switches to set the time.
;  The four common anodes are attached to the four Port A pins through level shifters.
; RA0 for CA0, RA1/CA1... through CA3.  
;
;  SWITCHES
; Port B is connected to switches such that SWX connects RBX to VCC (X=0,1,2,3) 
; SW2 and SW3 allow the user to set the minutes and hours respectively, and SW1 sets the
; display to show seconds. The optional SW0 can be connected for use as a reset switch.
;
; In the original code, all I/O pins are already used for the muxed displays, so the
; switches are read in alternatingly through software. Port B pins are changed to inputs 
; momentarily during read and changed back to outputs during display.
;
;
;
;**************************   Header *************************
;
;
PIC54   equ     H'01FF'
PIC56   equ     H'03FF'
;
POINTER	equ     H'00'
TMR0    equ     H'01'
PC      equ     H'02'
STATUS  equ     H'03'       ; F3 Reg is STATUS Reg.
FSR     equ     H'04'
;
PORT_A  equ     H'05'		; Nixie Anode Control
PORT_B  equ     H'06'       ; Center Colon and BCD bits (Switches when inputs)
;
                        	; STATUS REG. Bits
CARRY   equ     0       	; Carry Bit is Bit.0 of F3
C       equ     0
DCARRY  equ     1
DC      equ     1
Z_bit   equ     2       	; Bit 2 of F3 is Zero Bit
Z       equ     2
P_DOWN  equ     3
PD      equ     3
T_OUT   equ     4
TO      equ     4
PA0     equ     5       	;16C5X Status bits
PA1     equ     6      		;16C5X Status bits
PA2     equ     7       	;16C5X Status bits
;
ZERO	equ		H'7E'
ONE	equ		H'0C'
TWO	equ		H'B6'
THREE	equ		H'9E'
FOUR	equ		H'CC'
FIVE	equ		H'DA'
SIX	equ		H'FA'		; Mapping of segments for display (PORT_B)
SEVEN	equ		H'0E'
EIGHT	equ		H'FE'
NINE	equ		H'CE'
COLON	equ		H'01'
T	equ		H'F0'
BLANK	equ		H'00'
;
MAXNTHS	equ		D'12'		; constants for timer variable count up
MAXSECS	equ		D'196'		;  variables roll over in HEX at time roll over, see variable
MAXMINS	equ		D'196'		;  explanation
MAXHRS	equ		D'244'
MINHRS	equ		D'243'
ADJMIN	equ		D'9'		; number of nths that need to be subtracted each minute
ADJHR	equ		D'34'		; nths added each hour for accurate time
ADJDAY	equ		D'3'		; nths subtracted each 1/2 day rollover
;
DISP1	equ		B'11111110'
DISP2	equ		B'11111101'	; Mapping of Active Display Selection (PORT_A)
DISP3	equ		B'11111011'
DISP4	equ		B'11110111'
DISPOFF	equ		H'FF'
SWITCH	equ		B'00001110'	; Activate RB1-3 for switch inputs     
;
;  Flag bit assignments
SEC	equ		H'0'		; update time display values for sec, min, or hours
MIN	equ		H'1'
HRS	equ		H'2'
CHG	equ		H'3'		; a change has occurred on a switch or to a potentially displayed value				 
SW1	equ		H'4'		; Flag bit assignments - switches that are on = 1
SW2	equ		H'5'		;  SW1 is Seconds-minutes, SW2-hours, SW3-mode
SW3	equ		H'6'
SW_ON	equ		H'7'		; a switch has been pressed
;
;   VARIABLES
keys	equ		H'08'		; variable location - which keys are pressed? bit0/sw1... 
flags	equ     	H'09'		; bit flags; 0-SEC, 1-MIN, 2-HRS, 3-CHG, 4-SW1, 5-SW2, 6-SW3
;	equ		H'0A'		; Not Used
display equ     	H'0B'		; variable location - which display to update
digit1	equ		H'0C'		; Rightmost display value
digit2	equ		H'0D'		; Second display from right
digit3	equ		H'0E'		; Third    "       "    "
digit4	equ		H'0F'		; Fourth (and Leftmost)
;
;	timer variables start at a number that allows rollover in sync with time rollover,
;	 i.e. seconds starts at decimal 196 so that sixty 1-second increments causes 0.
sec_nth	equ		H'10'		; seconds, fractional place
seconds	equ		H'11'		; seconds
minutes	equ		H'12'  		; minutes
hours	equ		H'13'  		; hours
var	equ		H'14'		; variable for misc math computations
count	equ		H'15'		; loop counter variable
count2	equ		H'16'		; 2nd loop counter for nested loops

;
;********************************************************************************
;
;  Initialize Ports all outputs, blank display
;
START   
		movlw	H'03'   	; set option register, transition on clock,
		option			; Prescale TMR0, 1:16 (contents of the W register
					; will be transferred to the Option register)
;
		movlw	0
		tris	PORT_A		; Set all port pins as outputs
		tris	PORT_B
		movlw	BLANK
		movwf	PORT_B		; Blank the display
		bcf	STATUS,PA1	;set memory to page 0
		bcf	STATUS,PA0
;
;  initialize variables
		movlw	H'01'
		movwf	TMR0		; set TMR0 above zero so initial wait period occurs
		movlw	H'FE'
		movwf	display		; initializes display selected to first display.
		movlw	BLANK		; put all displays to blank, no visible segments
		movwf	digit1
		movwf	digit2
		movwf	digit3
		movwf	digit4
		movlw	MAXNTHS		; set timer variables to initial values
		movwf	sec_nth
		movlw	MAXSECS
		movwf	seconds
		movlw	MAXMINS
		movwf	minutes
		movlw	H'FF'		; hours start at 12 which is max at FF
		movwf	hours
		movlw	H'00'
		movwf	flags
;
;
;
MAIN 
;
TMR0_FILL
		movf	TMR0,0
		btfss	STATUS,Z  	; skip if TMR0 has not rolled over
					; TMR0 is left free running to not lose clock cycles on writes
		goto	TMR0_FILL	
;
		incfsz	sec_nth,1  	; add 1 to nths, n X nths = 1 sec, n is based on prescaler
		goto	TIME_DONE
		movlw	MAXNTHS
		movwf	sec_nth  	; restore sec_nths variable for next round
;
CHECK_SW
		btfss	flags,SW_ON ; if no switches pressed, bypass this
		goto	SET_TIME
		btfsc	flags,SW1
		goto	SET_TIME    ; if seconds display is pressed, do not change time
		movlw	MAXSECS
		movwf	seconds	    ; reset seconds to zero when setting clock
		movlw	H'7F'
		movwf	sec_nth	    ; advance second timer 1/2 second to speed time setting
		btfss	flags,SW2
		goto	HOURSET	    ; minutes do not need changing, check hours
		movlw	H'AF'
		movwf	sec_nth	    ; advances timer faster when setting minutes
		incfsz	minutes,1
		goto	HOURSET
		movlw	MAXMINS
		movwf	minutes
;
HOURSET	
		btfsc	flags,SW2
		goto	CHECK_TIME 	; not changing hours
		incfsz	hours,1
		goto	CHECK_TIME
		movlw	MAXHRS
		movwf	hours
		goto	CHECK_TIME 	; since no timing is required, go to display changes
;
SET_TIME
		bsf	flags,SEC 	; seconds, if displayed, should be updated
		bsf	flags,CHG 	; a flag change was made.
		incfsz	seconds,1 	;  add 1 to seconds
		goto	TIME_DONE
		movlw	MAXSECS
		movwf	seconds   	; restore seconds variable for next round
;
		bsf	flags,MIN 	; minutes, if displayed, should be updated
		bsf	flags,CHG
		movlw	ADJMIN
		subwf	sec_nth,1 	; subtraction needed adjustment for each minute
		incfsz	minutes,1  	; add 1 to minutes
		goto	TIME_DONE
		movlw	MAXMINS
		movwf	minutes	  	; restore minutes variable for next hour countdown
;
		bsf	flags,HRS
		bsf	flags,CHG
		movlw	ADJHR
		addwf	sec_nth,1 	; add needed adjustment for each hour
		incfsz	hours,1	  	; add 1 to hours
		goto	TIME_DONE
		movlw	MAXHRS
		movwf	hours	  	; restore hours variable for next round
		movlw	ADJDAY
		subwf	sec_nth,1 	; subtraction adjustment for each 1/2 day rollover
;
TIME_DONE
		btfss	flags,CHG	; if no switches or potentially dislayed numbers were
	 	goto	CYCLE		;  changed, then skip updating display variables
;
;
CHECK_SECONDS
;  if seconds is button was pushed and not mode display seconds
		btfss	flags,SW1
		goto	CHECK_TIME
		movlw	H'00'
		movwf	digit2		; 3rd digit variable used to store temp hex value for hours display
		movwf	digit3
		movwf	digit4
		movlw	MAXSECS
		subwf	seconds,0
		movwf	digit1  	; 1st digit variable temporarily holds hex value for seconds display
		goto	SPLIT_HEX
;
CHECK_TIME
		movlw	H'00'
		movwf	digit4	  	; zero out tens places in case there is no tens increment
		movwf	digit2
		movlw	MINHRS
		subwf	hours,0
		movwf	digit3    	; 3rd digit variable temporarily holds hex value for hours
		movlw	MAXMINS
		subwf	minutes,0
		movwf	digit1	  	; 1st digit temporarily holds hex value for minutes
;
;
;
SPLIT_HEX	;  split into two hex display variables and write
;
		movlw	H'02'
		movwf	count		; loop to convert each number - seconds - or minutes and hours

;1st time through, FSR = digit1, 2nd time FSR = digit3
		movlw	digit1		; 
		movwf	FSR			; address of digit1 into File Select Register enables POINTER
		goto	LOOP		; this loop is used to modify the minutes/seconds place
;
LOOP2	
		movlw	digit3
		movwf	FSR	; this loop is used to modify the hours place
;
LOOP
		movlw	D'10'
		subwf	POINTER,1       ; find out how many tens in number,
		btfsc	STATUS,C        ; was a borrow needed?
		goto	INCREMENT_10S   ;  if not, add 1 to tens position
		addwf	POINTER,1       ;  if so, do not increment tens place, add ten back on to get 1s
		goto	NEXT_DIGIT
;
INCREMENT_10S
		incf	FSR,1	  	; bump address pointed to from 1s positoion to 10s
		incf	POINTER,1 	; add 1 to 10s position as determined by previous subtract
		decf	FSR,1	  	; put POINTER value back to 1s place for next subtraction
		goto    LOOP	  	; go back and keep subtracting until finished
;
NEXT_DIGIT
		decfsz	count,1
		goto	LOOP2
;
CONVERT_HEX_TO_DISPLAY  ; converts hex number in digit variables to decimal display code
		movlw	digit1	
		movwf	FSR	; put the address of the first digit into the FSR to enable POINTER
		movlw	H'04'
		movwf	count	; prepare count variable to loop for all four displays
NEXT_HEX
		movf	POINTER,0    ; get the hex value of the current digit variable
		call	RETURN_CODE  ; call for the hex to decimal display conversion
		movwf	POINTER	     ; put the returned display code back into the digit variable
		incf	FSR,1	     ; increment the pointer to the next digit variable address
		decfsz	count,1	     ; allow only count(4) times through loop
		goto	NEXT_HEX
;
FIX_DISPLAY
		movlw	ZERO
		subwf	digit4,0
		btfss	STATUS,Z
		goto	FIX_SEC
		movlw	BLANK
		movwf	digit4

FIX_SEC	
		btfss	flags,SW1
		goto	CLEAR_FLAGS
		movwf	digit3	
;
CLEAR_FLAGS
		movlw	H'F0'
		andwf	flags,1	     ; clear the lower 4 flag bits to show update status
;
CYCLE
		movlw	DISPOFF
		movwf	PORT_A	   	; Turn off LED Displays
		movlw	SWITCH
		tris	PORT_B	   	; Set some port B pins as switch inputs
		movlw	H'0F'
		andwf	flags,1	   	; reset switch flags to zero
		nop		   	; nop may not be needed, allows old outputs to bleed
		nop		        ; off through 10k R before reading port pins
		nop
		movf	PORT_B,0
		movwf	var
		btfss	var,1
		goto	SWITCH2
		bsf	flags,CHG
		bsf	flags,SW1
		bsf	flags,SW_ON
;
SWITCH2	
		btfss	var,2
		goto	SWITCH3
		bsf	flags,CHG
		bsf	flags,SW2
		bsf	flags,SW_ON
SWITCH3	
		btfss	var,3
		goto	SETPORT
		bsf	flags,CHG
		bsf	flags,SW3
		bsf	flags,SW_ON
;
SETPORT	
		movlw	H'00'
		tris	PORT_B
		movlw	BLANK
		movwf	PORT_B
;
;   determine which display needs updating and cycle it on
		btfss	display,0  ; if 1st display, get 1st digit
		movf	digit4,0
		btfss	display,1  ; if 2nd display, get 2nd digit
		movf	digit3,0
		btfss	display,2  ; if 3rd display, get 3rd digit
		movf	digit2,0
		btfss	display,3  ; if 4th display, get 4th digit
		movf	digit1,0
		movwf	PORT_B	   ; put the number out to display
		btfsc	sec_nth,7
		bsf		PORT_B,0   ; sets colon decimal on %50 duty using highest bit
		movf	display,0  ; get display needing cycle on
		movwf	PORT_A	   ; enables proper display
		movwf	display    ; returns old w if not done, new w if resetting display
		rlf		display,1  ; rotate display "on" bit to next position
		bsf		display,0  ; assures a 1 on lowest position since rotated carry is zero
		btfss	display,4  ; check if last display was already updated
		bcf		display,0  ; if it was, set display back to 1st (bit 0 set)
;
;
;
        goto    MAIN
;
RETURN_CODE
;
		addwf	PC,1
		retlw	ZERO
		retlw	ONE
		retlw	TWO
		retlw	THREE
		retlw	FOUR
		retlw	FIVE
		retlw	SIX
		retlw	SEVEN
		retlw	EIGHT
		retlw	NINE
;
;
        org     PIC54
        goto    START
;
    END
