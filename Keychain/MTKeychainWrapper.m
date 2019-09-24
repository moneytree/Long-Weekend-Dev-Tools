//
// LWEKeychainWrapper.m
//
// Copyright (c) 2012 Long Weekend LLC
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
// associated documentation files (the "Software"), to deal in the Software without restriction,
// including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
// and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
// subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial
// portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
// NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
// IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
// SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

// TODO: Clean up this class, this class is F in messed up -- RPR 2015-04-24
// Maybe pull this out from LWE's and start a new MT's one.
// Ticket is here: https://www.pivotaltracker.com/story/show/93187208

#import "MTKeychainWrapper.h"

static NSString * const LWEKeychainDictionaryKey = @"LWEKeychainDictionaryKey";

@interface MTKeychainWrapper ()
@property (nonatomic, strong) NSString *identifier;
@property (nonatomic, strong) NSString *accessGroup;
@property (nonatomic, strong) NSDictionary *genericPasswordQuery;
@property (nonatomic, strong) NSMutableDictionary *keychainItem;
@property (nonatomic, strong) NSMutableDictionary *keychainData;
@end

@implementation MTKeychainWrapper

#pragma mark - Public Methods

- (OSStatus)setObject:(id)object forKey:(NSString *)key {
  id currentObject = self.keychainData[key];
  OSStatus status = noErr;
  if (object == nil) {
    [self.keychainData removeObjectForKey:key];
    status = [self writeToKeychain_];
  } else if ([currentObject isEqual:object] == NO) {
    [self.keychainData setObject:object forKey:key];
    status = [self writeToKeychain_];
  }
  return status;
}

- (OSStatus)removeObjectsForKeys:(NSArray<id> *)keys {
  [self.keychainData removeObjectsForKeys:keys];
  return [self writeToKeychain_];
}

- (id)objectForKey:(NSString *)key {
  return [self.keychainData objectForKey:key];
}

- (void)resetKeychainItem {
  [[self class] resetKeychainForIdentifier:self.identifier accessGroup:self.accessGroup];
  [self initializeForEmptyKeychain_];
}

+ (void)resetKeychainForIdentifier:(NSString *)keychainIdentifier accessGroup:(NSString *)accessGroup {
  // Delete everything from the keychain that is stored under our identifier.
  // We want to keep our delete query as general as possible,
  // so that it clears even old keychain items from previous versions of the app,
  // without making it so general that it might
  // delete keychain items maintained by other code in our app.
  NSMutableDictionary *keychainQuery = [NSMutableDictionary dictionary];
  [keychainQuery setObject:(__bridge id)kSecClassGenericPassword forKey:(__bridge id)kSecClass];
  if (keychainIdentifier) {
    [keychainQuery setObject:keychainIdentifier forKey:(__bridge id)kSecAttrGeneric];
  }

  if (accessGroup != nil) {
    #if TARGET_IPHONE_SIMULATOR
      // Ignore the access group if running on the iPhone simulator.
      //
      // Apps that are built for the simulator aren't signed, so there's no keychain access group
      // for the simulator to check. This means that all apps can see all keychain items when run
      // on the simulator.
      //
      // If a SecItem contains an access group attribute, SecItemAdd and SecItemUpdate on the
      // simulator will return -25243 (errSecNoAccessForItem).
    #else
      [keychainQuery setObject:accessGroup forKey:(__bridge id)kSecAttrAccessGroup];
    #endif
  }

  OSStatus status = SecItemDelete((__bridge CFDictionaryRef)keychainQuery);
  if (status != noErr && status != errSecItemNotFound) {
    NSLog(@"Problem deleting keychain items: %d", (int)status);
  }
}

#pragma mark - Privates

- (NSMutableDictionary *)_dictionaryToSecItemFormat {
  // The assumption is that this method will be called with a properly populated dictionary
  // containing all the right key/value pairs for a SecItem.
  // Create a dictionary to return populated with the attributes and data.
  NSMutableDictionary *returnDictionary = [NSMutableDictionary dictionaryWithDictionary:self.keychainItem];
  
  // Add the Generic Password keychain item class attribute. (If its not already there)
  [returnDictionary setObject:(__bridge id)kSecClassGenericPassword forKey:(__bridge id)kSecClass];
  [returnDictionary setObject:(__bridge id)kSecAttrAccessibleAfterFirstUnlock forKey:(__bridge id)kSecAttrAccessible];
  
  // Convert the NSDictionary to NSData to meet the requirements for the value type kSecValueData.
  // This is where to store sensitive data that should be encrypted.
  NSMutableData *data = [[NSMutableData alloc] init];
  NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
  [archiver encodeObject:self.keychainData forKey:LWEKeychainDictionaryKey];
  [archiver finishEncoding];
  [returnDictionary setObject:data forKey:(__bridge id)kSecValueData];
  
  return returnDictionary;
}

- (NSDictionary *)_generateGenericDictionaryForSearching:(BOOL)forSearching {
  // Begin Keychain search setup. The genericPasswordQuery leverages the special user
  // defined attribute kSecAttrGeneric to distinguish itself between other generic Keychain
  // items which may be included by the same application.
  NSMutableDictionary *genericDict = [[NSMutableDictionary alloc] init];
  
  [genericDict setObject:(__bridge id)kSecClassGenericPassword forKey:(__bridge id)kSecClass];
  [genericDict setObject:self.identifier forKey:(__bridge id)kSecAttrGeneric];
  [genericDict setObject:self.identifier forKey:(__bridge id)kSecAttrAccount];
  
  // The keychain access group attribute determines if this item can be shared
  // amongst multiple apps whose code signing entitlements contain the same keychain access group.
  if (self.accessGroup != nil) {
#if TARGET_IPHONE_SIMULATOR
    // Ignore the access group if running on the iPhone simulator.
    // 
    // Apps that are built for the simulator aren't signed, so there's no keychain access group
    // for the simulator to check. This means that all apps can see all keychain items when run
    // on the simulator.
    //
    // If a SecItem contains an access group attribute, SecItemAdd and SecItemUpdate on the
    // simulator will return -25243 (errSecNoAccessForItem).
#else			
    [genericDict setObject:self.accessGroup forKey:(__bridge id)kSecAttrAccessGroup];
#endif
  }
  
  //I dont really like this, but in case of "not-for-searching"
  //dictionary, we are "secretly" returrning a NSMutableDictionary object.
  //Thats fine though because we are persisting those in a Mutable format as well.
  if (forSearching) {
    // Use the proper search constants, return only the attributes of the first match.
    [genericDict setObject:(__bridge id)kSecMatchLimitOne forKey:(__bridge id)kSecMatchLimit];
    [genericDict setObject:(__bridge id)kCFBooleanTrue forKey:(__bridge id)kSecReturnAttributes];
    return [NSDictionary dictionaryWithDictionary:genericDict];
  } else {
    [genericDict setObject:@"" forKey:(__bridge id)kSecValueData];
    [genericDict setObject:@"" forKey:(__bridge id)kSecAttrLabel];
    [genericDict setObject:@"" forKey:(__bridge id)kSecAttrDescription];
  }
  return genericDict;
}

- (void)_getKeychainData {
  CFDictionaryRef cfdict = NULL;
  if (SecItemCopyMatching((__bridge CFDictionaryRef)self.genericPasswordQuery, (CFTypeRef *)&cfdict) != noErr) {
    [self initializeForEmptyKeychain_];
  } else {
    NSDictionary *metadataDictionary = (__bridge_transfer NSDictionary *)cfdict;
    
    // Load the saved data from Keychain
    // 1. Create a dictionary to return populated with the attributes and data.
    NSMutableDictionary * const returnDictionary = [metadataDictionary mutableCopy];
    
    // 2. Add the proper search key and class attribute.
    [returnDictionary setObject:(__bridge id)kCFBooleanTrue forKey:(__bridge id)kSecReturnData];
    [returnDictionary setObject:(__bridge id)kSecClassGenericPassword forKey:(__bridge id)kSecClass];
    
    // 3. Acquire the "data" from the attributes.
    CFDataRef cfdata = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)returnDictionary, (CFTypeRef *)&cfdata) == noErr) {
      NSData *data = (__bridge_transfer NSData *)cfdata;
      // 3a. Remove the search, class, and identifier key/value, we don't need them anymore.
      [returnDictionary removeObjectForKey:(__bridge id)kSecReturnData];
      
      // 3b. Add the password to the dictionary, converting from NSData to NSDictionary.
      NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
      NSMutableDictionary *dataDict = [unarchiver decodeObjectForKey:LWEKeychainDictionaryKey];
      [unarchiver finishDecoding];

      if (dataDict != nil) {
        // 3c. Set the data back to the return dict as part of the "kSecValueData" key.
        [returnDictionary setObject:dataDict forKey:(__bridge id)kSecValueData];

        // 3d. Set thos values back to the ivar.
        self.keychainItem = [NSMutableDictionary dictionaryWithDictionary:returnDictionary];
        self.keychainData = dataDict;
      } else {
        // Would like to do all `MT_LOG` or `MT_ASSERT` here even with
        // Crashlytics, but this file lives in a different world (lwe-dev-tools)
        // TODO: Move to Lib along with crash reporting facade and logging -- RPR 2017-06-26
        NSLog(@"Query: %@ is fetched but no data: %@", self.genericPasswordQuery, returnDictionary);
        NSAssert(NO, @"No expected data.");

        // Should not happen but to avoid crash here
        // https://fabric.io/moneytree-kk/ios/apps/jp.moneytree.journal/issues/594a2eaebe077a4dcc698647/sessions/f7f28e940f4c4844b63242b77c07dd6c_e2fc9aa456ee11e7bdaf56847afe9799_0_v2
        [self initializeForEmptyKeychain_];
      }
    } else {
      NSAssert(NO, @"The keychain should have the 'data'/'password' on its item.");
    }
  }
}

- (void)initializeForEmptyKeychain_ {
  self.keychainItem = (NSMutableDictionary *)[self _generateGenericDictionaryForSearching:NO];
  self.keychainData = [[NSMutableDictionary alloc] init];
}

- (OSStatus)writeToKeychain_ {
  CFDictionaryRef cfdict = NULL;
	OSStatus result;
  if (SecItemCopyMatching((__bridge CFDictionaryRef)self.genericPasswordQuery, (CFTypeRef *)&cfdict) == noErr) {
    //This will be used for update. We cannot use the genericPasswordQuery because that has
    //attribute like 'return-attribute with YES value", etc WHICH couldnt be used for SecItemUpdate().
    //It will return error code -50.
    NSMutableDictionary *dictionary = [(__bridge_transfer NSDictionary *)cfdict mutableCopy];
    [dictionary setObject:[self.genericPasswordQuery objectForKey:(__bridge id)kSecClass] forKey:(__bridge id)kSecClass];
    
    // Lastly, we need to set up the updated attribute list being careful to remove the class.
    // Only real keychain attributes are permitted in this dictionary (no "meta" attributes are allowed.) 
    // See “Attribute Item Keys and Values” for a description of currently defined value attributes.
    NSMutableDictionary *updatedItem = [self _dictionaryToSecItemFormat];
    [updatedItem removeObjectForKey:(__bridge id)kSecClass];
		
#if TARGET_IPHONE_SIMULATOR
		// Remove the access group if running on the iPhone simulator.
		// 
		// Apps that are built for the simulator aren't signed, so there's no keychain access group
		// for the simulator to check. This means that all apps can see all keychain items when run
		// on the simulator.
		//
		// If a SecItem contains an access group attribute, SecItemAdd and SecItemUpdate on the
		// simulator will return -25243 (errSecNoAccessForItem).
		//
		// The access group attribute will be included in items returned by SecItemCopyMatching,
		// which is why we need to remove it before updating the item.
		[updatedItem removeObjectForKey:(__bridge id)kSecAttrAccessGroup];
#endif
    
    // An implicit assumption is that you can only update a single item at a time.
    result = SecItemUpdate((__bridge CFDictionaryRef)dictionary, (__bridge CFDictionaryRef)updatedItem);
  } else {
    // No previous item found; add the new one.
    NSDictionary *addedItem = [self _dictionaryToSecItemFormat];
    result = SecItemAdd((__bridge CFDictionaryRef)addedItem, NULL);
  }
  return result;
}

#pragma mark - Class Plumbing

- (id)initWithIdentifier:(NSString *)identifier accessGroup:(NSString *)accessGroup {
  self = [super init];
  if (self) {
    self.identifier = identifier;
    self.accessGroup = accessGroup;
    self.genericPasswordQuery = [self _generateGenericDictionaryForSearching:YES];
    
    [self _getKeychainData];
  }
	return self;
}

@end
