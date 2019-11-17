/*
	Copyright (C) 2012-2015 DeSmuME team

	This file is free software: you can redistribute it and/or modify
	it under the terms of the GNU General Public License as published by
	the Free Software Foundation, either version 2 of the License, or
	(at your option) any later version.

	This file is distributed in the hope that it will be useful,
	but WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
	GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with the this software.  If not, see <http://www.gnu.org/licenses/>.
 */

#import "NDSGameCore.h"
#import "cocoa_cheat.h"
#import "cocoa_globals.h"
#import "cocoa_file.h"
#import "cocoa_firmware.h"
#import "cocoa_GPU.h"
#import "cocoa_input.h"
#import "OESoundInterface.h"
#import "OENDSSystemResponderClient.h"

#include <OpenGL/gl.h>
#include "../../NDSSystem.h"
#include "../../GPU.h"
#undef BOOL

#define OptionDefault(_NAME_, _PREFKEY_) @{ OEGameCoreDisplayModeNameKey : _NAME_, OEGameCoreDisplayModePrefKeyNameKey : _PREFKEY_, OEGameCoreDisplayModeStateKey : @YES, }
#define Option(_NAME_, _PREFKEY_) @{ OEGameCoreDisplayModeNameKey : _NAME_, OEGameCoreDisplayModePrefKeyNameKey : _PREFKEY_, OEGameCoreDisplayModeStateKey : @NO, }
#define OptionIndented(_NAME_, _PREFKEY_) @{ OEGameCoreDisplayModeNameKey : _NAME_, OEGameCoreDisplayModePrefKeyNameKey : _PREFKEY_, OEGameCoreDisplayModeStateKey : @NO, OEGameCoreDisplayModeIndentationLevelKey : @(1), }
#define OptionToggleable(_NAME_, _PREFKEY_) @{ OEGameCoreDisplayModeNameKey : _NAME_, OEGameCoreDisplayModePrefKeyNameKey : _PREFKEY_, OEGameCoreDisplayModeStateKey : @NO, OEGameCoreDisplayModeAllowsToggleKey : @YES, }
#define OptionToggleableNoSave(_NAME_, _PREFKEY_) @{ OEGameCoreDisplayModeNameKey : _NAME_, OEGameCoreDisplayModePrefKeyNameKey : _PREFKEY_, OEGameCoreDisplayModeStateKey : @NO, OEGameCoreDisplayModeAllowsToggleKey : @YES, OEGameCoreDisplayModeDisallowPrefSaveKey : @YES, }
#define Label(_NAME_) @{ OEGameCoreDisplayModeLabelKey : _NAME_, }
#define SeparatorItem() @{ OEGameCoreDisplayModeSeparatorItemKey : @"",}

volatile bool execute = true;

@implementation NDSGameCore

@synthesize cdsController;
@synthesize cdsGPU;
@synthesize cdsFirmware;
@synthesize cdsCheats;
@dynamic displayMode;

- (id)init
{
	self = [super init];
	if(self == nil)
	{
		return self;
	}
	
	// Set up threading locks
	spinlockDisplayMode = OS_SPINLOCK_INIT;
	pthread_rwlock_init(&rwlockCoreExecute, NULL);
	
	// Set up input handling
	touchLocation.x = 0;
	touchLocation.y = 0;
	
	inputID[OENDSButtonUp]			= DSControllerState_Up;
	inputID[OENDSButtonDown]		= DSControllerState_Down;
	inputID[OENDSButtonLeft]		= DSControllerState_Left;
	inputID[OENDSButtonRight]		= DSControllerState_Right;
	inputID[OENDSButtonA]			= DSControllerState_A;
	inputID[OENDSButtonB]			= DSControllerState_B;
	inputID[OENDSButtonX]			= DSControllerState_X;
	inputID[OENDSButtonY]			= DSControllerState_Y;
	inputID[OENDSButtonL]			= DSControllerState_L;
	inputID[OENDSButtonR]			= DSControllerState_R;
	inputID[OENDSButtonStart]		= DSControllerState_Start;
	inputID[OENDSButtonSelect]		= DSControllerState_Select;
	inputID[OENDSButtonMicrophone]	= DSControllerState_Microphone;
	inputID[OENDSButtonLid]			= DSControllerState_Lid;
	inputID[OENDSButtonDebug]		= DSControllerState_Debug;
	
	// Set up the DS controller
	cdsController = [[CocoaDSController alloc] init];
	[cdsController setMicMode:MICMODE_INTERNAL_NOISE];
	
	// Set up the DS GPU
	cdsGPU = [[CocoaDSGPU alloc] init];
	[cdsGPU setRwlockProducer:&rwlockCoreExecute];
	[cdsGPU setRender3DThreads:0]; // Pass 0 to automatically set the number of rendering threads
	[cdsGPU setRender3DRenderingEngine:CORE3DLIST_SWRASTERIZE];
	
	// Set up the emulation core
	CommonSettings.advanced_timing = true;
	CommonSettings.jit_max_block_size = 12;
	CommonSettings.use_jit = true;
	NDS_Init();
	
	// Set up the cheat system
	cdsCheats = [[CocoaDSCheatManager alloc] init];
	[cdsCheats setRwlockCoreExecute:&rwlockCoreExecute];
	addedCheatsDict = [[NSMutableDictionary alloc] initWithCapacity:128];
	
	// Set up the DS firmware using the internal firmware
	cdsFirmware = [[CocoaDSFirmware alloc] init];
	[cdsFirmware update];
	
	// Set up the sound core
	CommonSettings.spu_advanced = true;
	CommonSettings.spuInterpolationMode = SPUInterpolation_Cosine;
	CommonSettings.SPU_sync_mode = SPU_SYNC_MODE_SYNCHRONOUS;
	CommonSettings.SPU_sync_method = SPU_SYNC_METHOD_N;
	openEmuSoundInterfaceBuffer = [self ringBufferAtIndex:0];
	
	NSInteger result = SPU_ChangeSoundCore(SNDCORE_OPENEMU, (int)SPU_BUFFER_BYTES);
	if(result == -1)
	{
		SPU_ChangeSoundCore(SNDCORE_DUMMY, 0);
	}
	
	SPU_SetSynchMode(CommonSettings.SPU_sync_mode, CommonSettings.SPU_sync_method);
	SPU_SetVolume(100);
	
	// Set up the DS display
	displayMode = DS_DISPLAY_TYPE_DUAL;
	displayRect = OEIntRectMake(0, 0, GPU_DISPLAY_WIDTH, GPU_DISPLAY_HEIGHT * 2);
	displayAspectRatio = OEIntSizeMake(2, 3);
	
	return self;
}

- (void)dealloc
{
	SPU_ChangeSoundCore(SNDCORE_DUMMY, 0);
	NDS_DeInit();

	pthread_rwlock_destroy(&rwlockCoreExecute);
}

- (NSInteger) displayMode
{
	OSSpinLockLock(&spinlockDisplayMode);
	NSInteger theMode = displayMode;
	OSSpinLockUnlock(&spinlockDisplayMode);
	
	return theMode;
}

- (void) setDisplayMode:(NSInteger)theMode
{
	OEIntRect newDisplayRect;
	OEIntSize newDisplayAspectRatio;
	
	switch (theMode)
	{
		case DS_DISPLAY_TYPE_MAIN:
			newDisplayRect = OEIntRectMake(0, 0, GPU_DISPLAY_WIDTH, GPU_DISPLAY_HEIGHT);
			newDisplayAspectRatio = OEIntSizeMake(4, 3);
			break;
			
		case DS_DISPLAY_TYPE_TOUCH:
			newDisplayRect = OEIntRectMake(0, GPU_DISPLAY_HEIGHT, GPU_DISPLAY_WIDTH, GPU_DISPLAY_HEIGHT);
			newDisplayAspectRatio = OEIntSizeMake(4, 3);
			break;
			
		case DS_DISPLAY_TYPE_DUAL:
			newDisplayRect = OEIntRectMake(0, 0, GPU_DISPLAY_WIDTH, GPU_DISPLAY_HEIGHT * 2);
			newDisplayAspectRatio = OEIntSizeMake(2, 3);
			break;
			
		default:
			return;
			break;
	}
	
	OSSpinLockLock(&spinlockDisplayMode);
	displayMode = theMode;
	displayRect = newDisplayRect;
	displayAspectRatio = newDisplayAspectRatio;
	OSSpinLockUnlock(&spinlockDisplayMode);
}

#pragma mark -

#pragma mark Execution

- (void)resetEmulation
{
	pthread_rwlock_wrlock(&rwlockCoreExecute);
	NDS_Reset();
	pthread_rwlock_unlock(&rwlockCoreExecute);
	execute = true;
}

- (void)executeFrame
{
	[cdsController flush];
	
	NDS_beginProcessingInput();
	NDS_endProcessingInput();
	
	pthread_rwlock_wrlock(&rwlockCoreExecute);
	NDS_exec<false>();
	pthread_rwlock_unlock(&rwlockCoreExecute);
	
	SPU_Emulate_user();
}

- (BOOL)loadFileAtPath:(NSString *)path error:(NSError **)error
{
	BOOL isRomLoaded = NO;
	NSString *openEmuDataPath = [self batterySavesDirectoryPath];
	NSURL *openEmuDataURL = [NSURL fileURLWithPath:openEmuDataPath];
	
	[CocoaDSFile addURLToURLDictionary:openEmuDataURL groupKey:@PATH_OPEN_EMU fileKind:@"ROM"];
	[CocoaDSFile addURLToURLDictionary:openEmuDataURL groupKey:@PATH_OPEN_EMU fileKind:@"ROM Save"];
	[CocoaDSFile addURLToURLDictionary:openEmuDataURL groupKey:@PATH_OPEN_EMU fileKind:@"Save State"];
	[CocoaDSFile addURLToURLDictionary:openEmuDataURL groupKey:@PATH_OPEN_EMU fileKind:@"Screenshot"];
	[CocoaDSFile addURLToURLDictionary:openEmuDataURL groupKey:@PATH_OPEN_EMU fileKind:@"Video"];
	[CocoaDSFile addURLToURLDictionary:openEmuDataURL groupKey:@PATH_OPEN_EMU fileKind:@"Cheat"];
	[CocoaDSFile addURLToURLDictionary:openEmuDataURL groupKey:@PATH_OPEN_EMU fileKind:@"Sound Sample"];
	[CocoaDSFile addURLToURLDictionary:openEmuDataURL groupKey:@PATH_OPEN_EMU fileKind:@"Firmware Configuration"];
	[CocoaDSFile addURLToURLDictionary:openEmuDataURL groupKey:@PATH_OPEN_EMU fileKind:@"Lua Script"];
	
	[CocoaDSFile setupAllFilePathsWithURLDictionary:@PATH_OPEN_EMU];
	
	// Ensure that the OpenEmu data directory exists before loading the ROM.
	NSFileManager *fileManager = [[NSFileManager alloc] init];
	[fileManager createDirectoryAtPath:openEmuDataPath withIntermediateDirectories:YES attributes:nil error:NULL];

	isRomLoaded = [CocoaDSFile loadRom:[NSURL fileURLWithPath:path]];
	
	[CocoaDSCheatManager setMasterCheatList:cdsCheats];

	// Only temporary, so core doesn't crash on an older OpenEmu version
	if ([self respondsToSelector:@selector(displayModeInfo)]) {
		[self loadDisplayModeOptions];
	}
	
	return isRomLoaded;
}

#pragma mark Video

- (BOOL)rendersToOpenGL
{
	return NO;
}

- (OEIntRect)screenRect
{
	OSSpinLockLock(&spinlockDisplayMode);
	OEIntRect theRect = displayRect;
	OSSpinLockUnlock(&spinlockDisplayMode);
	
	return theRect;
}

- (OEIntSize)aspectSize
{
	OSSpinLockLock(&spinlockDisplayMode);
	OEIntSize theAspectRatio = displayAspectRatio;
	OSSpinLockUnlock(&spinlockDisplayMode);
	
	return theAspectRatio;
}

- (OEIntSize)bufferSize
{
	return OEIntSizeMake(GPU_DISPLAY_WIDTH, GPU_DISPLAY_HEIGHT * 2);
}

- (const void *)getVideoBufferWithHint:(void *)hint
{
	// TODO
	//_gpuFrame.buffer = (uint16_t *)hint;
	//return hint;
	return GPU_screen;
}

- (GLenum)pixelFormat
{
	return GL_RGBA;
}

- (GLenum)pixelType
{
	return GL_UNSIGNED_SHORT_1_5_5_5_REV;
}

- (GLenum)internalPixelFormat
{
	return GL_RGB5_A1;
}

- (NSTimeInterval)frameInterval
{
	return DS_FRAMES_PER_SECOND;
}

#pragma mark Audio

- (NSUInteger)audioBufferCount
{
	return 1;
}

- (NSUInteger)channelCount
{
	return SPU_NUMBER_CHANNELS;
}

- (double)audioSampleRate
{
	return SPU_SAMPLE_RATE;
}

- (NSUInteger)audioBitDepth
{
	return SPU_SAMPLE_RESOLUTION;
}

- (NSUInteger)channelCountForBuffer:(NSUInteger)buffer
{
	return [self channelCount];
}

- (NSUInteger)audioBufferSizeForBuffer:(NSUInteger)buffer
{
	return (NSUInteger)SPU_BUFFER_BYTES;
}

- (double)audioSampleRateForBuffer:(NSUInteger)buffer
{
	return [self audioSampleRate];
}

#pragma mark Input

- (oneway void)didPushNDSButton:(OENDSButton)button forPlayer:(NSUInteger)player
{
	[cdsController setControllerState:YES controlID:inputID[button]];
}

- (oneway void)didReleaseNDSButton:(OENDSButton)button forPlayer:(NSUInteger)player
{
	[cdsController setControllerState:NO controlID:inputID[button]];
}

- (oneway void)didTouchScreenPoint:(OEIntPoint)aPoint
{
	BOOL isTouchPressed = NO;
	NSInteger dispMode = [self displayMode];
	
	switch (dispMode)
	{
		case DS_DISPLAY_TYPE_MAIN:
			isTouchPressed = NO; // Reject touch input if showing only the main screen.
			break;
			
		case DS_DISPLAY_TYPE_TOUCH:
			isTouchPressed = YES;
			break;
			
		case DS_DISPLAY_TYPE_DUAL:
			isTouchPressed = YES;
			aPoint.y -= GPU_DISPLAY_HEIGHT; // Normalize the y-coordinate to the DS.
			break;
			
		default:
			return;
			break;
	}
	
	// Constrain the touch point to the DS dimensions.
	if (aPoint.x < 0)
	{
		aPoint.x = 0;
	}
	else if (aPoint.x > (GPU_DISPLAY_WIDTH - 1))
	{
		aPoint.x = (GPU_DISPLAY_WIDTH - 1);
	}
	
	if (aPoint.y < 0)
	{
		aPoint.y = 0;
	}
	else if (aPoint.y > (GPU_DISPLAY_HEIGHT - 1))
	{
		aPoint.y = (GPU_DISPLAY_HEIGHT - 1);
	}
	
	touchLocation = NSMakePoint(aPoint.x, aPoint.y);
	[cdsController setTouchState:isTouchPressed location:touchLocation];
}

- (oneway void)didReleaseTouch
{
	[cdsController setTouchState:NO location:touchLocation];
}

- (NSTrackingAreaOptions)mouseTrackingOptions
{
	return 0;
}

- (void)settingWasSet:(id)aValue forKey:(NSString *)keyName
{
	DLog(@"keyName = %@", keyName);
	//[self doesNotImplementSelector:_cmd];
}

#pragma mark Save State

- (void)saveStateToFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
	// TODO: error handling
	block([CocoaDSFile saveState:[NSURL fileURLWithPath:fileName]], nil);
}

- (void)loadStateFromFileAtPath:(NSString *)fileName completionHandler:(void (^)(BOOL, NSError *))block
{
	// TODO: error handling
	block([CocoaDSFile loadState:[NSURL fileURLWithPath:fileName]], nil);
}

#pragma mark - Display Mode

- (NSArray <NSDictionary <NSString *, id> *> *)displayModes
{
	if (_availableDisplayModes.count == 0)
	{
		_availableDisplayModes = [NSMutableArray array];

		NSArray <NSDictionary <NSString *, id> *> *availableModesWithDefault =
		@[
		  Label(@"Screen"),
		  OptionDefault(@"Dual", @"screen"),
		  Option(@"Main", @"screen"),
		  Option(@"Touch", @"screen"),
		  ];

		// Deep mutable copy
		_availableDisplayModes = (NSMutableArray *)CFBridgingRelease(CFPropertyListCreateDeepCopy(kCFAllocatorDefault, (CFArrayRef)availableModesWithDefault, kCFPropertyListMutableContainers));
	}

	return [_availableDisplayModes copy];
}

- (void)changeDisplayWithMode:(NSString *)currentDisplayMode
{
	if (_availableDisplayModes.count == 0)
		[self displayModes];

	// First check if 'displayMode' is valid
	BOOL isValidDisplayMode = NO;

	for (NSDictionary *modeDict in _availableDisplayModes) {
		if ([modeDict[OEGameCoreDisplayModeNameKey] isEqualToString:currentDisplayMode]) {
			isValidDisplayMode = YES;
			break;
		}
	}

	// Disallow a 'displayMode' not found in _availableDisplayModes
	if (!isValidDisplayMode)
		return;

	// Handle option state changes
	for (NSMutableDictionary *optionDict in _availableDisplayModes) {
		if (!optionDict[OEGameCoreDisplayModeNameKey])
			continue;
		// Mutually exclusive option state change
		else if ([optionDict[OEGameCoreDisplayModeNameKey] isEqualToString:currentDisplayMode])
			optionDict[OEGameCoreDisplayModeStateKey] = @YES;
		// Reset
		else
			optionDict[OEGameCoreDisplayModeStateKey] = @NO;
	}

	if ([currentDisplayMode isEqualToString:@"Dual"])
		[self setDisplayMode:DS_DISPLAY_TYPE_DUAL];
	else if ([currentDisplayMode isEqualToString:@"Main"])
		[self setDisplayMode:DS_DISPLAY_TYPE_MAIN];
	else if ([currentDisplayMode isEqualToString:@"Touch"])
		[self setDisplayMode:DS_DISPLAY_TYPE_TOUCH];
}

- (void)loadDisplayModeOptions
{
	// Restore screen
	NSString *lastScreen = self.displayModeInfo[@"screen"];
	if (lastScreen && ![lastScreen isEqualToString:@"Dual"]) {
		[self changeDisplayWithMode:lastScreen];
	}
}

#pragma mark Miscellaneous

- (void)setCheat:(NSString *)code setType:(NSString *)type setEnabled:(BOOL)enabled
{
	// This method can be used for both adding a new cheat or setting the enable
	// state on an existing cheat, so be sure to account for both cases.
	
	// First check if the cheat exists.
	CocoaDSCheatItem *cheatItem = (CocoaDSCheatItem *)[addedCheatsDict objectForKey:code];
	
	if (cheatItem == nil)
	{
		// If the cheat doesn't already exist, then create a new one and add it.
		cheatItem = [[CocoaDSCheatItem alloc] init];
		[cheatItem setCheatType:CHEAT_TYPE_ACTION_REPLAY]; // Default to Action Replay for now
		[cheatItem setFreezeType:0];
		[cheatItem setDescription:@""]; // OpenEmu takes care of this
		[cheatItem setCode:code];
		[cheatItem setMemAddress:0x00000000]; // UNUSED
		[cheatItem setBytes:1]; // UNUSED
		[cheatItem setValue:0]; // UNUSED
		
		[cheatItem setEnabled:enabled];
		[[self cdsCheats] add:cheatItem];
		
		// OpenEmu doesn't currently save cheats per game, so assume that the
		// cheat list is short and that code strings are unique. This allows
		// us to get away with simply saving the cheat code string and hashing
		// for it later.
		[addedCheatsDict setObject:cheatItem forKey:code];
	}
	else
	{
		// If the cheat does exist, then just set its enable state.
		[cheatItem setEnabled:enabled];
		[[self cdsCheats] update:cheatItem];
	}
}

@end
