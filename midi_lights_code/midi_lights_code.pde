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

// Shift Register Pin Assignments
int latchPin = 4;  // ST_CP pin of the 74HC595s
int clockPin = 3;  // SH_CP pin of the 74HC595s
int dataPin = 5;   // DS pin of the first 74HC595
int clearPin = 2;  // /MR pin of the 74HC595s

// MIDI Setup
// Connect MIDI IN to RX (Arduino D0).  No setup necessary.

// Selector Switch Pin Assignments
int playModePin = 6;  // From one side of the mode selector toggle switch
int recModePin = 7;   // From the other side of the mode selector switch

// Status LED Pin Assignment
int statusLED = 13;

// Globals
int mode = 0;        // Indicates the position of the mode selector switch
#define MODE_LIVE 0  // 0 -> Live play mode
#define MODE_REC  1  // 1 -> Recording mode
#define MODE_PLAY 2  // 2 -> Playback mode
int current_notes = 0;  // The notes currently being played / recorded
int *recorded_notes;   // TODO Array initialization and malloc
int rec_ptr = 0;
#define MAX_PTR 255  // Maximum number of time windows of notes to record.
#define INTERVAL 1000  // Number of milliseconds in a recording time window. (resolution)
int interval_start = 0;  // start time in millis of the current recording window

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
  
  // Clear the shift registers
  digitalWrite(clearPin, LOW);
  delay(50);
  digitalWrite(clearPin, HIGH);
  
  // Blink all of the lights on startup.
  for (int i = 0; i < 3; i++) {
    digitalWrite(latchPin, LOW);
    shiftOut(dataPin, clockPin, MSBFIRST, 255);
    shiftOut(dataPin, clockPin, MSBFIRST, 255);
    digitalWrite(latchPin, HIGH);
    delay(500);
    digitalWrite(latchPin, LOW);
    shiftOut(dataPin, clockPin, MSBFIRST, 0);
    shiftOut(dataPin, clockPin, MSBFIRST, 0);
    digitalWrite(latchPin, HIGH);
    delay(500);
    
    // MIDI setup
    MIDI.begin();
  } 
}


void loop() {
  
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
   
  /* If the mode has just changed to record, initalize the recording. */
  
  /* If in Live or Recording mode, look for MIDI input */
  if (mode == MODE_LIVE || mode == MODE_REC) {
    if (MIDI.read()) {
      switch(MIDI.getType()) {
        case NoteOn: 
        {
          int note = MIDI.getData1();
          int velocity = MIDI.getData2();
          
          // translate the note into our 16 note system
          // convert middle C (note 60 in MIDI) into #8 in our system
          note = note - 52;
          
          if (velocity > 0) {
            // if velocity is greater than 0, this is a note ON
            // otherwise it's actually another form of note OFF
            note_on(note);
            break;
          } 
        }
        case NoteOff:
        {
          int note = MIDI.getData1();
          note_off(note);
          break;
        }
      }
    }
    
    
    /* If we're in Recording mode and another time window has passed, 
     * record these notes. 
     * TODO micros rollover handling
     * TODO array size limit
     */
     if (mode == MODE_REC && (millis() - interval_start) >= INTERVAL) {
       recorded_notes[++rec_ptr] = current_notes;
       interval_start = millis();
     }
     
  } else {
    
    /* Play back the recorded notes */
    if (millis() - interval_start >= INTERVAL) {
      current_notes = recorded_notes[++rec_ptr];
      interval_start = millis();
    }
  }
  
  
  /* "Play" the notes current showing in current_notes - either those just played in
   * or those from the recording.
   */
   
    digitalWrite(latchPin, LOW);  // Disable register output changes
    shiftOut(dataPin, clockPin, MSBFIRST, current_notes >> 8);
    shiftOut(dataPin, clockPin, MSBFIRST, current_notes);
    digitalWrite(latchPin, HIGH);  // Latch new data to the register outputs
   
}

/* 
 * void note_on(int note)
 * 
 * Turns on the note in our representation of the notes currently being 
 * played or played back.
 *
 */
 void note_on(int note) {
   current_notes |= 1<<note;
 }
 
 /*
  * void note_off(int note)
  *
  * Turns off the note in our representation of the notes currenting being played or 
  * played back.
  *
  */
 void note_off(int note) {
   current_notes &= ~( 1<<note);
 }
