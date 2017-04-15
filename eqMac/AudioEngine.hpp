#ifndef __AudioEngine_hpp__
#define __AudioEngine_hpp__

#include "AudioDevice.hpp"
#include <AudioUnit/AudioUnit.h>
#include <AudioToolbox/AUGraph.h>
#import <AudioToolbox/AudioToolbox.h>
#include "RingBuffer.h"
#import <Foundation/Foundation.h>


class AudioEngine {
public:
  AudioEngine(AudioDeviceID inputDeviceID, AudioDeviceID outputDeviceID);
  ~AudioEngine() {}
  void start();
  void stop();
  void reset();

  AudioDevice mInputDevice;
  AudioDevice mOutputDevice;
  AudioStreamBasicDescription absd;
  SFB::RingBuffer buff;

  void setEQBands(Float32 bandArray[]);
  
 protected:
  
  UInt32 mBufferSize;
  
  static OSStatus InputIOProc(AudioDeviceID inDevice, const AudioTimeStamp *inNow, const AudioBufferList *inInputData, const AudioTimeStamp *inInputTime, AudioBufferList *outOutputData, const AudioTimeStamp *inOutputTime, void *inClientData);

  
  AudioComponentDescription eqDescription;
  AudioComponentDescription iDescription;
  AudioComponentDescription oDescription;
  
  AUGraph graph;
  
  AUNode iNode;
  AUNode oNode;
  AUNode eqNode;
  
  AudioUnit iUnit;
  AudioUnit oUnit;
  AudioUnit eqUnit;
  
  void initializeGraph();
  
  AudioDeviceIOProcID mInputIOProcID;

  };

#endif