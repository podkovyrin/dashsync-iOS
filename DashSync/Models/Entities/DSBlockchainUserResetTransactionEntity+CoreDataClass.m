//
//  DSBlockchainUserResetTransactionEntity+CoreDataClass.m
//  DashSync
//
//  Created by Sam Westrich on 8/29/18.
//
//

#import "DSBlockchainUserResetTransactionEntity+CoreDataClass.h"
#import "DSBlockchainUserResetTransaction.h"
#import "DSTransactionFactory.h"
#import "NSData+Bitcoin.h"

@implementation DSBlockchainUserResetTransactionEntity

- (instancetype)setAttributesFromTransaction:(DSTransaction *)tx
{
    [self.managedObjectContext performBlockAndWait:^{
        [super setAttributesFromTransaction:tx];
        DSBlockchainUserResetTransaction * blockchainUserResetTransaction = (DSBlockchainUserResetTransaction*)tx;
        self.specialTransactionVersion = blockchainUserResetTransaction.blockchainUserResetTransactionVersion;
        self.registrationTransactionHash = [NSData dataWithUInt256:blockchainUserResetTransaction.registrationTransactionHash];
        self.creditFee = blockchainUserResetTransaction.creditFee;
        self.oldPubKeyPayloadSignature = blockchainUserResetTransaction.oldPublicKeyPayloadSignature;
        self.replacementPublicKey = [NSData dataWithUInt160:blockchainUserResetTransaction.replacementPublicKeyHash];
        
    }];
    
    return self;
}

- (DSTransaction *)transactionForChain:(DSChain*)chain
{
    DSBlockchainUserResetTransaction * transaction = (DSBlockchainUserResetTransaction *)[super transactionForChain:chain];
    transaction.type = DSTransactionType_SubscriptionTopUp;
    [self.managedObjectContext performBlockAndWait:^{
        transaction.blockchainUserResetTransactionVersion = self.specialTransactionVersion;
        transaction.registrationTransactionHash = self.registrationTransactionHash.UInt256;
        transaction.creditFee = self.creditFee;
        transaction.oldPublicKeyPayloadSignature = self.oldPubKeyPayloadSignature;
        transaction.replacementPublicKeyHash = self.replacementPublicKey.UInt160;
    }];
    
    return transaction;
}

-(Class)transactionClass {
    return [DSBlockchainUserResetTransaction class];
}

@end
