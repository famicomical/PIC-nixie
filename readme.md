# PIC-nixie #
Design of a simple yet accurate Nixie clock controlled by a single chip and some transistors. No arduino. 

For IN-14 or equivalent Nixie neon tubes. 

The time is displayed on four tubes where the cathodes are tied together while the anode pins broken out separately in addition to an optional center neon bulb ( 12:34 ).  The digits are output in binary-coded decimal (BCD) for interfacing the K155ID1 driver. Anodes and the colon are also controlled by the MCU through level shifters.

The program correctly tracks time such that the bottle-neck for clock accuracy will be the external oscillator. Anode blanking was implemented to ensure fast transitions on the Nixie tubes without ghosting (some hardware-side work is also necessary). The clock will also run an outgassing routine every 20 min to prevent "cathode poisoning" to even out wear&tear and ensure a long tube life.

Hardware details and features coming soon!
