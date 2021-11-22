;
;********************************************************************
	LIST    P = 16F54, n = 66
;
;                      Nixie Clock
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
; Four IN-14 Nixie Neon Tubes are multiplexed. The cathodes are tied together while
; the anode pins broken out separately.  The time is displayed on four tubes
; with an optional center neon bulb ( 12:34 ).  The digits are output to the upper 4
; bits of Port B in binary-coded decimal (BCD) for interfacing the K155ID1 driver. The
; colon is controlled by RB0, while RB1-3 act as inputs for switches to set the time.
; The four common anodes are attached to the four Port A pins through level shifters.
; RA0 and RA2 for 10s place in hours and mins, RA1 RA3 for 1s place in hours and mins.  
;
;  SWITCHES
; Port B is connected to switches such that SWX connects RBX to VCC (X=1,2,3) 
; SW2 and SW3 allow the user to set the minutes and hours respectively, and SW1 sets the
; display to show seconds. 
;
; TODO:	invert 'display' use cases, port a outputs -- done
;	fix hex outputs to port b -- done: removed routine for converting digits 
;				now implemented by 4x left rotate during refresh
;	incorporate blanking -- done
; 	add cathode poisoning prevention routine -- counter variable poison gets 
;		incremented every minute. if equal 20 then run poison prevention
;		by hijacking the 'cycle' execution with a loop that runs each
;		digit on each tube for 1 full second. after all 40 cathodes are 
;		outgassed then 'poison' gets reset. pressing any switch resets
;		'poison' and should end the outgassing routine if it is running.
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
COLON	equ		H'01'
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
display equ     	H'0B'		; variable location - which digit to update 
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
poison	equ		H'17'		; poisoning minute counter, bit 6 and 7 are status and ready bit
ppcount	equ		H'18'		; loop variable for poison prevention routine 
;
;********************************************************************************
;
;  Initialize Ports all outputs, blank display
;

	__config	B'1001'	; set oscillator mode to XT, Watchdog Timer is off
START   
	movlw	H'03'   	; set option register, transition on CLKOUT,
	option			; Prescale TMR0, 1:16 (contents of the W register
				; will be transferred to the Option register)
;
	movlw	0
	tris	PORT_A	; Set all port pins as outputs
	tris	PORT_B
	movlw	BLANK
	movwf	PORT_B	; Blank the display
	bcf	STATUS,PA1
	bcf	STATUS,PA0
;
;  initialize variables
	movlw	H'01'
	movwf	TMR0		; set TMR0 above zero so initial wait period occurs
	movlw	H'01'		; inverted from 'FE' cause we Common anode now
	movwf	display		; initializes 'display' selected to first display.
	movlw	BLANK		; put all displays to blank
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
	movwf	poison
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
	btfss	flags,SW_ON ; if no switches pressed, adjust time naturally
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
;this code only runs once a second and updates the stored time
	bsf	flags,SEC 	; seconds, if displayed, should be updated. 
	bsf	flags,CHG 	; a flag change was made.
	incfsz	seconds,1 	;  add 1 to seconds
	goto	TIME_DONE	; if seconds did not rollover, short circuit
	movlw	MAXSECS
	movwf	seconds   	; restore seconds variable for next round
;
	bsf	flags,MIN 	; minutes, if displayed, should be updated
	bsf	flags,CHG
	movlw	ADJMIN
	subwf	sec_nth,1 	; subtraction needed adjustment for each minute
	incf	poison,1	; add 1 to poison counter
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
	btfss	flags,CHG	; if no change in stored clock time, 
 	goto	CYCLE		;  cycle digits without updating digit vars
 				; display vars are set in next few subs
;
CHECK_POISON
		movlw	D'20'		;20 min(/4) of on-time. 1/4 factor due to muxing
		subwf	poison, 0
		btfsc	STATUS, Z	;every 20 min 
		goto	CHECK_SECONDS	; run the poison prevention routine
;
		bsf	poison, 6	;this sub runs every second, so inidicate a second has passed
;
		btfss	poison, 7	;if poison prevention is not already running
		goto	INITPOISON	; initialize the digits

		;poison loop logic here: cycle digits, clear 'poison' and goto check secs if done outgassing
		; on first run, a '0' has already been displayed at the hr10s digit for 1 sec, and 'display' is set on digit3.
		incf	POINTER,1	; increment cathode for previously displayed tube
		decf	FSR,1		; move up to next tube

		movlw	display		; check cycle for wraparound 
		xorwf	FSR,0		; set status bits for FSR='digit4'-4='display'
		movlw	D'4'		; prepare w to bump FSR back; this does not set any flags
		btfsc	STATUS,Z	; if FSR!='display' skip bumping
		addwf	FSR,1		;

		decfsz	ppcount,1	
		goto	CLEAR_FLAGS

		clrf	poison		;loop has ended, reset the poison timer
		goto 	CHECK_SECONDS	;ensure that clock resumes normal display immediately
;

INITPOISON
		bsf 	poison, 7	
		movlw	digit4
		movwf	FSR
		movlw	D'40'
		movwf	ppcount
		clrf	display
		clrf 	digit1
		clrf 	digit2
		clrf 	digit3
		clrf 	digit4
		incf	display,1	; POINTER=digit4 and display=0001 syncs the poison prevention logic loop 
		goto	CLEAR_FLAGS	; with the update loop
;
CHECK_SECONDS
	btfss	flags,SW1	;skip this sub if not displaying secs
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
	movwf	digit3    	; 'digit3' temporarily holds hex value for hours
	movlw	MAXMINS
	subwf	minutes,0
	movwf	digit1	  	; 'digit1' temporarily holds hex value for minutes
;
;
;
SPLIT_HEX	;  this loop puts min1s->digit1, min10s->digit2, hr1s->digit3, hr10s->digit4
;
	movlw	H'02'
	movwf	count		; loop to convert each number - seconds - or minutes and hours
				;1st time through, FSR = digit1, 2nd time FSR = digit3
	movlw	digit1		; 
	movwf	FSR		; address of digit1 into File Select Register enables POINTER
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
	incf	FSR,1	  	; bump address pointed to from 1s position to 10s
	incf	POINTER,1 	; add 1 to 10s position as determined by previous subtract
	decf	FSR,1	  	; put POINTER value back to 1s place for next subtraction
	goto    LOOP	  	; go back and keep subtracting until finished
;
NEXT_DIGIT
	decfsz	count,1
	goto	LOOP2

CLEAR_FLAGS
	movlw	H'F0'
	andwf	flags,1	     ; clear the lower 4 flag bits to show update status
;
;****************************************************************************************
CYCLE
;reads the switches every refresh (4ms), handles muxing and displaying digits
;there's a 100us delay between runs of this subroutine
;
	movlw	BLANK		; turn the anode off
	movwf	PORT_A		

; anode blanking busywait assuming 1 microsec per instruction, 2 instructions per loop
	movlw 	D'30'		;30*2 = 60us
	movwf	count
BLOOP
	decfsz 	count,1
	goto	BLOOP

;
CHECKSWITCHES
	movlw	SWITCH
	tris	PORT_B	   ; Set some port B pins as switch inputs
	movlw	H'0F'
	andwf	flags,1	   ; reset switch flags to zero
	nop		   ; nop may not be needed, allows old outputs to bleed
	nop		   ;   off through 10k R before reading port pins
	nop
	movf	PORT_B,0
	movwf	var
SWITCH1
	btfss	var,1		;check if sw1 pressed and so on for sw2 and sw3
	goto	SWITCH2
	bsf	flags,CHG
	bsf	flags,SW1
	bsf	flags,SW_ON
	clrf	poison
;
SWITCH2	
	btfss	var,2
	goto	SWITCH3
	bsf	flags,CHG
	bsf	flags,SW2
	bsf	flags,SW_ON
	clrf	poison
;
SWITCH3	
	btfss	var,3
	goto	SETPORT
	bsf	flags,CHG
	bsf	flags,SW3
	bsf	flags,SW_ON
	clrf	poison
;
;
SETPORT	movlw	H'00'
	tris	PORT_B
	movlw	BLANK
	movwf	PORT_B
;
POISONCHECK
		btfss	poison,7	;if poison prevention is not running then cycle as normal
		goto	UPDATE
		btfss	poison,6	;if  a second has not passed
		goto	MAIN		;skip the rest of this
		bcf 	poison,6	;reset once-a-second update flag

UPDATE
;determine which display needs updating and cycle it on, 'digitx' contains the display bits

	btfsc	display,0  ; if 1st display, get 1st digit
	movf	digit4,0
	btfsc	display,1  ; if 2nd display, get 2nd digit
	movf	digit3,0
	btfsc	display,2  ; if 3rd display, get 3rd digit
	movf	digit2,0
	btfsc	display,3  ; if 4th display, get 4th digit
	movf	digit1,0

	movwf	var
	swapf	var, 1
	btfsc	seconds,0
	bsf	var,0   ; sets colon decimal at 2Hz
	movf	var,0 

	movwf	PORT_B	   ; put the number out to display

; anode blanking busywait 2
	movlw 	D'30'		; total is 30*2*2+100 = 220us
	movwf	count
BLOOP2
	decfsz 	count,1
	goto	BLOOP2

	movf	display,0  ; get display needing cycle on
	movwf	PORT_A	   ; enables proper display
	movwf	display    ; returns old w if not done, new w if resetting display
	bcf 	STATUS, 0
	rlf	display,1  ; rotate display "on" bit to next position; 
	btfsc	display,4  ; check if last display was already updated
	bsf	display,0  ; if it was, set display back to 1st (bit 0 set)
	bcf	display,4  
;
;
;
        goto    MAIN
;
    END
