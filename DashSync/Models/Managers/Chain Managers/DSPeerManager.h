//
//  DSPeerManager.h
//  DashSync
//
//  Created by Aaron Voisine for BreadWallet on 10/6/13.
//  Copyright (c) 2013 Aaron Voisine <voisine@gmail.com>
//  Copyright (c) 2018 Dash Core Group <contact@dash.org>
//  Updated by Quantum Explorer on 05/11/18.
//  Copyright (c) 2018 Quantum Explorer <quantum@dash.org>
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

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "DSChain.h"
#import "DSPeer.h"

FOUNDATION_EXPORT NSString* _Nonnull const DSPeerManagerConnectedPeersDidChangeNotification;
FOUNDATION_EXPORT NSString* _Nonnull const DSPeerManagerDownloadPeerDidChangeNotification;
FOUNDATION_EXPORT NSString* _Nonnull const DSPeerManagerPeersDidChangeNotification;

#define PEER_MAX_CONNECTIONS 3
#define SETTINGS_FIXED_PEER_KEY @"SETTINGS_FIXED_PEER"


#define LAST_SYNCED_GOVERANCE_OBJECTS @"LAST_SYNCED_GOVERANCE_OBJECTS"
#define LAST_SYNCED_MASTERNODE_LIST @"LAST_SYNCED_MASTERNODE_LIST"

@class DSTransaction,DSGovernanceSyncManager,DSMasternodeManager,DSSporkManager,DSPeer,DSGovernanceVote,DSDAPIPeerManager,DSTransactionManager;

@interface DSPeerManager : NSObject <DSPeerDelegate, UIAlertViewDelegate>

@property (nonatomic, readonly) BOOL connected;
@property (nonatomic, readonly) NSUInteger peerCount;
@property (nonatomic, readonly) NSUInteger connectedPeerCount; // number of connected peers
@property (nonatomic, readonly) NSString * _Nullable downloadPeerName;
@property (nonatomic, readonly) DSChain * chain;
@property (nonatomic, readonly) DSPeer * downloadPeer, *fixedPeer;
@property (nonatomic, readonly) NSArray* registeredDevnetPeers;
@property (nonatomic, readonly) NSArray* registeredDevnetPeerServices;
@property (nonatomic, readonly) NSString* trustedPeerHost;

- (instancetype)initWithChain:(DSChain*)chain;

- (void)connect;
- (void)clearPeers;
- (void)disconnect;

- (void)clearRegisteredPeers;
- (void)registerPeerAtLocation:(UInt128)IPAddress port:(uint32_t)port dapiPort:(uint32_t)dapiPort;

- (DSPeerStatus)statusForLocation:(UInt128)IPAddress port:(uint32_t)port;
- (DSPeerType)typeForLocation:(UInt128)IPAddress port:(uint32_t)port;
- (void)setTrustedPeerHost:(NSString*)host;
- (void)removeTrustedPeerHost;

@end
