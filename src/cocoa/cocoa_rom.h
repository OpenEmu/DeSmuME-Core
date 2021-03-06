/*
	Copyright (C) 2011 Roger Manuel
	Copyright (C) 2011-2013 DeSmuME team

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

#import <Cocoa/Cocoa.h>
#include <libkern/OSAtomic.h>


#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_5
@interface CocoaDSRom : NSObject <NSXMLParserDelegate>
#else
@interface CocoaDSRom : NSObject
#endif
{	
	NSMutableDictionary *header;
	NSMutableDictionary *bindings;
	NSURL *fileURL;
	NSInteger saveType;
	
	NSMutableDictionary *xmlCurrentRom;
	NSMutableArray *xmlElementStack;
	NSMutableArray *xmlCharacterStack;
}

@property (readonly, strong) NSMutableDictionary *header;
@property (readonly, strong) NSMutableDictionary *bindings;
@property (readonly, strong) NSURL *fileURL;
@property (assign) BOOL willStreamLoadData;
@property (readonly) BOOL isDataLoaded;
@property (assign) NSInteger saveType;

- (id) initWithURL:(NSURL *)theURL;
- (id) initWithURL:(NSURL *)theURL saveType:(NSInteger)saveTypeID;
- (id) initWithURL:(NSURL *)theURL saveType:(NSInteger)saveTypeID streamLoadData:(BOOL)willStreamLoad;
- (void) initHeader;
- (BOOL) loadData:(NSURL *)theURL;
- (void) loadDataOnThread:(id)object;
@property (readonly, copy) NSString *title;
@property (readonly, copy) NSString *code;
- (NSString *) banner:(const UInt16 *)UTF16TextBuffer;
@property (readonly, copy) NSString *internalName;
@property (readonly, copy) NSString *serial;
@property (readonly, copy) NSString *developerName;
@property (readonly, copy) NSString *developerNameAndCode;
- (NSString *) unitCodeStringUsingID:(NSInteger)unitCodeID;
- (NSImage *) icon;
- (void) handleAdvansceneDatabaseInfo;

+ (void) changeRomSaveType:(NSInteger)saveTypeID;
+ (NSInteger) saveTypeByString:(NSString *)saveTypeString;
+ (NSMutableDictionary *) romNotLoadedBindings;
+ (NSString *) byteSizeStringWithLargerUnit:(NSUInteger)byteSize;

@end

#ifdef __cplusplus
extern "C"
{
#endif

void RomIconToRGBA8888(uint32_t *bitmapData);

#ifdef __cplusplus
}
#endif
