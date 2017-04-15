
#include <Cocoa/Cocoa.h>
#include "AudioEngine.hpp"
#include "NSSliderExtensions.h"
#include "STPrivilegedTask.h"

@interface AppController : NSObject <NSComboBoxDelegate, NSTextFieldDelegate, NSMenuDelegate>{
  NSStatusItem *mSbItem;
  NSMenu *mMenu;
  AudioEngine *mEngine;
  NSImageView *volumeIconView;
  BOOL darkModeOn;
  NSImage *volumeIcon;
  NSMutableDictionary *eqPresets;
}


@end

AudioObjectPropertyAddress volCurrDef2Address;
AudioObjectPropertyAddress volCurrDef1Address;

Float32 stashedVolume;
Float32 stashedVolume2;
BOOL foundDevice;
AudioDeviceID stashedAudioDeviceID;
AudioDeviceID eqMacDeviceID;
AudioDeviceID outputDeviceID;
struct Device {
  char mName[64];
  AudioDeviceID mID;
};
std::vector<Device> *mDevices;
NSMutableArray *sliders;
Float32 bandArray[10];
NSComboBox *presetsComboBox;
NSTextField *editTextField;
NSButton *saveButton;
NSButton *deleteButton;
NSButton *editButton;
NSUserDefaults *defaults;
NSView *uninstallView;
NSView *view;
NSString *currentPresetName;

