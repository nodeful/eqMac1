#!/bin/sh

cp -R /Applications/eqMac.app/Contents/Resources/ /System/Library/Extensions/
kextload -tv /System/Library/Extensions/eqMacDriver.kext
touch /System/Library/Extensions