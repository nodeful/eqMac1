#include <iostream>
#include <fstream>
#include <time.h>
#include <AudioToolbox/AudioFile.h>
#include <AudioToolbox/AudioConverter.h>
#include "AudioEngine.hpp"
#include "AudioDevice.hpp"




AudioEngine::AudioEngine(AudioDeviceID inputDeviceID, AudioDeviceID outputDeviceID) : mInputDevice(inputDeviceID, true), mOutputDevice(outputDeviceID, false),  mBufferSize(1024) {
  mInputDevice.SetBufferSize(mBufferSize);
  mOutputDevice.SetBufferSize(mBufferSize);
}


OSStatus AudioEngine::InputIOProc(AudioDeviceID inDevice, const AudioTimeStamp *inNow,const AudioBufferList *inInputData,const AudioTimeStamp *inInputTime,AudioBufferList *outOutputData,const AudioTimeStamp *inOutputTime,void *inClientData) {
  
  AudioEngine *This = (AudioEngine *)inClientData;
  This->buff.Write(inInputData->mBuffers[0].mData, inInputData->mBuffers[0].mDataByteSize);

  return noErr;
}



static OSStatus renderInput(void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumberFrames, AudioBufferList *ioData){
  AudioEngine *This = (AudioEngine *)inRefCon;
  
  AudioBuffer *buffer = &(ioData->mBuffers[0]);
  UInt32 bytesRequired = buffer->mDataByteSize;
  
  NSUInteger availableData = This->buff.GetBytesAvailableToRead();
  if (availableData < bytesRequired) {
    buffer->mDataByteSize = 0;
    *ioActionFlags |= kAudioUnitRenderAction_OutputIsSilence;
    return noErr;
  }
  
  This->buff.Read(ioData->mBuffers[0].mData, ioData->mBuffers[0].mDataByteSize);
  
  return noErr;
}

void AudioEngine::start() {
  if (mInputDevice.mID == kAudioDeviceUnknown || mOutputDevice.mID == kAudioDeviceUnknown) return;
  if (mInputDevice.mFormat.mSampleRate != mOutputDevice.mFormat.mSampleRate) {
    mInputDevice.SetSampleRate(mOutputDevice.mFormat.mSampleRate);
  }

  buff.Allocate(8192*mBufferSize);
  absd = mInputDevice.mFormat;
 
  mInputIOProcID = NULL;
  AudioDeviceCreateIOProcID(mInputDevice.mID, InputIOProc, this, &mInputIOProcID);
  AudioDeviceStart(mInputDevice.mID, mInputIOProcID);

  initializeGraph();
 
}

void AudioEngine::stop() {
  AudioDeviceStop(mInputDevice.mID, mInputIOProcID);
  AudioDeviceDestroyIOProcID(mInputDevice.mID, mInputIOProcID);
  AUGraphStop(graph);
  AUGraphUninitialize(graph);
  AUGraphClose(graph);
}




Float32 map(Float32 x, Float32 in_min, Float32 in_max, Float32 out_min, Float32 out_max)
{
  return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
}

void AudioEngine::setEQBands(Float32 bandArray[]){
  for (int i = 0; i<10; i++) {
    AudioUnitParameterID parameterID = kAUNBandEQParam_Gain + i;
    AudioUnitSetParameter(eqUnit,parameterID, kAudioUnitScope_Global,0,map(bandArray[i], 0.0, 1.0, -24.0, 24.0),0);
  }
  
  
}

void AudioEngine::initializeGraph(){
  eqDescription.componentType = kAudioUnitType_Effect;
  eqDescription.componentSubType = kAudioUnitSubType_NBandEQ;
  eqDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
  eqDescription.componentFlags = 0;
  eqDescription.componentFlagsMask = 0;
  
  oDescription.componentType = kAudioUnitType_Output;
  oDescription.componentSubType = kAudioUnitSubType_HALOutput;
  oDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
  oDescription.componentFlags = 0;
  oDescription.componentFlagsMask = 0;
  
  iDescription.componentType = kAudioUnitType_FormatConverter;
  iDescription.componentSubType = kAudioUnitSubType_AUConverter;
  iDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
  iDescription.componentFlags = 0;
  iDescription.componentFlagsMask = 0;
  
  
  NewAUGraph(&graph);
  AUGraphOpen(graph);
  
  AUGraphAddNode(graph, &iDescription, &iNode);
  AUGraphAddNode(graph, &eqDescription, &eqNode);
  AUGraphAddNode(graph, &oDescription, &oNode);
  
  AUGraphNodeInfo(graph, iNode, NULL, &iUnit);
  AUGraphNodeInfo(graph, eqNode, NULL, &eqUnit);
  AUGraphNodeInfo(graph, oNode, NULL, &oUnit);
  
  
  
  AudioUnitSetProperty(iUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &absd, sizeof(absd));


  NSArray *eqFrequencies = @[ @32, @64, @125, @250, @500, @1000, @2000, @4000, @8000, @16000 ];
  NSArray *eqBypass = @[@0, @0, @0, @0, @0, @0, @0, @0, @0, @0];
  UInt32 noBands = [eqFrequencies count];
  AudioUnitSetProperty(eqUnit, kAUNBandEQProperty_NumberOfBands, kAudioUnitScope_Global, 0, &noBands, sizeof(noBands));
  
  for (NSUInteger i=0; i<noBands; i++) {
    AudioUnitSetParameter(eqUnit, kAUNBandEQParam_Frequency+i, kAudioUnitScope_Global, 0, (AudioUnitParameterValue)[[eqFrequencies objectAtIndex:i] floatValue], 0);
  }
  
  for (NSUInteger i=0; i<noBands; i++) {
    AudioUnitSetParameter(eqUnit, kAUNBandEQParam_BypassBand+i, kAudioUnitScope_Global, 0, (AudioUnitParameterValue)[[eqBypass objectAtIndex:i] intValue], 0);
  }
  
  AudioUnitInitialize(eqUnit);
  
  AUGraphConnectNodeInput(graph, iNode, 0, eqNode, 0);
  AUGraphConnectNodeInput(graph, eqNode, 0, oNode, 0);
  
  AURenderCallbackStruct inputCallbackStruct;
  inputCallbackStruct.inputProc = renderInput;
  inputCallbackStruct.inputProcRefCon = this;
  AUGraphSetNodeInputCallback(graph, iNode, 0, &inputCallbackStruct);

  AUGraphInitialize(graph);
  AUGraphUpdate(graph, NULL);
  AUGraphStart(graph);
  
  
}



