//
//  DSBlockchainUserTopupTransaction.h
//  DashSync
//
//  Created by Sam Westrich on 7/30/18.
//

#import "DSTransaction.h"
#import "IntTypes.h"

@class DSKey,DSChain;

@interface DSBlockchainUserTopupTransaction : DSTransaction

@property (nonatomic,readonly) uint16_t blockchainUserTopupTransactionVersion;
@property (nonatomic,readonly) UInt256 registrationTransactionHash;
@property (nonatomic,readonly) UInt256 previousSubscriptionTransactionHash;
@property (nonatomic,readonly) NSNumber * topupAmount;
@property (nonatomic,readonly) uint16_t topupIndex;

- (instancetype)initWithInputHashes:(NSArray *)hashes inputIndexes:(NSArray *)indexes inputScripts:(NSArray *)scripts inputSequences:(NSArray*)inputSequences outputAddresses:(NSArray *)addresses outputAmounts:(NSArray *)amounts BlockchainUserTopupTransactionVersion:(uint16_t)version registrationTransactionHash:(UInt256)registrationTransactionHash previousSubscriptionTransactionHash:(UInt256)previousSubscriptionTransactionHash topupAmount:(NSNumber*)topupAmount topupIndex:(uint16_t)topupIndex onChain:(DSChain *)chain;

-(instancetype)initWithBlockchainUserTopupTransactionVersion:(uint16_t)version registrationTransactionHash:(UInt256)registrationTransactionHash previousSubscriptionTransactionHash:(UInt256)previousSubscriptionTransactionHash onChain:(DSChain*)chain;

@end
