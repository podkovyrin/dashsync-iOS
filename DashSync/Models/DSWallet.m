//
//  DSWallet.m
//  DashSync
//
//  Created by Sam Westrich on 5/20/18.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "DSWallet.h"
#import "DSAccount.h"
#import "DSAuthenticationManager.h"
#import "DSWalletManager.h"
#import "DSBIP39Mnemonic.h"
#import "NSManagedObject+Sugar.h"
#import "NSMutableData+Dash.h"
#import "DSAddressEntity+CoreDataProperties.h"
#import "DSTransactionEntity+CoreDataProperties.h"

#define SEED_ENTROPY_LENGTH   (128/8)
#define SEC_ATTR_SERVICE      @"org.dashfoundation.dash"
#define CREATION_TIME_KEY   @"creationtime"

static BOOL setKeychainData(NSData *data, NSString *key, BOOL authenticated)
{
    if (! key) return NO;
    
    id accessible = (authenticated) ? (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    : (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
    NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                            (__bridge id)kSecAttrAccount:key};
    
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, NULL) == errSecItemNotFound) {
        if (! data) return YES;
        
        NSDictionary *item = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                               (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                               (__bridge id)kSecAttrAccount:key,
                               (__bridge id)kSecAttrAccessible:accessible,
                               (__bridge id)kSecValueData:data};
        OSStatus status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
        
        if (status == noErr) return YES;
        NSLog(@"SecItemAdd error: %@",
              [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil].localizedDescription);
        return NO;
    }
    
    if (! data) {
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
        
        if (status == noErr) return YES;
        NSLog(@"SecItemDelete error: %@",
              [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil].localizedDescription);
        return NO;
    }
    
    NSDictionary *update = @{(__bridge id)kSecAttrAccessible:accessible,
                             (__bridge id)kSecValueData:data};
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)update);
    
    if (status == noErr) return YES;
    NSLog(@"SecItemUpdate error: %@",
          [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil].localizedDescription);
    return NO;
}

static BOOL hasKeychainData(NSString *key, NSError **error)
{
    NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                            (__bridge id)kSecAttrAccount:key,
                            (__bridge id)kSecReturnRef:@YES};
    CFDataRef result = nil;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
    
    if (status == errSecItemNotFound) return NO;
    if (status == noErr) return YES;
    NSLog(@"SecItemCopyMatching error: %@",
          [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil].localizedDescription);
    if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    return nil;
}

static NSData *getKeychainData(NSString *key, NSError **error)
{
    NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrService:SEC_ATTR_SERVICE,
                            (__bridge id)kSecAttrAccount:key,
                            (__bridge id)kSecReturnData:@YES};
    CFDataRef result = nil;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
    
    if (status == errSecItemNotFound) return nil;
    if (status == noErr) return CFBridgingRelease(result);
    NSLog(@"SecItemCopyMatching error: %@",
          [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil].localizedDescription);
    if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    return nil;
}

static BOOL setKeychainInt(int64_t i, NSString *key, BOOL authenticated)
{
    @autoreleasepool {
        NSMutableData *d = [NSMutableData secureDataWithLength:sizeof(int64_t)];
        
        *(int64_t *)d.mutableBytes = i;
        return setKeychainData(d, key, authenticated);
    }
}

static int64_t getKeychainInt(NSString *key, NSError **error)
{
    @autoreleasepool {
        NSData *d = getKeychainData(key, error);
        
        return (d.length == sizeof(int64_t)) ? *(int64_t *)d.bytes : 0;
    }
}

static BOOL setKeychainString(NSString *s, NSString *key, BOOL authenticated)
{
    @autoreleasepool {
        NSData *d = (s) ? CFBridgingRelease(CFStringCreateExternalRepresentation(SecureAllocator(), (CFStringRef)s,
                                                                                 kCFStringEncodingUTF8, 0)) : nil;
        
        return setKeychainData(d, key, authenticated);
    }
}

static NSString *getKeychainString(NSString *key, NSError **error)
{
    @autoreleasepool {
        NSData *d = getKeychainData(key, error);
        
        return (d) ? CFBridgingRelease(CFStringCreateFromExternalRepresentation(SecureAllocator(), (CFDataRef)d,
                                                                                kCFStringEncodingUTF8)) : nil;
    }
}

static BOOL setKeychainDict(NSDictionary *dict, NSString *key, BOOL authenticated)
{
    @autoreleasepool {
        NSData *d = (dict) ? [NSKeyedArchiver archivedDataWithRootObject:dict] : nil;
        
        return setKeychainData(d, key, authenticated);
    }
}

static NSDictionary *getKeychainDict(NSString *key, NSError **error)
{
    @autoreleasepool {
        NSData *d = getKeychainData(key, error);
        
        return (d) ? [NSKeyedUnarchiver unarchiveObjectWithData:d] : nil;
    }
}

@interface DSWallet()

@property (nonatomic, strong) DSChain * chain;
@property (nonatomic, strong) NSMutableDictionary * mAccounts;

@end

@implementation DSWallet

+ (DSWallet*)standardWalletWithSeedPhrase:(NSString*)seedPhrase forChain:(DSChain*)chain storeSeedPhrase:(BOOL)store {
    DSWallet * wallet = [[DSWallet alloc] initWithSeedPhrase:seedPhrase forChain:chain storeSeedPhrase:store];
    DSAccount * account = [DSAccount accountWithDerivationPaths:[chain standardDerivationPathsForAccountNumber:0] onWallet:wallet];
    [wallet addAccount:account];
    return wallet;
}

+ (DSWallet* )standardWalletWithRandomSeedPhraseForChain:(DSChain* )chain {
    return [self standardWalletWithSeedPhrase:[self generateRandomSeed] forChain:chain storeSeedPhrase:true];
}

-(void)generateExtendedPublicKeys {
    self.seedRequestBlock(@"Please authorize", 0, ^(NSData * _Nullable seed) {
        if (seed) {
        for (DSAccount * account in self.accounts) {
            for (DSDerivationPath * derivationPath in account.derivationPaths) {
                [self setExtendedPublicKeyData:[derivationPath generateExtendedPublicKeyFromSeed:seed] forDerivationPath:derivationPath];
            }
        }
        }
    });
}

-(instancetype)initWithSeedPhrase:(NSString*)seedPhrase forChain:(DSChain*)chain storeSeedPhrase:(BOOL)store {
    if (! (self = [super init])) return nil;
    self.mAccounts = [NSMutableDictionary dictionary];
    [self setSeedPhrase:seedPhrase];
    self.chain = chain;
    if (store) {
        __weak typeof(self) weakSelf = self;
    self.seedRequestBlock = ^void(NSString *authprompt, uint64_t amount, SeedCompletionBlock seedCompletion) {
        //this happens when we request the seed
        [weakSelf seedWithPrompt:authprompt forAmount:amount completion:seedCompletion];
    };
    }
    
    [self generateExtendedPublicKeys];
    return self;
}

-(NSArray *)accounts {
    return [self.mAccounts allValues];
}

-(void)addAccount:(DSAccount*)account {
    [self.mAccounts setObject:account forKey:@(account.accountNumber)];
    account.wallet = self;
}

- (DSAccount* _Nullable)accountWithNumber:(NSUInteger)accountNumber {
    return [self.mAccounts objectForKey:@(accountNumber)];
}

-(NSData*)extendedPublicKeyForDerivationPath:(DSDerivationPath*)derivationPath {
    NSAssert(derivationPath.account.wallet.chain, @"The wallet has no chain");
    return getKeychainData([NSString stringWithFormat:@"extendedPubKey%@_%@",derivationPath.account.wallet.chain.uniqueID,derivationPath.extendedPublicKeyString], nil);
}

-(void)setExtendedPublicKeyData:(NSData*)data forDerivationPath:(DSDerivationPath*)derivationPath {
    NSAssert(derivationPath.account.wallet.chain, @"The wallet has no chain");
    NSAssert(derivationPath.account.wallet == self, @"The derivation path isn't in this wallet");
    setKeychainData(data,[NSString stringWithFormat:@"extendedPubKey%@_%@",derivationPath.account.wallet.chain.uniqueID,derivationPath.extendedPublicKeyString],NO);
}

// MARK: - Seed

// generates a random seed, saves to keychain and returns the associated seedPhrase
+ (NSString *)generateRandomSeed
{
    NSMutableData *entropy = [NSMutableData secureDataWithLength:SEED_ENTROPY_LENGTH];
    
    if (SecRandomCopyBytes(kSecRandomDefault, entropy.length, entropy.mutableBytes) != 0) return nil;
    
    NSString *phrase = [[DSBIP39Mnemonic sharedInstance] encodePhrase:entropy];
    
    return phrase;
}


- (void)seedPhraseAfterAuthentication:(void (^)(NSString * _Nullable))completion
{
    [self seedPhraseWithPrompt:nil completion:completion];
}

-(BOOL)hasSeedPhrase {
    NSError * error = nil;
    BOOL hasSeed = hasKeychainData(MNEMONIC_KEY, &error);
    return hasSeed;
}

- (void)setSeedPhrase:(NSString *)seedPhrase
{
    @autoreleasepool { // @autoreleasepool ensures sensitive data will be deallocated immediately
        if (seedPhrase) {
            // we store the wallet creation time on the keychain because keychain data persists even when an app is deleted
            NSTimeInterval time = [NSDate timeIntervalSinceReferenceDate];
            setKeychainData([NSData dataWithBytes:&time length:sizeof(time)], CREATION_TIME_KEY, NO);
            seedPhrase = [[DSBIP39Mnemonic sharedInstance] normalizePhrase:seedPhrase];
        }
        
        [[NSManagedObject context] performBlockAndWait:^{
            [DSAddressEntity deleteAllObjects];
            [DSTransactionEntity deleteAllObjects];
            [NSManagedObject saveContext];
        }];
        
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:PIN_UNLOCK_TIME_KEY];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        setKeychainData(nil, CREATION_TIME_KEY, NO);
            for (DSAccount * account in self.accounts) {
                for (DSDerivationPath * derivationPath in account.derivationPaths) {
                    setKeychainData(nil, [derivationPath extendedPublicKeyString], NO);
                }
            }
        
        setKeychainData(nil, EXTENDED_0_PUBKEY_KEY_BIP44_V1, NO); //for sanity
        setKeychainData(nil, EXTENDED_0_PUBKEY_KEY_BIP32_V1, NO); //for sanity
        setKeychainData(nil, EXTENDED_0_PUBKEY_KEY_BIP32_V0, NO); //for sanity
        setKeychainData(nil, EXTENDED_0_PUBKEY_KEY_BIP44_V0, NO); //for sanity
        setKeychainData(nil, SPEND_LIMIT_KEY, NO);
//        setKeychainData(nil, PIN_KEY, NO);
//        setKeychainData(nil, PIN_FAIL_COUNT_KEY, NO);
//        setKeychainData(nil, PIN_FAIL_HEIGHT_KEY, NO);
//        setKeychainData(nil, AUTH_PRIVKEY_KEY, NO);
//
//        self.pinAlertController = nil;
        
        if (! setKeychainString(seedPhrase, MNEMONIC_KEY, YES)) {
            NSLog(@"error setting wallet seed");
            
            if (seedPhrase) {
                UIAlertController * alert = [UIAlertController
                                             alertControllerWithTitle:@"couldn't create wallet"
                                             message:@"error adding master private key to iOS keychain, make sure app has keychain entitlements"
                                             preferredStyle:UIAlertControllerStyleAlert];
                UIAlertAction* okButton = [UIAlertAction
                                           actionWithTitle:@"abort"
                                           style:UIAlertActionStyleCancel
                                           handler:^(UIAlertAction * action) {
                                               exit(0);
                                           }];
                [alert addAction:okButton];
                [[[DSWalletManager sharedInstance] presentingViewController] presentViewController:alert animated:YES completion:nil];
            }
            
            return;
        }
        
        NSData * derivedKeyData = (seedPhrase) ?[[DSBIP39Mnemonic sharedInstance]
                                                 deriveKeyFromPhrase:seedPhrase withPassphrase:nil]:nil;
        
        if (seedPhrase) {
                for (DSAccount * account in self.accounts) {
                    for (DSDerivationPath * derivationPath in account.derivationPaths) {
                        if ([seedPhrase isEqual:@"wipe"]) {
                            setKeychainData([NSData data], [derivationPath extendedPublicKeyString], NO);
                        } else {
                            NSData * data = [derivationPath generateExtendedPublicKeyFromSeed:derivedKeyData];
                            setKeychainData(data, [derivationPath extendedPublicKeyString], NO);
                        }
                    }
                }
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:DSWalletManagerSeedChangedNotification object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:DSWalletBalanceChangedNotification object:nil];
    });
}

// interval since refrence date, 00:00:00 01/01/01 GMT
- (NSTimeInterval)seedCreationTime
{
    NSData *d = getKeychainData(CREATION_TIME_KEY, nil);
    
    if (d.length == sizeof(NSTimeInterval)) return *(const NSTimeInterval *)d.bytes;
    return ([DSWalletManager sharedInstance].watchOnly) ? 0 : BIP39_CREATION_TIME;
}

// authenticates user and returns seed
- (void)seedWithPrompt:(NSString *)authprompt forAmount:(uint64_t)amount completion:(void (^)(NSData * seed))completion
{
    @autoreleasepool {
        BOOL touchid = (self.totalSent + amount < getKeychainInt(SPEND_LIMIT_KEY, nil)) ? YES : NO;
        
        [[DSAuthenticationManager sharedInstance] authenticateWithPrompt:authprompt andTouchId:touchid alertIfLockout:YES completion:^(BOOL authenticated,BOOL cancelled) {
            if (!authenticated) {
                completion(nil);
            } else {
                // BUG: if user manually chooses to enter pin, the touch id spending limit is reset, but the tx being authorized
                // still counts towards the next touch id spending limit
                if (! touchid) setKeychainInt(self.totalSent + amount + [DSWalletManager sharedInstance].spendingLimit, SPEND_LIMIT_KEY, NO);
                completion([[DSBIP39Mnemonic sharedInstance] deriveKeyFromPhrase:getKeychainString(MNEMONIC_KEY, nil) withPassphrase:nil]);
            }
        }];
        
    }
}

-(NSString*)seedPhraseIfAuthenticated {
    
    if (![DSAuthenticationManager sharedInstance].usesAuthentication || [DSAuthenticationManager sharedInstance].didAuthenticate) {
        return getKeychainString(MNEMONIC_KEY, nil);
    } else {
        return nil;
    }
}

// authenticates user and returns seedPhrase
- (void)seedPhraseWithPrompt:(NSString *)authprompt completion:(void (^)(NSString * seedPhrase))completion
{
    @autoreleasepool {
        [[DSAuthenticationManager sharedInstance] authenticateWithPrompt:authprompt andTouchId:NO alertIfLockout:YES completion:^(BOOL authenticated,BOOL cancelled) {
            NSString * rSeedPhrase = authenticated?getKeychainString(MNEMONIC_KEY, nil):nil;
            completion(rSeedPhrase);
        }];
    }
}

// MARK: - Combining Accounts

-(NSArray *)registerAddressesWithGapLimit:(NSUInteger)gapLimit internal:(BOOL)internal {
    NSMutableArray * mArray = [NSMutableArray array];
    for (DSAccount * account in self.accounts) {
        [mArray addObjectsFromArray:[account registerAddressesWithGapLimit:gapLimit internal:internal]];
    }
    return [mArray copy];
}

- (DSAccount*)accountContainingTransaction:(DSTransaction *)transaction {
    for (DSAccount * account in self.accounts) {
        if ([account containsTransaction:transaction]) return account;
    }
    return FALSE;
}

// all previously generated external addresses
-(NSSet *)allReceiveAddresses {
    NSMutableSet * mSet = [NSMutableSet set];
    for (DSAccount * account in self.accounts) {
        [mSet addObjectsFromArray:[account externalAddresses]];
    }
    return [mSet copy];
}

// all previously generated internal addresses
-(NSSet *)allChangeAddresses {
    NSMutableSet * mSet = [NSMutableSet set];
    for (DSAccount * account in self.accounts) {
        [mSet addObjectsFromArray:[account internalAddresses]];
    }
    return [mSet copy];
}

-(NSArray *) allTransactions {
    NSMutableArray * mArray = [NSMutableArray array];
    for (DSAccount * account in self.accounts) {
        [mArray addObjectsFromArray:account.allTransactions];
    }
    return mArray;
}

- (DSTransaction *)transactionForHash:(UInt256)txHash {
    for (DSAccount * account in self.accounts) {
        DSTransaction * transaction = [account transactionForHash:txHash];
        if (transaction) return transaction;
    }
    return nil;
}

-(NSArray *) unspentOutputs {
    NSMutableArray * mArray = [NSMutableArray array];
    for (DSAccount * account in self.accounts) {
        [mArray addObjectsFromArray:account.unspentOutputs];
    }
    return mArray;
}

// true if the address is controlled by the wallet
- (BOOL)containsAddress:(NSString *)address {
    for (DSAccount * account in self.accounts) {
        if ([account containsAddress:address]) return TRUE;
    }
    return FALSE;
}

// true if the address was previously used as an input or output in any wallet transaction
- (BOOL)addressIsUsed:(NSString *)address {
    for (DSAccount * account in self.accounts) {
        if ([account addressIsUsed:address]) return TRUE;
    }
    return FALSE;
}

// returns the amount received by the wallet from the transaction (total outputs to change and/or receive addresses)
- (uint64_t)amountReceivedFromTransaction:(DSTransaction *)transaction {
    uint64_t received = 0;
    for (DSAccount * account in self.accounts) {
        received += [account amountReceivedFromTransaction:transaction];
    }
    return received;
}

// retuns the amount sent from the wallet by the trasaction (total wallet outputs consumed, change and fee included)
- (uint64_t)amountSentByTransaction:(DSTransaction *)transaction {
    uint64_t sent = 0;
    for (DSAccount * account in self.accounts) {
        sent += [account amountSentByTransaction:transaction];
    }
    return sent;
}

// set the block heights and timestamps for the given transactions, use a height of TX_UNCONFIRMED and timestamp of 0 to
// indicate a transaction and it's dependents should remain marked as unverified (not 0-conf safe)
- (NSArray *)setBlockHeight:(int32_t)height andTimestamp:(NSTimeInterval)timestamp forTxHashes:(NSArray *)txHashes
{
    NSMutableArray *updated = [NSMutableArray array];
    
    if (height != TX_UNCONFIRMED && height > self.bestBlockHeight) self.bestBlockHeight = height;
    
    for (DSAccount * account in self.accounts) {
        NSArray * fromAccount = [account setBlockHeight:height andTimestamp:timestamp forTxHashes:txHashes];
        if (fromAccount)
            [updated addObjectsFromArray:fromAccount];
    }
    return updated;
}

- (DSAccount *)accountForTransactionHash:(UInt256)txHash transaction:(DSTransaction **)transaction {
    for (DSAccount * account in self.accounts) {
        DSTransaction * lTransaction = [account transactionForHash:txHash];
        if (lTransaction) {
            if (transaction) *transaction = lTransaction;
            return account;
        }
    }
    return nil;
}

- (BOOL)transactionIsValid:(DSTransaction * _Nonnull)transaction {
    for (DSAccount * account in self.accounts) {
        if (![account transactionIsValid:transaction]) return FALSE;
    }
    return TRUE;
}

@end
