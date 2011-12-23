#include <MIDI.h>

/*
 * Radio Shack MIDI Lights
 *
 * Use a MIDI input to sequence strings of holiday lights.
 * 
 * This is the code for the project featured in the December 2011 issue
 * of Popular Science.
 *
 * Check the Github repository for the most recent version of this file
 * https://github.com/vinmarshall/Radio-Shack-MIDI-Lights
 *
 */
 
/* Debugging settings
 * 0 - regular mode - no debugging
 * 1 - Cycle through the relays - 1 to 16 and back
 * 2 - Blink all relays at once - on for 15 seconds, off for 15 seconds
 * 3 - Turn all relays on.
 */
#define DEBUG 0

/*
 * Pin Assignments
 */

// Shift Register Pin Assignments
const int latchPin = 4;  // ST_CP pin of the 74HC595s
const int clockPin = 3;  // SH_CP pin of the 74HC595s
const int dataPin = 5;   // DS pin of the first 74HC595
const int clearPin = 2;  // /MR pin of the 74HC595s

// MIDI Setup
// Connect MIDI IN to RX (Arduino D0).  No assignments necessary.

// Selector Switch Pin Assignments
const int playModePin = 6;  // From one side of the mode selector toggle switch
const int recModePin = 7;   // From the other side of the mode selector switch

// Status LED Pin Assignment
const int statusLED = 13;


/*
 * Globals
 */

// Mode selection 
#define MODE_LIVE 0  // 0 -> Live play mode
#define MODE_REC  1  // 1 -> Recording mode
#define MODE_PLAY 2  // 2 -> Playback mode
int mode = 0;        // Indicates the position of the mode selector switch
int lastMode = 0;
int lastModeState;   // For switch debouncing
unsigned long debounceTime;
unsigned long debounceInterval = 50;

// currentNotes holds the current notes being played or recorded.
// Each bit in the int corresopnds to one relay. 
// e.g. 0x0001 -> relay 1, 0x0002 -> relay 2, 0x0004 -> relay 3, etc...
int currentNotes = 0;

// Note Adjustment - move middle C, #60 in MIDI, down to relay #8
#define NOTE_ADJUSTMENT 53

// Recording setup
#define NUM_TIME_WINDOWS 500
int recordedNotes[NUM_TIME_WINDOWS];  // an array of currentNotes
int recPtr = 0;   // where we are in the recordedNotes array
int lastPtr = 0;  // where recPtr was at the end of the recording

// Number of milliseconds in a recording time window. (resolution)
// A smaller number gives you a greater resolution, but shorter recording time
// Start with this somewhere between 100 and 250
#define INTERVAL 100 
// start time in millis of the current recording window
unsigned long intervalStart = 0;  

void setup() {
  // Setup shift register pins.
  pinMode(latchPin, OUTPUT);
  pinMode(clockPin, OUTPUT);
  pinMode(dataPin, OUTPUT);
  pinMode(clearPin, OUTPUT);

  // Setup the mode selector toggle switch pins
  pinMode(playModePin, INPUT);
  pinMode(recModePin, INPUT);

  // Setup the status LED pin
  pinMode(statusLED, OUTPUT);

  // Clear the shift registers by bringing /MR LOW
  digitalWrite(clearPin, LOW);
  delay(50);
  digitalWrite(clearPin, HIGH);

  // Blink all of the lights on startup.
  for (int i = 0; i < 3; i++) {
    blink(500);
  }

  // MIDI setup
  MIDI.begin(); 
}


void loop() {

  /* 
  * DEBUG Mode - 
  * 
  * If we're in any of the debug modes, we jump out to a separate loop.
  * This will not return control to the main loop.
  */
  if (DEBUG == 1) {
    debugPlayScale(); // This does not return.
  } else if (DEBUG == 2) {
    debugBlink();     // This does not return.
  } else if (DEBUG == 3) {
    debugOn();        // This does not return.
  }

  /*
  * Determine in which mode we are operating
  *
  * playModePin = 0, recModePin = 0  --> Live play mode.  Play the MIDI
  *   input through to the lights without recording.
  * playModePin = 0, recModePin = 1  --> Record mode.  Play the MIDI 
  *   input through to the lights while recording it until the memory is 
  *   full or the mode is changed.
  * playModePin = 1, recModePin = 0  --> Playback mode.  Loop through the 
  *   recorded sequence.
  * playModePin = 1, recModePin = 1  --> Invalid input.  The circuit's 
  *   configuration will prevent this. 
  */

  // Mode switch read and debounce code.
  int playModeReading = digitalRead(playModePin);
  int recModeReading = digitalRead(recModePin);
  int modeReading = recModeReading + (playModeReading << 1);

  // Mark the time of this switch change
  if (modeReading != lastModeState) {
    debounceTime = millis();
  }

  // Switch change is valid if a debouncing interval has passed since last change
  if ((millis() - debounceTime) > debounceInterval) {
    mode = modeReading;
  }

  // Record this reading so we can compare switch positions the next time through
  lastModeState = modeReading;
 
  // if the mode has just changed, do some initializations
  if (lastMode != mode) {
    // Clear whatever notes are on.
    currentNotes = 0x0000;

    if (lastMode == MODE_REC) {
      // Mark where in the buffer this recording ended
      lastPtr = recPtr;
    }
    if (mode == MODE_REC || mode == MODE_PLAY) {
      // reset the buffer pointer when entering record or play mode
      recPtr = 0;
    }

    // log the change
    lastMode = mode;
  }


  if (mode == MODE_LIVE || mode == MODE_REC) {

    /* 
     * If we are in LIVE or RECORD mode, look for a MIDI input 
     */

    // Get a note if one is one is present.
    if (MIDI.read()) {
      switch(MIDI.getType()) {
      case NoteOn: 
        {
          int note = MIDI.getData1();
          int velocity = MIDI.getData2();
          // translate the note into our 16 note system
          // convert middle C (note 60 in MIDI) into relay #8 in our system
          note = note - NOTE_ADJUSTMENT;
        
          // if velocity is greater than 0, this is a note ON
          // otherwise it's actually another form of note OFF
          if (velocity > 0) {
            noteOn(note);
          } else {
            noteOff(note);
          }
          break;
        }
      case NoteOff:
        {
          // Turn notes off for any NoteOff message
          int note = MIDI.getData1();
          note = note - NOTE_ADJUSTMENT;
          noteOff(note);
          break;
        }
      }
    }


    /* 
     * If we're in Recording mode and another time window has passed, 
     * record these notes. 
     */
    if (mode == MODE_REC && (millis() - intervalStart) >= INTERVAL) {
   
      // Record the current notes if the buffer isn't full yet
      if (recPtr < NUM_TIME_WINDOWS) {
        recordedNotes[recPtr++] = currentNotes; // grab the note(s)
        intervalStart = millis(); // restart the interval counter 
        toggleStatusLed();        // flash the metronome / alive LED
      }
    }  
  
  } else {

    /*
     * Otherwise, we are in Playback mode. 
     * We will loop over the notes in the recorded buffer.
     */

    if (millis() - intervalStart >= INTERVAL) {

      // Reset the array pointer if we've reached the end of the recording
      if (recPtr >= lastPtr) {
        recPtr = 0;
      }

      // Set currentNotes to the notes in this window of the recording buffer
      currentNotes = recordedNotes[recPtr++];

      // toggle the metronome/alive LED
      toggleStatusLed();

      // And reset the interval counter
      intervalStart = millis();
    } 
  }  


  /* 
   * "Play" the notes current showing in currentNotes - 
   * either those just played in or those from the recording.  
   *
   * Stop playing notes when the recording buffer is full.
   */
  if (mode == MODE_REC && recPtr >= NUM_TIME_WINDOWS) {
    // Don't play notes - alert user recording buffer is full
    currentNotes = 0x0000;
  }
    
  doOutput();

}

/*
 * doOutput() 
 *
 * Set the relays to the current notes being played or played back.
 * Shifts the two bytes of currentNotes int out into the shift registers
 *
 */
void doOutput() {
  digitalWrite(latchPin, LOW);  // Disable register output changes
  shiftOut(dataPin, clockPin, MSBFIRST, currentNotes >> 8);
  shiftOut(dataPin, clockPin, MSBFIRST, currentNotes);
  digitalWrite(latchPin, HIGH);  // Latch new data to the register outputs
}

/* 
 * void noteOn(int note)
 * 
 * Turns on the note in our representation of the notes currently being 
 * played or played back.
 *
 */
void noteOn(int note) {
  if (note >= 0 && note < 16) {
    currentNotes |= 1<<note;
  }
}
 
/*
 * void noteOff(int note)
 *
 * Turns off the note in our representation of the notes currenting 
 * being played or played back.
 *
 */
void noteOff(int note) {
  if (note >= 0 && note < 16) {
    currentNotes &= ~( 1<<note);
  }
}
 
/*
 * blink(int pause)
 * 
 * Does just what it says - blinks the lights with the specified pause
 * in between.
 */
void blink(int pause) {
  currentNotes = 0xFFFF;    // Turn ON
  doOutput();
  delay(pause);
  currentNotes = 0x0000;    // Turn OFF
  doOutput();
  delay(pause);
}

/*
 * toggleStatusLed()
 * 
 * Toggles the status LED on and off
 * 
 */
void toggleStatusLed() {
  int status = digitalRead(statusLED);
  (status == 1) ? status = LOW : status = HIGH;
  digitalWrite(statusLED, status);
}
 
/*
 * debugPlayScale()
 *
 * Debugging mode.  Cycles up and down through all of the relays - 1 to 16
 * and back.  This method loops here and does not return to the main loop.
 *
 */
void debugPlayScale() {

  // Loop endlessly
  while (1) {
    
    // Cycle up - relay 1 to 16
    for (int i=0; i < 16; i++) {
      noteOn(i);
      doOutput();
      delay(250);
      noteOff(i);
      doOutput();
    }
    
    // and back down
    for (int i=14; i > 0; i--) {
      noteOn(i);
      doOutput();
      delay(250);
      noteOff(i);
      doOutput();
    }
  }
}

/* 
 * debugBlink()
 *
 * Debugging mode.  Flashes all relays on for 1 second, off for 1 second.
 * This method loops here and does not return to the main loop.
 *
 */
void debugBlink() {
  
  // Loop endlessly
  while (1) {
    blink(1000);
  }
}

/*
 * debugOn()
 *
 * Debugging mode.  Turns all relays on.
 * This method loops here and does not return to the main loop.
 *
 */
void debugOn() {
  currentNotes = 0xFFFF;
  doOutput();
  while (1) {}
}
