////////////////////////////////////////////////////////////////////////////////
//
// B L I N K
//
// Copyright (C) 2016-2018 Blink Mobile Shell Project
//
// This file is part of Blink.
//
// Blink is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Blink is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Blink. If not, see <http://www.gnu.org/licenses/>.
//
// In addition, Blink is also subject to certain additional terms under
// GNU GPL version 3 section 7.
//
// You should have received a copy of these additional terms immediately
// following the terms and conditions of the GNU General Public License
// which accompanied the Blink Source Code. If not, see
// <http://www.github.com/blinksh/blink>.
//
////////////////////////////////////////////////////////////////////////////////

#import "BlinkPaths.h"
#import "XCConfig.h"

@implementation BlinkPaths

NSString *__homePath = nil;
NSString *__documentsPath = nil;
NSString *__groupContainerPath = nil;
NSString *__iCloudsDriveDocumentsPath = nil;

+ (NSString *)homePath {
  if (__homePath == nil) {
    __homePath = [[self groupContainerPath] stringByAppendingPathComponent:@"home"];
  }

  return __homePath;
}

+ (NSURL *)homeURL
{
  return [NSURL fileURLWithPath:[self homePath]];
}

+ (NSString *)documentsPath
{
  if (__documentsPath == nil) {
    __documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    // Linked and resolved files has prefix /private
    if (![__documentsPath hasPrefix:@"/private"]) {
      __documentsPath = [@"/private" stringByAppendingString:__documentsPath];
    }
  }
  return __documentsPath;
}

+ (NSString *)groupContainerPath {
  if (__groupContainerPath == nil) {

    NSString *groupID = [XCConfig infoPlistFullGroupID];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = [fm containerURLForSecurityApplicationGroupIdentifier:groupID].path;
    __groupContainerPath = path;
  }
  return __groupContainerPath;
}

+ (NSString *)iCloudDriveDocuments
{
  if (__iCloudsDriveDocumentsPath == nil) {
    NSString *iCloudID = [XCConfig infoPlistFullCloudID];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *path = [[fm URLForUbiquityContainerIdentifier:iCloudID] URLByAppendingPathComponent:@"Documents"].path;
    [self _ensureFolderAtPath:path];
    __iCloudsDriveDocumentsPath = path;
  }

  return __iCloudsDriveDocumentsPath;
}

+ (void)linkICloudDriveIfNeeded
{
  [self _linkAtPath:[[self homePath] stringByAppendingPathComponent:@"iCloud"]
    destinationPath:[self iCloudDriveDocuments]];
}

+ (void)linkDocumentsIfNeeded {
  [self _linkAtPath:[[self homePath] stringByAppendingPathComponent:@"Documents"]
    destinationPath:[self documentsPath]];
}

+ (void)_linkAtPath:(NSString *)path destinationPath:(NSString *)destinationPath {
  NSFileManager *fm = [NSFileManager defaultManager];
  
  // Don't use fileExists as that would traverse the symlink.
  if ([fm attributesOfItemAtPath:path error:nil]) {
    NSString *currentDestinationPath = [fm destinationOfSymbolicLinkAtPath:path error:nil];
    if (!currentDestinationPath) {
      return;
    }

    // We lost access. Remove that symlink.
    if (![fm isReadableFileAtPath: currentDestinationPath]) {
      [fm removeItemAtPath: path error: nil];
    } else {
      return;
    }
  }
  NSError *error = nil;

  BOOL ok = [fm createSymbolicLinkAtPath:path
                     withDestinationPath:destinationPath
                                   error:&error];

  if (!ok) {
    NSLog(@"Error: %@", error);
  };
}

+ (NSString *)blink {
  NSString *dotBlink = [[self homePath] stringByAppendingPathComponent:@".blink"];
  [self _ensureFolderAtPath:dotBlink];
  return dotBlink;
}

+ (NSString *)blinkBuild {
  NSString *dotBlinkBuild = [[self homePath] stringByAppendingPathComponent:@".blink-build"];
  [self _ensureFolderAtPath:dotBlinkBuild];
  return dotBlinkBuild;
}


+ (NSString *)ssh {
  NSString *dotSSH = [[self homePath] stringByAppendingPathComponent:@".ssh"];
  [self _ensureFolderAtPath:dotSSH];
  return dotSSH;
}

+ (NSString *)blinkAgentSettings {
  NSString *path = [[self blink] stringByAppendingPathComponent:@"agents"];
  [self _ensureFolderAtPath:path];
  return path;
}

+ (void)_ensureFolderAtPath:(NSString *)path {
  BOOL isDir = NO;
  NSFileManager *fm = [NSFileManager defaultManager];
  if ([fm fileExistsAtPath:path isDirectory:&isDir]) {
    if (isDir) {
      return;
    }

    [fm removeItemAtPath:path error:nil];
  }
  [fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:@{} error:nil];
}


+ (NSURL *)blinkURL
{
  return [NSURL fileURLWithPath:[self blink]];
}

+ (NSURL *)blinkBuildURL
{
  return [NSURL fileURLWithPath:[self blinkBuild]];
}

+ (NSURL *)blinkBuildTokenURL
{
  NSString *url = [self blinkBuild];
  return [NSURL fileURLWithPath:[url stringByAppendingPathComponent:@".build.token"]];
}

+ (NSURL *)blinkBuildStagingMarkURL
{
  NSString *url = [self blinkBuild];
  return [NSURL fileURLWithPath:[url stringByAppendingPathComponent:@".staging"]];
}

+ (NSURL *)blinkAgentSettingsURL
{
  return [NSURL fileURLWithPath:[self blinkAgentSettings]];
}

+ (NSURL *)sshURL
{
  return [NSURL fileURLWithPath:[self ssh]];
}

+ (NSString *)blinkKeysFile
{
  return [[self blink] stringByAppendingPathComponent:@"keys"];
}

+ (NSURL *)blinkKBConfigURL
{
  return [[self blinkURL] URLByAppendingPathComponent:@"kb.json"];
}

+ (NSString *)blinkHostsFile
{
  return [[self blink] stringByAppendingPathComponent:@"hosts"];
}

+ (NSURL *)blinkGlobalSSHConfigFileURL
{
  return [[self blinkURL] URLByAppendingPathComponent:@"ssh_global"];
}

+ (NSURL *)blinkSSHConfigFileURL
{
  return [[self blinkURL] URLByAppendingPathComponent:@"ssh_config"];
}


+ (NSString *)blinkSyncItemsFile
{
  return [[self blink] stringByAppendingPathComponent:@"syncItems"];
}

+ (NSString *)blinkProfileFile
{
  return [[self blink] stringByAppendingPathComponent:@"profile"];
}

+ (NSString *)historyFile
{
  return [[self blink] stringByAppendingPathComponent:@"history.txt"];
}

+ (NSURL *)historyURL
{
  return [NSURL fileURLWithPath:[self historyFile]];
}

+ (NSURL *)localSnippetsLocationURL
{
  return [NSURL fileURLWithPath:[[self documentsPath] stringByAppendingPathComponent:@"snips"]];
}

+ (NSURL *)iCloudSnippetsLocationURL {
  NSString *path = [self iCloudDriveDocuments];
  if (path) {
    return [NSURL fileURLWithPath:[path stringByAppendingPathComponent:@"snips"]];
  }
  return nil;
}

+ (NSURL *)fileProviderReplicatedURL {
  NSString *fileProviderPath = [[self groupContainerPath] stringByAppendingPathComponent:@"FileProviderReplicated"];
  [self _ensureFolderAtPath:fileProviderPath];
  return [NSURL fileURLWithPath:fileProviderPath];
}

+ (NSString *)knownHostsFile
{
  return [[self ssh] stringByAppendingPathComponent:@"known_hosts"];
}

+ (NSString *)blinkDefaultsFile
{
  return [[self blink] stringByAppendingPathComponent:@"defaults"];
}

+ (NSURL *)fileProviderErrorLogURL
{
  return [[self blinkURL] URLByAppendingPathComponent:@"fileprovider.log"];
}

+ (NSURL *)blinkCodeErrorLogURL
{
  return [[self blinkURL] URLByAppendingPathComponent:@"blinkCode.log"];
}

@end
