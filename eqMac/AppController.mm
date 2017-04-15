#include <iostream>
#include <fstream>
#include <math.h>
#include <vector>
#include <Carbon/Carbon.h>
#include <AudioToolbox/AudioFile.h>
#include <AudioUnit/AudioUnit.h>
#include <QuartzCore/CoreImage.h>
#include "AppController.hpp"
#include "AudioEngine.hpp"


@implementation AppController

#pragma mark - Initialization

- (id)init {
  mDevices = new std::vector<Device>();
  outputDeviceID = 0;
  eqMacDeviceID = 0;
  return self;
}

//Gets initiralized when the application is loaded
- (void)awakeFromNib {
  [[NSApplication sharedApplication] setDelegate:(id)self];
  [self rebuildDeviceList];
  [self scanDeviceList];
  [self restoreSystemOutputDevice];
  
  if(!foundDevice){
    [self doInstall];
    [self rebuildDeviceList];
    [self scanDeviceList];
    [self doReset];
  }
  
  [self initConnections];
  [self initStatusBar];
  [self initEQPresets];
  [self buildMenu];
  [NSApp activateIgnoringOtherApps:YES];

}

- (void)rebuildDeviceList{
  if (mDevices) mDevices->clear();
  UInt32 propsize;
  AudioObjectPropertyAddress theAddress = { kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMaster };
  AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &theAddress, 0, NULL,&propsize);
  int nDevices = propsize / sizeof(AudioDeviceID);
  AudioDeviceID *devids = new AudioDeviceID[nDevices];
  AudioObjectGetPropertyData(kAudioObjectSystemObject, &theAddress, 0, NULL, &propsize, devids);
  for (int i = 0; i < nDevices; ++i) {
    int mInputs = 2;
    AudioDevice dev(devids[i], mInputs);
    Device d;
    d.mID = devids[i];
    propsize = sizeof(d.mName);
    AudioObjectPropertyAddress addr = { kAudioDevicePropertyDeviceName, (dev.mIsInput ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput), 0 };
    AudioObjectGetPropertyData(dev.mID, &addr, 0, NULL,  &propsize, &d.mName);
    mDevices->push_back(d);
  }
  delete[] devids;
}

-(void)initConnections {
  Float32 maxVolume = 1.0;
  Float32 zeroVolume = 0.0;
  UInt32 size = sizeof(stashedAudioDeviceID);
  
  //Get currently selected Audio Device address
  AudioObjectPropertyAddress devCurrDefAddress = { kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMaster };
  
  //Stash current Audio Device ID
  //AudioObjectGetPropertyData(kAudioObjectSystemObject, &devCurrDefAddress, 0, NULL, &size, &mStashedAudioDeviceID);
  //mOutputDeviceID = mStashedAudioDeviceID;
  stashedAudioDeviceID = outputDeviceID;
  //Get default Audio Device Vol1 address
  volCurrDef1Address = { kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, 1 };
  
  //Get default Audio Device actuall Vol1
  size = sizeof(stashedVolume);
  AudioObjectGetPropertyData(stashedAudioDeviceID, &volCurrDef1Address, 0, NULL, &size, &stashedVolume);
  
  //Get default Audio Device Vol2 address
  volCurrDef2Address = { kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, 2 };
  
  //Get default Audio Device actuall Vol2
  size = sizeof(stashedVolume2);
  AudioObjectGetPropertyData(stashedAudioDeviceID, &volCurrDef2Address, 0, NULL, &size, &stashedVolume2);
  
  [self restoreSystemOutputDevice];
  //Initialize Audio Processing Engine
  mEngine = new AudioEngine(eqMacDeviceID, outputDeviceID);
  
  AudioObjectSetPropertyData(outputDeviceID, &volCurrDef1Address, 0, NULL, sizeof(zeroVolume), &zeroVolume);
  AudioObjectSetPropertyData(outputDeviceID, &volCurrDef2Address, 0, NULL, sizeof(zeroVolume), &zeroVolume);
  
  AudioObjectPropertyAddress volSwapWav0Address = { kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, 0 };
  AudioObjectSetPropertyData(eqMacDeviceID, &volSwapWav0Address, 0, NULL, sizeof(maxVolume), &maxVolume);
  
  AudioObjectPropertyAddress volSwapWav1Address = { kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, 1 };
  AudioObjectSetPropertyData(eqMacDeviceID, &volSwapWav1Address, 0, NULL, sizeof(maxVolume), &maxVolume);
  
  AudioObjectPropertyAddress volSwapWav2Address = { kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeOutput, 2 };
  AudioObjectSetPropertyData(eqMacDeviceID, &volSwapWav2Address, 0, NULL, sizeof(maxVolume), &maxVolume);
  mEngine->start();
  
  AudioObjectSetPropertyData(outputDeviceID, &volCurrDef1Address, 0, NULL, sizeof(stashedVolume), &stashedVolume);
  AudioObjectSetPropertyData(outputDeviceID, &volCurrDef2Address, 0, NULL, sizeof(stashedVolume2), &stashedVolume2);
  AudioObjectSetPropertyData(kAudioObjectSystemObject, &devCurrDefAddress, 0, NULL, sizeof(eqMacDeviceID), &eqMacDeviceID);
}

- (void)initStatusBar {
  mSbItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
  NSImage *image = [NSImage imageNamed:@"menuIcon"];
  [image setSize:NSMakeSize(18, 18)];
  [image setTemplate:YES];
  [mSbItem setTitle:@"eqM"];
  //[mSbItem setImage:image];
  NSImage *alternateImage = [NSImage imageNamed:@"menuIcon"];
  [alternateImage setSize:NSMakeSize(18, 18)];
  [alternateImage setTemplate:YES];
 // [mSbItem setAlternateImage:alternateImage];
  [mSbItem setToolTip: @"eqMac"];
  [mSbItem setHighlightMode:YES];
  
}

-(void)initEQPresets{
  defaults = [NSUserDefaults standardUserDefaults];
  eqPresets = [[NSMutableDictionary alloc] init];
  if ([defaults objectForKey:@"eqPresets"]) {
    NSDictionary *newDict = [defaults objectForKey:@"eqPresets"];
    eqPresets = [newDict mutableCopy];
  }else{
    [defaults setObject:[NSNumber numberWithBool:true] forKey:@"FlatPresetFlag"];
    [defaults setObject:eqPresets forKey:@"eqPresets"];
    [defaults synchronize];
  }
  
}

-(void)buildMenu {
    //Menu parameters
  CGFloat menuWidth = 320;
  CGFloat menuHeight = 170;
  NSMenuItem *item = [[NSMenuItem alloc] init];
  
  mMenu = [[NSMenu alloc] initWithTitle:@"eqMac"];
  //NSStatusItem *item = [[NSStatusItem alloc] init];
  
  view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, menuWidth, menuHeight)];
  CGFloat sliderYPos = 40;
  sliders = [[NSMutableArray alloc] initWithCapacity:10];
  CGFloat sliderXPos = 50;
  CGFloat sliderXOrigPos = sliderXPos;
  CGFloat sliderXOffset = 10;
  NSLog(@"%i", [[view window] canBecomeKeyWindow]);
  
  
  //Detect menu bar mode (Dark/Light)
  NSDictionary *dict = [[NSUserDefaults standardUserDefaults] persistentDomainForName:NSGlobalDomain];
  id style = [dict objectForKey:@"AppleInterfaceStyle"];
  darkModeOn = ( style && [style isKindOfClass:[NSString class]] && NSOrderedSame == [style caseInsensitiveCompare:@"dark"] );
  
  //0dB bar
  NSView *barView = [[NSView alloc] initWithFrame:NSMakeRect(sliderXPos+sliderXOffset, sliderYPos+50-0.5, menuWidth-sliderXOrigPos-sliderXOffset-10, 1)];
  [barView setWantsLayer:YES];
  if (darkModeOn) {
    [barView.layer setBackgroundColor:[[NSColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:0.2] CGColor]];
  }else{
    [barView.layer setBackgroundColor:[[NSColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:0.2] CGColor]];
  }
  
  [view addSubview:barView];
  
    //Volume Slider
  NSSlider *volumeSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(10, sliderYPos, 20, 100)];
  [volumeSlider setFloatValue:stashedVolume];
  [volumeSlider setTarget:self];
  [volumeSlider setAction:@selector(changeVolume:)];
  //[[volumeSlider cell] setControlSize:NSSmallControlSize];
  [view addSubview:volumeSlider];
  
    //Frequency Sliders
  for(int i = 0; i<10; i++){
    NSSlider *slider = [[NSSlider alloc] initWithFrame:NSMakeRect(sliderXPos + sliderXOffset, sliderYPos, 20, 100)];
    [slider setFloatValue:0.5];
    [sliders addObject:slider];
    [slider setTarget:self];
    [slider setAction:@selector(changeEQ:)];
    [[slider cell] setControlSize:NSSmallControlSize];
    [view addSubview:slider];
    
    sliderXPos += (menuWidth-sliderXOrigPos-sliderXOffset-3)/10;
  }
  
  
  
  //Volume icon
  if (!darkModeOn) {
    if (stashedVolume == 0) {
      volumeIcon = [NSImage imageNamed:@"volBlack0.png"];
    }else if(stashedVolume>0 && stashedVolume<=0.33){
      volumeIcon = [NSImage imageNamed:@"volBlack1-33.png"];
    }else if(stashedVolume>0.33 && stashedVolume<=0.66){
      volumeIcon = [NSImage imageNamed:@"volBlack33-66.png"];
    }else{
      volumeIcon = [NSImage imageNamed:@"volBlack66-100.png"];
    }
  }else{
    if (stashedVolume == 0) {
      volumeIcon = [NSImage imageNamed:@"volWhite0.png"];
    }else if(stashedVolume>0 && stashedVolume<=0.33){
      volumeIcon = [NSImage imageNamed:@"volWhite1-33.png"];
    }else if(stashedVolume>0.33 && stashedVolume<=0.66){
      volumeIcon = [NSImage imageNamed:@"volWhite33-66.png"];
    }else{
      volumeIcon = [NSImage imageNamed:@"volWhite66-100.png"];
    }
  }
  volumeIconView = [[NSImageView alloc] initWithFrame:NSMakeRect(10, menuHeight-23, 20, 20)];
  [volumeIconView setImageAlignment:NSImageAlignCenter];
  [volumeIconView setImage:volumeIcon];
  [view addSubview:volumeIconView];
  
  //Frequency labels
  sliderXPos = sliderXOrigPos;
  for(int i = 0; i<10; i++){
    NSTextView *frLabel = [[NSTextView alloc] initWithFrame:NSMakeRect(sliderXPos+6, menuHeight-25, 40, 20)];
    [frLabel setBackgroundColor:[NSColor clearColor]];
    [frLabel setAlignment:NSLeftTextAlignment];
    [frLabel setAcceptsTouchEvents:FALSE];
    [frLabel setEditable:FALSE];
    [frLabel setFieldEditor:FALSE];
    [frLabel setSelectable:FALSE];
    if (darkModeOn) {
      [frLabel setTextColor:[NSColor whiteColor]];
    }else{
      [frLabel setTextColor:[NSColor blackColor]];
    }
    switch (i) {
      case 0:
        [frLabel setString:@"32"];
        break;
      case 1:
        [frLabel setString:@"64"];
        break;
      case 2:
        [frLabel setString:@"125"];
        break;
      case 3:
        [frLabel setString:@"250"];
        break;
      case 4:
        [frLabel setString:@"500"];
        break;
      case 5:
        [frLabel setString:@"1K"];
        break;
      case 6:
        [frLabel setString:@"2K"];
        break;
      case 7:
        [frLabel setString:@"4K"];
        break;
      case 8:
        [frLabel setString:@"8K"];
        break;
      case 9:
        [frLabel setString:@"16K"];
        break;
      default:
        break;
    }
    sliderXPos += (menuWidth-sliderXOrigPos-sliderXOffset-3)/10;
    [view addSubview:frLabel];
  }
  
  //Decibel Labels
  //Positive dB
  NSTextView *pDecibelLabel = [[NSTextView alloc] initWithFrame:NSMakeRect(sliderXOrigPos-23, sliderYPos+90, 38, 10)];
  [pDecibelLabel setFont:[NSFont systemFontOfSize:8]];
  if (darkModeOn) {
    [pDecibelLabel setTextColor:[NSColor whiteColor]];
  }else{
    [pDecibelLabel setTextColor:[NSColor blackColor]];
  }
  [pDecibelLabel setString:@"+24dB"];
  [pDecibelLabel setBackgroundColor:[NSColor clearColor]];
  [pDecibelLabel setAcceptsTouchEvents:FALSE];
  [pDecibelLabel setEditable:FALSE];
  [pDecibelLabel setFieldEditor:FALSE];
  [pDecibelLabel setSelectable:FALSE];
  [view addSubview:pDecibelLabel];
  

  //Negative dB
  NSTextView *nDecibelLabel = [[NSTextView alloc] initWithFrame:NSMakeRect(sliderXOrigPos-23, sliderYPos, 38, 10)];
  [nDecibelLabel setFont:[NSFont systemFontOfSize:8]];
  if (darkModeOn) {
    [nDecibelLabel setTextColor:[NSColor whiteColor]];
  }else{
    [nDecibelLabel setTextColor:[NSColor blackColor]];
  }
  [nDecibelLabel setString:@"+24dB"];
  [nDecibelLabel setBackgroundColor:[NSColor clearColor]];
  [nDecibelLabel setAcceptsTouchEvents:FALSE];
  [nDecibelLabel setEditable:FALSE];
  [nDecibelLabel setFieldEditor:FALSE];
  [nDecibelLabel setSelectable:FALSE];
  [view addSubview:nDecibelLabel];
  
  //Quit Button
  NSButton *quitButton = [[NSButton alloc] initWithFrame:NSMakeRect(13, 5, 40, 15)];
  quitButton.title = @"Quit";
  [quitButton setAcceptsTouchEvents:TRUE];
  [quitButton setAction:@selector(doQuit)];
  NSButtonCell *qbCell = [quitButton cell];
  [qbCell setFont:[NSFont systemFontOfSize:15]];
  [qbCell setAlignment:NSLeftTextAlignment];
  [qbCell setBackgroundColor:[NSColor clearColor]];
  [qbCell setBordered:false];
  [view addSubview:quitButton];
  
  //Contribute button
  NSButton *contributeButton = [[NSButton alloc] initWithFrame:NSMakeRect(menuWidth-85, 23, 75, 10)];
  contributeButton.title = @"Contribute";
  [contributeButton setAcceptsTouchEvents:TRUE];
  [contributeButton setAction:@selector(openContributeURL)];
  NSButtonCell *cbCell = [contributeButton cell];
  [cbCell setAlignment:NSRightTextAlignment];
  [cbCell setBackgroundColor:[NSColor clearColor]];
  [cbCell setBordered:false];
  [view addSubview:contributeButton];
  
  //Uninstall button
  NSButton *bitgappButton = [[NSButton alloc] initWithFrame:NSMakeRect(menuWidth-85, 3, 75, 15)];
  bitgappButton.title = @"© Bitgapp";
  [bitgappButton setAcceptsTouchEvents:TRUE];
  [bitgappButton setAction:@selector(doBitgapp)];
  NSButtonCell *ubCell = [bitgappButton cell];
  [ubCell setAlignment:NSRightTextAlignment];
  [ubCell setBackgroundColor:[NSColor clearColor]];
  [ubCell setBordered:false];
  [view addSubview:bitgappButton];
  
  //Reset button
  NSButton *resetButton = [[NSButton alloc] initWithFrame:NSMakeRect(sliderXOrigPos-13, sliderYPos+43, 16, 16)];
  resetButton.title = @"";
  NSImage *resetImage;
  if (darkModeOn) {
    resetImage = [NSImage imageNamed:@"resetButtonWhite.png"];
  }else{
    resetImage = [NSImage imageNamed:@"resetButtonBlack.png"];
  }
  [resetImage setSize:NSMakeSize(16, 16)];
  [resetButton setImage:resetImage];
  [resetButton setImagePosition:NSImageOnly];
  [resetButton setAcceptsTouchEvents:TRUE];
  [resetButton setAction:@selector(doReset)];
  [resetButton setBordered:FALSE];
  [resetButton sizeToFit];
  NSButtonCell *rbCell = [resetButton cell];
  [rbCell setAlignment:NSRightTextAlignment];
  [rbCell setBackgroundColor:[NSColor clearColor]];
  [rbCell setBordered:false];
  [view addSubview:resetButton];
  
  
  //Delete button
  deleteButton = [[NSButton alloc] initWithFrame:NSMakeRect(80, 8, 19, 19)];
  deleteButton.title = @"";
  NSImage *deleteImage;
  if (darkModeOn) {
    deleteImage = [NSImage imageNamed:@"deleteIconWhite.png"];
  }else{
    deleteImage = [NSImage imageNamed:@"deleteIconBlack.png"];
  }
  [deleteImage setSize:NSMakeSize(20, 20)];
  [deleteButton setImage:deleteImage];
  [deleteButton setImagePosition:NSImageOnly];
  [deleteButton setAcceptsTouchEvents:TRUE];
  [deleteButton setAction:@selector(doDelete)];
  [deleteButton setBordered:FALSE];
  [deleteButton sizeToFit];
  [deleteButton setEnabled:FALSE];
  NSButtonCell *dbCell = [deleteButton cell];
  [dbCell setAlignment:NSRightTextAlignment];
  [dbCell setBackgroundColor:[NSColor clearColor]];
  [dbCell setBordered:false];
  [view addSubview:deleteButton];
  
  //Save button
  saveButton = [[NSButton alloc] initWithFrame:NSMakeRect(215, 8, 19, 19)];
  saveButton.title = @"";
  NSImage *saveImage;
  if (darkModeOn) {
    saveImage = [NSImage imageNamed:@"saveIconWhite.png"];
  }else{
    saveImage = [NSImage imageNamed:@"saveIconBlack.png"];
  }
  [saveImage setSize:NSMakeSize(20, 20)];
  [saveButton setImage:saveImage];
  [saveButton setImagePosition:NSImageOnly];
  [saveButton setAcceptsTouchEvents:TRUE];
  [saveButton setAction:@selector(doSave)];
  [saveButton setBordered:FALSE];
  [saveButton sizeToFit];
  [saveButton setEnabled:false];
  [saveButton setHidden:YES];
  NSButtonCell *sbCell = [saveButton cell];
  [sbCell setAlignment:NSRightTextAlignment];
  [sbCell setBackgroundColor:[NSColor clearColor]];
  [sbCell setBordered:false];
  [view addSubview:saveButton];
  
  editButton = [[NSButton alloc] initWithFrame:NSMakeRect(215, 8, 19, 19)];
  editButton.title = @"";
  NSImage *editImage;
  if (darkModeOn) {
    editImage = [NSImage imageNamed:@"editIconWhite.png"];
  }else{
    editImage = [NSImage imageNamed:@"editIconBlack.png"];
  }
  [editImage setSize:NSMakeSize(20, 20)];
  [editButton setImage:editImage];
  [editButton setImagePosition:NSImageOnly];
  [editButton setAcceptsTouchEvents:TRUE];
  [editButton setAction:@selector(doEdit)];
  [editButton setBordered:FALSE];
  [editButton sizeToFit];
  [editButton setEnabled:false];
  [editButton setHidden:YES];
  NSButtonCell *ebCell = [editButton cell];
  [ebCell setAlignment:NSRightTextAlignment];
  [ebCell setBackgroundColor:[NSColor clearColor]];
  [ebCell setBordered:false];
  [view addSubview:editButton];
  
  
  
  //Preset ComboBox

  presetsComboBox = [[NSComboBox alloc] initWithFrame:NSMakeRect(menuWidth/2-50, 5, 100, 25)];
  
  NSArray *presetKeys = [[eqPresets allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
  [presetsComboBox addItemsWithObjectValues:presetKeys];
 // [presetsComboBox setEditable:false];
  [presetsComboBox setDrawsBackground:true];
  [presetsComboBox setAcceptsTouchEvents:YES];
  [presetsComboBox setNumberOfVisibleItems:20];
  if([[defaults objectForKey:@"CustomPresetFlag"] boolValue] == true){
    [presetsComboBox setStringValue:@"Custom"];
    [saveButton setHidden:YES];
    [editButton setHidden:NO];
    [editButton setEnabled:YES];
    NSArray *customPreset = [defaults objectForKey:@"CustomPreset"];
    for(int i = 0; i<10; i++){
      NSNumber *fValue = [customPreset objectAtIndex:i];
      [[sliders objectAtIndex:i] setFloatValue: [fValue floatValue]];
      bandArray[i] = [fValue floatValue];
    }
    mEngine->setEQBands(bandArray);
  }else if ([[defaults objectForKey:@"FlatPresetFlag"] boolValue] == true){
    [presetsComboBox setStringValue:@"Flat"];
  }else{
    [saveButton setHidden:YES];
    [editButton setHidden:NO];
    [editButton setEnabled:YES];
    NSArray *presetValues;
    presetValues = [eqPresets objectForKey:[defaults objectForKey:@"LastPreset"]];
    for(int i = 0; i<10; i++){
      CGFloat newValue =[[presetValues objectAtIndex:i] floatValue];
      [[sliders objectAtIndex:i] setFloatValue:newValue];
      bandArray[i] = [[sliders objectAtIndex:i] floatValue];
    }
    [presetsComboBox setStringValue:[defaults objectForKey:@"LastPreset"]];
    mEngine->setEQBands(bandArray);
    [deleteButton setEnabled:true];
  }
  [presetsComboBox setDelegate:self];
  [view addSubview:presetsComboBox];
  [presetsComboBox setEditable:false];

  
  [item setView:view];
  [mMenu addItem:item];
  [mMenu setDelegate:self];
  [mSbItem setMenu:mMenu];
  
}


-(OSStatus)restoreSystemOutputDevice {
  OSStatus err = noErr;
  AudioObjectPropertyAddress devAddress = { kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMaster };
  err = AudioObjectSetPropertyData(kAudioObjectSystemObject, &devAddress, 0, NULL, sizeof(stashedAudioDeviceID), &stashedAudioDeviceID);
  return err;
}

- (void)cleanupOnBeforeQuit {
  if(mEngine) mEngine->stop();
  [self restoreSystemOutputDevice];
}

-(void)scanDeviceList{
  foundDevice = false;
  for (std::vector<Device>::iterator i = mDevices->begin(); i != mDevices->end(); ++i) {
    NSLog(@"%s\n",(*i).mName);
    if (0 == strcmp("eqMac", (*i).mName)){
      eqMacDeviceID = (*i).mID;
      foundDevice = true;
      NSLog(@"Found eqMac Device\n");
    }else if (0 == strcmp("Built-in Output", (*i).mName)){
      outputDeviceID = (*i).mID;
      NSLog(@"Found default Device\n");
    }
  }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
  [self cleanupOnBeforeQuit];
}

#pragma mark - Button actions

-(void)openContributeURL{
  [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.bitgapp.com/eqmac/contribute/"]];
}

-(void)doBitgapp{
  [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://www.bitgapp.com/"]];
}

-(void)doSave{
  NSLog(@"Saving");
  if ([currentPresetName isEqualToString:[presetsComboBox stringValue]]) {
    [saveButton setEnabled:false];
    [saveButton setHidden:true];
    [editButton setHidden:false];
    [editButton setEnabled:true];
    [deleteButton setEnabled:true];
    return;
  }
  [presetsComboBox addItemWithObjectValue:[NSString stringWithFormat:@"%@", [presetsComboBox stringValue]]];
  NSMutableArray *newPreset = [[NSMutableArray alloc] init];
  for(int i = 0; i<10; i++){
    NSNumber *sliderValue = [NSNumber numberWithFloat:[[sliders objectAtIndex:i] floatValue]];
    [newPreset addObject:sliderValue];
  }
  [eqPresets setObject:newPreset forKey:[presetsComboBox stringValue]];
  [defaults setObject:eqPresets forKey:@"eqPresets"];
  [defaults synchronize];
  [saveButton setEnabled:false];
  [saveButton setHidden:true];
  [editButton setHidden:false];
  [editButton setEnabled:true];
  [deleteButton setEnabled:true];
  [[presetsComboBox window] makeFirstResponder:nil];
  [presetsComboBox setEditable:false];
}

-(void)doEdit{
  
  [deleteButton setEnabled:NO];
  [editButton setHidden:YES];
  [saveButton setHidden:NO];
  [saveButton setEnabled:false];
  if(![presetsComboBox.stringValue isEqualToString:@"Custom"])[saveButton setEnabled:TRUE];
  [presetsComboBox setEditable:true];
  [presetsComboBox becomeFirstResponder];
  
  
  
  
}


-(void)doDelete{
  if([eqPresets objectForKey:[presetsComboBox stringValue]]){
    [eqPresets removeObjectForKey:[presetsComboBox stringValue]];
    [defaults setObject:eqPresets forKey:@"eqPresets"];
    [defaults synchronize];
    
    
    for(int i = 0; i<10; i++){
      [[[sliders objectAtIndex:i] animator] setFloatValue:0.5];
      bandArray[i] = 0.5;
    }
    mEngine->setEQBands(bandArray);
    [presetsComboBox setStringValue:@"Flat"];
    [presetsComboBox setEditable:false];
    [[presetsComboBox window] makeFirstResponder:nil];
    [saveButton setEnabled:false];
    [saveButton setHidden:YES];
    [editButton setHidden:NO];
    [editButton setEnabled:NO];
    [deleteButton setEnabled:false];
    
    [presetsComboBox removeItemAtIndex:[presetsComboBox indexOfSelectedItem]];
    
  }
}

-(void)doReset{
  [self cleanupOnBeforeQuit];
  [self rebuildDeviceList];
  [self scanDeviceList];
  [self initConnections];
  
  for(int i = 0; i<10; i++){
    [[[sliders objectAtIndex:i] animator] setFloatValue:0.5];
    bandArray[i] = 0.5;
  }
  mEngine->setEQBands(bandArray);
  [presetsComboBox setStringValue:@"Flat"];
  [presetsComboBox setEditable:false];
  [[presetsComboBox window] makeFirstResponder:nil];
  [saveButton setEnabled:false];
  [saveButton setHidden:YES];
  [editButton setHidden:NO];
  [editButton setEnabled:NO];
  [deleteButton setEnabled:false];
  
}

-(void)doInstall{
  
  NSString *resourcePath = [[NSBundle bundleForClass:[self class]] resourcePath];
  NSString *scriptName = @"install_script";
  NSString *scriptExtension = @"sh";
  NSString *scriptAbsolutePath = [NSString stringWithFormat:@"%@/%@.%@", resourcePath, scriptName, scriptExtension];

  STPrivilegedTask *task = [[STPrivilegedTask alloc] init];

  NSArray *argv = [NSArray arrayWithObjects:nil];
  [task setLaunchPath:scriptAbsolutePath];
  [task setArguments:argv];
  [task launch];
  [task waitUntilExit];
}


- (void)doQuit {
  if([[presetsComboBox stringValue] isEqualToString:@"Custom"]){
    NSMutableArray *customPreset = [[NSMutableArray alloc] init];
    for(int i = 0; i<10; i++){
      NSNumber *sliderValue = [NSNumber numberWithFloat:[[sliders objectAtIndex:i] floatValue]];
      [customPreset addObject:sliderValue];
    }
    [defaults setObject:customPreset forKey:@"CustomPreset"];
    [defaults setObject:[NSNumber numberWithBool:true] forKey:@"CustomPresetFlag"];
    [defaults setObject:[NSNumber numberWithBool:false] forKey:@"FlatPresetFlag"];
    [defaults setObject:[NSString stringWithFormat:@""] forKey:@"LastPreset"];
    
  }else if([[presetsComboBox stringValue] isEqualToString:@"Flat"]){
    [defaults setObject:[NSNumber numberWithBool:false] forKey:@"CustomPresetFlag"];
    [defaults setObject:[NSNumber numberWithBool:true] forKey:@"FlatPresetFlag"];
    [defaults setObject:[NSString stringWithFormat:@""] forKey:@"LastPreset"];
    
  }else{
    [defaults setObject:[NSNumber numberWithBool:false] forKey:@"CustomPresetFlag"];
    [defaults setObject:[NSNumber numberWithBool:false] forKey:@"FlatPresetFlag"];
    if ([eqPresets objectForKey:[presetsComboBox stringValue]]) {
      [defaults setObject:[NSString stringWithFormat:@"%@", [presetsComboBox stringValue]] forKey:@"LastPreset"];
    }else{
      [defaults setObject:[NSString stringWithFormat:@""] forKey:@"LastPreset"];
      NSMutableArray *customPreset = [[NSMutableArray alloc] init];
      for(int i = 0; i<10; i++){
        NSNumber *sliderValue = [NSNumber numberWithFloat:[[sliders objectAtIndex:i] floatValue]];
        [customPreset addObject:sliderValue];
      }
      [eqPresets setObject:customPreset forKey:@"CustomPreset"];
      [defaults setObject:[NSNumber numberWithBool:true] forKey:@"CustomPresetFlag"];
    }
    
  }
  [defaults synchronize];
  [self cleanupOnBeforeQuit];
  [NSApp terminate:nil];
}





#pragma mark - Events

-(void)comboBoxSelectionDidChange:(NSNotification *)notification{
  [[presetsComboBox window] makeFirstResponder:nil];
  NSComboBox *cb = [notification object];
  NSString *selectedPreset = [cb itemObjectValueAtIndex:[cb indexOfSelectedItem]];
  NSArray *presetValues;
  if ([eqPresets objectForKey:selectedPreset]) {
    presetValues = [eqPresets objectForKey:selectedPreset];
    for(int i = 0; i<10; i++){
      CGFloat newValue = [[presetValues objectAtIndex:i] floatValue];
      [[[sliders objectAtIndex:i] animator] setFloatValue:newValue];
    }
    double delayInSeconds = 1.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
      for(int i = 0; i<10; i++){
        bandArray[i] = [[sliders objectAtIndex:i] floatValue];
      }
      mEngine->setEQBands(bandArray);
    });
    [deleteButton setEnabled:true];
  }else{
    [saveButton setEnabled:false];
    [deleteButton setEnabled:false];
  }
}

-(void)controlTextDidChange:(NSNotification *)notification{
  if ([[presetsComboBox stringValue] isEqualToString:@"Custom"] || [[presetsComboBox stringValue] isEqualToString:@"Flat"] || [[presetsComboBox stringValue] isEqual:@""]) {
    [saveButton setEnabled:false];
  }else{
    [saveButton setEnabled:true];
  }
}

-(IBAction)changeVolume:(id)sender{
  NSSlider *slider = sender;
  stashedVolume = [slider floatValue];
  stashedVolume2 = [slider floatValue];
  AudioObjectSetPropertyData(outputDeviceID, &volCurrDef1Address, 0, NULL, sizeof(stashedVolume), &stashedVolume);
  AudioObjectSetPropertyData(outputDeviceID, &volCurrDef2Address, 0, NULL, sizeof(stashedVolume2), &stashedVolume2);
  
  if (!darkModeOn) {
    if (stashedVolume == 0) {
      volumeIcon = [NSImage imageNamed:@"volBlack0.png"];
    }else if(stashedVolume>0 && stashedVolume<=0.33){
      volumeIcon = [NSImage imageNamed:@"volBlack1-33.png"];
    }else if(stashedVolume>0.33 && stashedVolume<=0.66){
      volumeIcon = [NSImage imageNamed:@"volBlack33-66.png"];
    }else{
      volumeIcon = [NSImage imageNamed:@"volBlack66-100.png"];
    }
  }else{
    if (stashedVolume == 0) {
      volumeIcon = [NSImage imageNamed:@"volWhite0.png"];
    }else if(stashedVolume>0 && stashedVolume<=0.33){
      volumeIcon = [NSImage imageNamed:@"volWhite1-33.png"];
    }else if(stashedVolume>0.33 && stashedVolume<=0.66){
      volumeIcon = [NSImage imageNamed:@"volWhite33-66.png"];
    }else{
      volumeIcon = [NSImage imageNamed:@"volWhite66-100.png"];
    }
  }
  
  [volumeIconView setImage:volumeIcon];
}

-(IBAction)changeEQ:(id)sender{
  for(int i = 0; i<10; i++){
    bandArray[i] = [[sliders objectAtIndex:i] floatValue];
  }
  [presetsComboBox setStringValue:@"Custom"];
  [presetsComboBox setEditable:false];
  [[presetsComboBox window] makeFirstResponder:nil];
  [editButton setHidden:NO];
  [editButton setEnabled:YES];
  mEngine->setEQBands(bandArray);
}

@end
