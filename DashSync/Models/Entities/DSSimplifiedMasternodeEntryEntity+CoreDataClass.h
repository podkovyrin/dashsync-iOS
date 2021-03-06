//
//  DSSimplifiedMasternodeEntryEntity+CoreDataClass.h
//  DashSync
//
//  Created by Sam Westrich on 7/19/18.
//
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class DSChainEntity,DSSimplifiedMasternodeEntry;

NS_ASSUME_NONNULL_BEGIN

@interface DSSimplifiedMasternodeEntryEntity : NSManagedObject

- (void)updateAttributesFromSimplifiedMasternodeEntry:(DSSimplifiedMasternodeEntry * _Nonnull)simplifiedMasternodeEntry;
- (void)setAttributesFromSimplifiedMasternodeEntry:(DSSimplifiedMasternodeEntry * _Nonnull)simplifiedMasternodeEntry onChain:(DSChainEntity* _Nullable)chainEntity;
+ (void)deleteHavingProviderTransactionHashes:(NSArray*)providerTransactionHashes onChain:(DSChainEntity* _Nonnull)chainEntity;
+ (DSSimplifiedMasternodeEntryEntity* _Nullable)simplifiedMasternodeEntryForHash:(NSData*)simplifiedMasternodeEntryHash onChain:(DSChainEntity* _Nonnull)chainEntity;

- (DSSimplifiedMasternodeEntry* _Nullable)simplifiedMasternodeEntry;
+ (void)deleteAllOnChain:(DSChainEntity*)chainEntity;

@end

NS_ASSUME_NONNULL_END

#import "DSSimplifiedMasternodeEntryEntity+CoreDataProperties.h"
