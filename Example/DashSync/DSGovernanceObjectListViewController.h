//
//  DSGovernanceObjectListViewController.h
//  DashSync_Example
//
//  Created by Sam Westrich on 6/15/18.
//  Copyright © 2018 Andrew Podkovyrin. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <DashSync/DashSync.h>

@interface DSGovernanceObjectListViewController : UITableViewController<NSFetchedResultsControllerDelegate,UISearchBarDelegate>

@property (nonatomic,strong) DSChainPeerManager * chainPeerManager;

@end
