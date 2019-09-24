//
// LWEKeychainWrapper.h
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

@import Foundation;
@import Security;

NS_ASSUME_NONNULL_BEGIN

@interface MTKeychainWrapper : NSObject

- (OSStatus)removeObjectsForKeys:(NSArray<NSString *> *)keys;
- (OSStatus)setObject:(nullable id)object forKey:(NSString *)key;
- (nullable id)objectForKey:(NSString *)key;
- (void)resetKeychainItem;

/** 
 * Resets all items in the keychain. `keychainIdentifier` argument is optional; if nil, everything is
 * cleared out (that we have access to).
 */
+ (void)resetKeychainForIdentifier:(NSString *)keychainIdentifier accessGroup:(NSString *)accessGroup;

- (id)initWithIdentifier:(NSString *)identifier accessGroup:(NSString *)accessGroup;

@end

NS_ASSUME_NONNULL_END
