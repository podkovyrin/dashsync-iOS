//
//  DSGovernanceSyncManager.m
//  DashSync
//
//  Created by Sam Westrich on 6/12/18.
//

#import "DSGovernanceSyncManager.h"
#import "DSGovernanceObject.h"
#import "DSGovernanceVote.h"
#import "DSMasternodePing.h"
#import "DSGovernanceObjectEntity+CoreDataProperties.h"
#import "DSGovernanceObjectHashEntity+CoreDataProperties.h"
#import "DSGovernanceVoteEntity+CoreDataProperties.h"
#import "DSGovernanceVoteHashEntity+CoreDataProperties.h"
#import "NSManagedObject+Sugar.h"
#import "DSChain.h"
#import "DSPeer.h"
#import "DSChainEntity+CoreDataProperties.h"
#import "NSData+Dash.h"
#import "DSOptionsManager.h"
#import "DSMasternodeBroadcast.h"
#import "DSKey.h"
#import "DSChainPeerManager.h"
#import "DSChainManager.h"

#define REQUEST_GOVERNANCE_OBJECT_COUNT 500

@interface DSGovernanceSyncManager()

@property (nonatomic,strong) DSChain * chain;

@property (nonatomic,strong) NSOrderedSet * knownGovernanceObjectHashes; //this doesn't care if the hash has an associated governance object already known
@property (nonatomic,strong) NSMutableOrderedSet<NSData *> * knownGovernanceObjectHashesForExistingGovernanceObjects;
@property (nonatomic,readonly) NSOrderedSet * fulfilledRequestsGovernanceObjectHashEntities;
@property (nonatomic,strong) NSMutableArray * needsRequestsGovernanceObjectHashEntities;
@property (nonatomic,strong) NSMutableArray * requestGovernanceObjectHashEntities;
@property (nonatomic,strong) NSMutableArray<DSGovernanceObject *> * governanceObjects;
@property (nonatomic,strong) NSMutableArray<DSGovernanceObject *> * needVoteSyncGovernanceObjects;
@property (nonatomic,assign) NSUInteger governanceObjectsCount;

@property (nonatomic,strong) DSGovernanceObject * currentGovernanceSyncObject;

@property (nonatomic,strong) NSManagedObjectContext * managedObjectContext;

@end

@implementation DSGovernanceSyncManager

- (instancetype)initWithChain:(id)chain
{
    if (! (self = [super init])) return nil;
    _chain = chain;
    _governanceObjects = [NSMutableArray array];
    [self loadGovernanceObjects:0];
    self.managedObjectContext = [NSManagedObject context];
    return self;
}

// MARK:- Control

-(void)finishedGovernanceObjectSyncWithPeer:(DSPeer*)peer {
    if (peer.governanceRequestState != DSGovernanceRequestState_GovernanceObjects) return;
    peer.governanceRequestState = DSGovernanceRequestState_None;
    if (!([[DSOptionsManager sharedInstance] syncType] & DSSyncType_GovernanceVotes)) return;
    self.needVoteSyncGovernanceObjects = [self.governanceObjects mutableCopy];
    self.currentGovernanceSyncObject = [self.needVoteSyncGovernanceObjects firstObject];
    self.currentGovernanceSyncObject.delegate = self;
    NSLog(@"Getting votes for %@",self.currentGovernanceSyncObject.identifier);
    [peer sendGovSync:self.currentGovernanceSyncObject.governanceObjectHash];
}

-(void)finishedGovernanceVoteSyncWithPeer:(DSPeer*)peer {
    if (peer.governanceRequestState != DSGovernanceRequestState_GovernanceObjectVotes) return;
    if (!([[DSOptionsManager sharedInstance] syncType] & DSSyncType_GovernanceVotes)) return;
    peer.governanceRequestState = DSGovernanceRequestState_None;
    [self.needVoteSyncGovernanceObjects removeObject:self.currentGovernanceSyncObject];
    if ([self.needVoteSyncGovernanceObjects count]) {
        self.currentGovernanceSyncObject = [self.needVoteSyncGovernanceObjects firstObject];
        self.currentGovernanceSyncObject.delegate = self;
        NSLog(@"Getting votes for %@",self.currentGovernanceSyncObject.identifier);
        [peer sendGovSync:self.currentGovernanceSyncObject.governanceObjectHash];
    }
}

// MARK:- Governance Object

-(NSUInteger)recentGovernanceObjectHashesCount {
    __block NSUInteger count = 0;
    [self.managedObjectContext performBlockAndWait:^{
        count = [DSGovernanceObjectHashEntity countAroundNowOnChain:self.chain.chainEntity];
    }];
    return count;
}

-(NSUInteger)last3HoursStandaloneGovernanceObjectHashesCount {
    __block NSUInteger count = 0;
    [self.managedObjectContext performBlockAndWait:^{
        [DSGovernanceObjectHashEntity setContext:self.managedObjectContext];
        count = [DSGovernanceObjectHashEntity standaloneCountInLast3hoursOnChain:self.chain.chainEntity];
    }];
    return count;
}

-(NSUInteger)governanceObjectsCount {
    
    __block NSUInteger count = 0;
    [self.managedObjectContext performBlockAndWait:^{
        [DSGovernanceObjectEntity setContext:self.managedObjectContext];
        count = [DSGovernanceObjectEntity countForChain:self.chain.chainEntity];
    }];
    return count;
}


-(void)loadGovernanceObjects:(NSUInteger)count {
    NSFetchRequest * fetchRequest = [[DSGovernanceObjectEntity fetchRequest] copy];
    if (count) {
        [fetchRequest setFetchLimit:count];
    }
    if (!_knownGovernanceObjectHashesForExistingGovernanceObjects) _knownGovernanceObjectHashesForExistingGovernanceObjects = [NSMutableOrderedSet orderedSet];
    NSArray * governanceObjectEntities = [DSGovernanceObjectEntity fetchObjects:fetchRequest];
    for (DSGovernanceObjectEntity * governanceObjectEntity in governanceObjectEntities) {
        DSGovernanceObject * governanceObject = [governanceObjectEntity governanceObject];
        NSLog(@"%@ -> %@",[NSData dataWithUInt256:governanceObject.governanceObjectHash],governanceObject.identifier);
        [_knownGovernanceObjectHashesForExistingGovernanceObjects addObject:[NSData dataWithUInt256:governanceObject.governanceObjectHash]];
        [_governanceObjects addObject:governanceObject];
    }
}

-(NSOrderedSet*)knownGovernanceObjectHashes {
    if (_knownGovernanceObjectHashes) return _knownGovernanceObjectHashes;
    
    [self.managedObjectContext performBlockAndWait:^{
        [DSGovernanceObjectHashEntity setContext:self.managedObjectContext];
        NSFetchRequest *request = DSGovernanceObjectHashEntity.fetchReq;
        [request setPredicate:[NSPredicate predicateWithFormat:@"chain = %@",self.chain.chainEntity]];
        [request setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"governanceObjectHash" ascending:TRUE]]];
        NSArray<DSGovernanceObjectHashEntity *> * knownGovernanceObjectHashEntities = [DSGovernanceObjectHashEntity fetchObjects:request];
        NSMutableOrderedSet <NSData*> * rHashes = [NSMutableOrderedSet orderedSetWithCapacity:knownGovernanceObjectHashEntities.count];
        for (DSGovernanceObjectHashEntity * knownGovernanceObjectHashEntity in knownGovernanceObjectHashEntities) {
            NSData * hash = knownGovernanceObjectHashEntity.governanceObjectHash;
            [rHashes addObject:hash];
        }
        self.knownGovernanceObjectHashes = [rHashes copy];
    }];
    return _knownGovernanceObjectHashes;
}

-(NSMutableArray*)needsRequestsGovernanceObjectHashEntities {
    if (_needsRequestsGovernanceObjectHashEntities) return _needsRequestsGovernanceObjectHashEntities;
    
    [self.managedObjectContext performBlockAndWait:^{
        [DSGovernanceObjectHashEntity setContext:self.managedObjectContext];
        NSFetchRequest *request = DSGovernanceObjectHashEntity.fetchReq;
        [request setPredicate:[NSPredicate predicateWithFormat:@"chain = %@ && governanceObject == nil",self.chain.chainEntity]];
        [request setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"governanceObjectHash" ascending:TRUE]]];
        self.needsRequestsGovernanceObjectHashEntities = [[DSGovernanceObjectHashEntity fetchObjects:request] mutableCopy];
        
    }];
    return _needsRequestsGovernanceObjectHashEntities;
}

-(NSArray*)needsGovernanceObjectRequestsHashes {
    __block NSMutableArray * mArray = [NSMutableArray array];
    [self.managedObjectContext performBlockAndWait:^{
        [DSGovernanceObjectHashEntity setContext:self.managedObjectContext];
        for (DSGovernanceObjectHashEntity * governanceObjectHashEntity in self.needsRequestsGovernanceObjectHashEntities) {
            [mArray addObject:governanceObjectHashEntity.governanceObjectHash];
        }
    }];
    return [mArray copy];
}

-(NSOrderedSet*)fulfilledRequestsGovernanceObjectHashEntities {
    __block NSOrderedSet * orderedSet;
    [self.managedObjectContext performBlockAndWait:^{
        [DSGovernanceObjectHashEntity setContext:self.managedObjectContext];
        NSFetchRequest *request = DSGovernanceObjectHashEntity.fetchReq;
        [request setPredicate:[NSPredicate predicateWithFormat:@"chain = %@ && governanceObject != nil",self.chain.chainEntity]];
        [request setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"governanceObjectHash" ascending:TRUE]]];
        orderedSet = [NSOrderedSet orderedSetWithArray:[DSGovernanceObjectHashEntity fetchObjects:request]];
        
    }];
    return orderedSet;
}

-(NSOrderedSet*)fulfilledGovernanceObjectRequestsHashes {
    NSMutableOrderedSet * mOrderedSet = [NSMutableOrderedSet orderedSet];
    for (DSGovernanceObjectHashEntity * governanceObjectHashEntity in self.fulfilledRequestsGovernanceObjectHashEntities) {
        [mOrderedSet addObject:governanceObjectHashEntity.governanceObjectHash];
    }
    return [mOrderedSet copy];
}

-(void)requestGovernanceObjectsFromPeer:(DSPeer*)peer {
    if (peer.governanceRequestState == DSGovernanceRequestState_GovernanceObjectHashes) {
        peer.governanceRequestState = DSGovernanceRequestState_GovernanceObjects;
    }
    if (![self.needsRequestsGovernanceObjectHashEntities count]) {
        [self finishedGovernanceObjectSyncWithPeer:(DSPeer*)peer];
        //we are done syncing
        return;
    }
    self.requestGovernanceObjectHashEntities = [[self.needsRequestsGovernanceObjectHashEntities subarrayWithRange:NSMakeRange(0, MIN(self.needsGovernanceObjectRequestsHashes.count,REQUEST_GOVERNANCE_OBJECT_COUNT))] mutableCopy];
    NSMutableArray * requestHashes = [NSMutableArray array];
    for (DSGovernanceObjectHashEntity * governanceObjectHashEntity in self.requestGovernanceObjectHashEntities) {
        [requestHashes addObject:governanceObjectHashEntity.governanceObjectHash];
    }
    [peer sendGetdataMessageWithGovernanceObjectHashes:requestHashes];
}

- (void)peer:(DSPeer *)peer hasGovernanceObjectHashes:(NSSet*)governanceObjectHashes {
    if (peer.governanceRequestState != DSGovernanceRequestState_GovernanceObjectHashes) {
        
        if ((governanceObjectHashes.count == 1) && ([_knownGovernanceObjectHashesForExistingGovernanceObjects containsObject:[governanceObjectHashes anyObject]])) {
            return;
        }
    }
    NSLog(@"peer %@ relayed governance objects",peer.host);
    NSMutableOrderedSet * hashesToInsert = [[NSOrderedSet orderedSetWithSet:governanceObjectHashes] mutableCopy];
    NSMutableOrderedSet * hashesToUpdate = [[NSOrderedSet orderedSetWithSet:governanceObjectHashes] mutableCopy];
    NSMutableOrderedSet * hashesToQuery = [[NSOrderedSet orderedSetWithSet:governanceObjectHashes] mutableCopy];
    NSMutableOrderedSet <NSData*> * rHashes = [_knownGovernanceObjectHashes mutableCopy];
    [hashesToInsert minusOrderedSet:self.knownGovernanceObjectHashes];
    [hashesToUpdate minusOrderedSet:hashesToInsert];
    [hashesToQuery minusOrderedSet:self.fulfilledGovernanceObjectRequestsHashes];
    NSMutableOrderedSet * hashesToQueryFromInsert = [hashesToQuery mutableCopy];
    [hashesToQueryFromInsert intersectOrderedSet:hashesToInsert];
    NSMutableArray * hashEntitiesToQuery = [NSMutableArray array];
    NSMutableArray <NSData*> * rNeedsRequestsHashEntities = [self.needsRequestsGovernanceObjectHashEntities mutableCopy];
    if ([governanceObjectHashes count]) {
        [self.managedObjectContext performBlockAndWait:^{
            [DSChainEntity setContext:self.managedObjectContext];
            [DSGovernanceObjectHashEntity setContext:self.managedObjectContext];
            if ([hashesToInsert count]) {
                NSArray * novelGovernanceObjectHashEntities = [DSGovernanceObjectHashEntity governanceObjectHashEntitiesWithHashes:hashesToInsert onChain:self.chain.chainEntity];
                for (DSGovernanceObjectHashEntity * governanceObjectHashEntity in novelGovernanceObjectHashEntities) {
                    if ([hashesToQueryFromInsert containsObject:governanceObjectHashEntity.governanceObjectHash]) {
                        [hashEntitiesToQuery addObject:governanceObjectHashEntity];
                    }
                }
            }
            if ([hashesToUpdate count]) {
                [DSGovernanceObjectHashEntity updateTimestampForGovernanceObjectHashEntitiesWithGovernanceObjectHashes:hashesToUpdate onChain:self.chain.chainEntity];
            }
            [DSGovernanceObjectHashEntity saveContext];
        }];
        if ([hashesToInsert count]) {
            [rHashes addObjectsFromArray:[hashesToInsert array]];
            [rHashes sortUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
                UInt256 a = *(UInt256 *)((NSData*)obj1).bytes;
                UInt256 b = *(UInt256 *)((NSData*)obj2).bytes;
                return uint256_sup(a,b)?NSOrderedAscending:NSOrderedDescending;
            }];
        }
    }
    
    [rNeedsRequestsHashEntities addObjectsFromArray:hashEntitiesToQuery];
    [rNeedsRequestsHashEntities sortUsingComparator:^NSComparisonResult(id  _Nonnull obj1, id  _Nonnull obj2) {
        UInt256 a = *(UInt256 *)((NSData*)((DSGovernanceObjectHashEntity*)obj1).governanceObjectHash).bytes;
        UInt256 b = *(UInt256 *)((NSData*)((DSGovernanceObjectHashEntity*)obj2).governanceObjectHash).bytes;
        return uint256_sup(a,b)?NSOrderedAscending:NSOrderedDescending;
    }];
    self.knownGovernanceObjectHashes = rHashes;
    self.needsRequestsGovernanceObjectHashEntities = rNeedsRequestsHashEntities;
    NSLog(@"-> %lu - %lu",(unsigned long)[self.knownGovernanceObjectHashes count],(unsigned long)self.totalGovernanceObjectCount);
    NSUInteger countAroundNow = [self recentGovernanceObjectHashesCount];
    if ([self.knownGovernanceObjectHashes count] > self.totalGovernanceObjectCount) {
        [self.managedObjectContext performBlockAndWait:^{
            [DSGovernanceObjectHashEntity setContext:self.managedObjectContext];
            NSLog(@"countAroundNow -> %lu - %lu",(unsigned long)countAroundNow,(unsigned long)self.totalGovernanceObjectCount);
            if (countAroundNow == self.totalGovernanceObjectCount) {
                [DSGovernanceObjectHashEntity removeOldest:self.totalGovernanceObjectCount - [self.knownGovernanceObjectHashes count] onChain:self.chain.chainEntity];
                [self requestGovernanceObjectsFromPeer:peer];
            }
        }];
    } else if (countAroundNow == self.totalGovernanceObjectCount) {
        NSLog(@"%@",@"All governance object hashes received");
        //we have all hashes, let's request objects.
        [self requestGovernanceObjectsFromPeer:peer];
    }
}

- (void)peer:(DSPeer * )peer relayedGovernanceObject:(DSGovernanceObject * )governanceObject {
    NSData *governanceObjectHash = [NSData dataWithUInt256:governanceObject.governanceObjectHash];
    DSGovernanceObjectHashEntity * relatedHashEntity = nil;
    for (DSGovernanceObjectHashEntity * governanceObjectHashEntity in [self.requestGovernanceObjectHashEntities copy]) {
        if ([governanceObjectHashEntity.governanceObjectHash isEqual:governanceObjectHash]) {
            relatedHashEntity = governanceObjectHashEntity;
            [self.requestGovernanceObjectHashEntities removeObject:governanceObjectHashEntity];
            break;
        }
    }
    //NSAssert(relatedHashEntity, @"There needs to be a relatedHashEntity");
    if (!relatedHashEntity) return;
    [[DSGovernanceObjectEntity managedObject] setAttributesFromGovernanceObject:governanceObject forHashEntity:relatedHashEntity];
    [self.needsRequestsGovernanceObjectHashEntities removeObject:relatedHashEntity];
    [self.governanceObjects addObject:governanceObject];
    if (![self.requestGovernanceObjectHashEntities count]) {
        [self requestGovernanceObjectsFromPeer:peer];
        [DSGovernanceObjectEntity saveContext];
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSNotificationCenter defaultCenter] postNotificationName:DSGovernanceObjectListDidChangeNotification object:self userInfo:nil];
        });
    }
    if (![self.needsRequestsGovernanceObjectHashEntities count]) {
        [self finishedGovernanceObjectSyncWithPeer:(DSPeer*)peer];
    }
}

// MARK:- Governance Votes

-(NSUInteger)governanceVotesCount {
    NSUInteger totalVotes = 0;
    for (DSGovernanceObject * governanceObject in self.governanceObjects) {
        totalVotes += governanceObject.governanceVotesCount;
    }
    return totalVotes;
}

// MARK:- Governance ObjectDelegate

-(void)governanceObject:(DSGovernanceObject*)governanceObject didReceiveUnknownHashes:(NSSet*)hash fromPeer:(DSPeer*)peer {
    
}

// MARK:- Voting

-(void)vote:(DSGovernanceVoteOutcome)governanceVoteOutcome onGovernanceProposal:(DSGovernanceObject*)governanceObject {
    NSArray * registeredMasternodes = [self.chain registeredMasternodes];
    DSChainPeerManager * peerManager = [[DSChainManager sharedInstance] peerManagerForChain:self.chain];
    NSMutableArray * votesToRelay = [NSMutableArray array];
    for (DSMasternodeBroadcast * masternodeBroadcast in registeredMasternodes) {
        NSData * votingKey = [self.chain votingKeyForMasternodeBroadcast:masternodeBroadcast];
        DSKey * key = [DSKey keyWithPrivateKey:votingKey.base58String onChain:self.chain];
        UInt256 proposalHash = governanceObject.governanceObjectHash;
        DSUTXO masternodeUTXO = masternodeBroadcast.utxo;
        DSGovernanceVote * governanceVote = [[DSGovernanceVote alloc] initWithParentHash:proposalHash forMasternodeUTXO:masternodeUTXO voteOutcome:governanceVoteOutcome voteSignal:DSGovernanceVoteSignal_None createdAt:[[NSDate date] timeIntervalSince1970] signature:nil onChain:self.chain];
        [governanceVote signWithKey:key];
        [votesToRelay addObject:governanceVote];
    }
    [peerManager publishVotes:votesToRelay];
}

@end
