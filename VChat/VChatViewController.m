//
//  VChatViewController.m
//  VChat
//
//  Created by George Chen on 1/22/14.
//  Copyright (c) 2014 George Chen. All rights reserved.
//

#import "VChatViewController.h"
#import "ChatsTableViewController.h"
#import "LogInViewController.h"
#import "SignupViewController.h"

@interface VChatViewController () {
    dispatch_queue_t myQueue;
}

@property (nonatomic, strong) LogInViewController *logInViewController;
@property (strong, nonatomic) IBOutlet UITableView *myVChatTableView;

@property (strong, nonatomic) NSMutableArray *latestToUserArray;
@property (strong, nonatomic) NSMutableArray *latestFromUserArray;

@property (strong, nonatomic) NSMutableArray *allChatArray;

@property (strong, nonatomic) NSString *pathLocalToFile;
@property (strong, nonatomic) NSString *pathLocalFromFile;
@property (strong, nonatomic) NSString *pathLocalStorage;

@property (strong, nonatomic) NSIndexPath *playingIndexPath;
@property BOOL isPlaying;

- (void)logOutButtonTapAction;
- (void)initLogInController;

@end

// AVAudioPlayer *audioPlayer;

// this should be in one location, and this should use the same value.
// for now, comment it out and use it explicitly
// NSString* const RECORDING_CLASSNAME = @"UserRecording";

@implementation VChatViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
    
    self.myVChatTableView.delegate = self;
    self.myVChatTableView.dataSource = self;
    
    self.pathLocalToFile = @"/tmp/sound.caf";
    self.pathLocalFromFile = @"/tmp/localFile2";
    
    NSString *docsDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
    self.pathLocalToFile = [docsDir stringByAppendingPathComponent:@"localToFile.plist"];
    self.pathLocalFromFile = [docsDir stringByAppendingPathComponent:@"localFromFile.plist"];
    self.pathLocalStorage = [docsDir stringByAppendingPathComponent:@"localStorage.plist"];

    self.allChatArray = [[NSMutableArray alloc] init];
    
//    audioPlayer = [[AVAudioPlayer alloc]initWithContentsOfURL:[NSURL fileURLWithPath:self.pathLocalToFile] error:nil];
//    audioPlayer.delegate = self;
    
//    audioPlayer.delegate = self;
    self.isPlaying = NO;

}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
//    NSLog(@"VChatViewController : viewDidAppear");

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Sign Out" style:UIBarButtonItemStylePlain target:self action:@selector(logOutButtonTapAction)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"PlusIcon"] style:UIBarButtonItemStylePlain target:nil action:nil];
    self.title = @"Chats";
    
    [self initLogInController];
    
    PFUser *currentUser = [PFUser currentUser];
    if (!currentUser) { // No user logged in
        // Present the log in view controller
        [self presentViewController:self.logInViewController animated:YES completion:NULL];
    } else {
//        NSLog(@"user logged in");
        // update user location
        [PFGeoPoint geoPointForCurrentLocationInBackground:^(PFGeoPoint *geoPoint, NSError *error) {
            if (!error) {
                // do something with the new geoPoint
                //                NSLog(@"%f, %f", geoPoint.latitude, geoPoint.longitude);
                NSLog(@"VChatViewController: update location");
                currentUser[@"location"] = geoPoint;
                [currentUser saveInBackground];
            } 
        }];
        
        FBRequest *request = [FBRequest requestForMe];
        
        // Send request to Facebook
        [request startWithCompletionHandler:^(FBRequestConnection *connection, id result, NSError *error) {
            if (!error) {
                // result is a dictionary with the user's Facebook data
                NSDictionary *userData = (NSDictionary *)result;
                BOOL missingData = NO;
                
                NSString *facebookID = userData[@"id"];
                if (!currentUser[@"displayName"]) {
                    NSLog(@"display name missing");
                    NSString *name = userData[@"name"];
                    currentUser[@"displayName"] = name;
//                    NSLog(@"name: %@", name);
                    missingData = YES;
                }
                if (!currentUser[@"profileImage"]) {
                    NSLog(@"profile image missing");
                    NSString * pictureString = [NSString stringWithFormat:@"https://graph.facebook.com/%@/picture?type=large&return_ssl_resources=1", facebookID];
//                    NSLog(@"pictureURL: %@", pictureURL);
                    missingData = YES;
                    currentUser[@"profileImage"] = pictureString;
                }
//                NSLog(@"%@", currentUser);
                if (missingData) {
                    NSLog(@"updating facebook data for user");
                    [currentUser saveInBackground];
                }
            }
        }];
        
        // initialize the chat table w/ recent chats
        [self loadChattingDataFromRepository];
        self.title = currentUser.username;
    }
}

#pragma mark - TableView Source
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSLog(@"VChatViewController : numberOfSectionsInTableView");
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSLog(@"VChatViewController : numberOfRowsInSection = %d",self.allChatArray.count);
    return self.allChatArray.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"chatViewCell"];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"chatViewCell"];
    }
    
    NSDictionary *chat = [self.allChatArray objectAtIndex:indexPath.row];

    NSString *leftUser = [[NSString alloc] init];
    NSString *rightUser = [[NSString alloc] init];
    NSString *cellString = [[NSString alloc] init];
    NSDate *timestamp = [chat objectForKey:@"timestamp"];
    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"MM/dd HH:mm"];
    NSString *shortTime = [dateFormatter stringFromDate:timestamp];
    
    // is this a from or a to
    if ([[chat objectForKey:@"fromUser"] isEqualToString:[PFUser currentUser].username]) {
        // I sent this chat.  show who I sent it to.
        rightUser = [chat objectForKey:@"toUser"];
        cellString = [NSString stringWithFormat:@" me    ---->    %@  %@",rightUser,shortTime];
    } else {
        // I got this chat.  tell me who-sent-it.
        leftUser = [chat objectForKey:@"fromUser"];
        cellString = [NSString stringWithFormat:@"%@   ----->  me   %@",leftUser,shortTime];
    }
    
    cell.textLabel.font = [UIFont fontWithName:@"Times" size:14];
    cell.textLabel.text = cellString;
    
// [NSString stringWithFormat:@"chat with %d",indexPath.row];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSLog(@"VChatViewController : didSelectRowAtIndexPath (%d)", indexPath.row);
    
    // playback message.  if currently playing a message, then immediately ignore.
    if (self.isPlaying == YES) {
        NSLog(@"currently playing.  skipping");
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    
    NSLog(@"Playback message");
    NSDictionary *chat = [self.allChatArray objectAtIndex:indexPath.row];
//    NSURL *chatURL = [chat objectForKey:@"recordingURL"];    
//    NSLog(@"chat url is %@",chatURL);

    NSData *soundData = [chat objectForKey:@"sound"];
    NSError *outError;
//    NSURL *tempURL = [NSURL fileURLWithPath:@"/tmp/sound.caf"];
    
//    [vchat setValue:playData forKey:@"sound"];

    chatPlayer = [[AVAudioPlayer alloc] initWithData:soundData error:&outError];
//    NSLog(@"Error - %@",outError);
    
    if (chatPlayer == nil) {
        NSLog(@"Error trying to play %@.",[chat objectForKey:@"timestamp"]);
    } else {
        chatPlayer.delegate = self;
        self.playingIndexPath = indexPath;
        NSLog(@"Playing returned %d",[chatPlayer play]);
    }
    
    // now deselect this row.
    // [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
}

-(void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    NSLog(@"Playback finished");
    [self.myVChatTableView deselectRowAtIndexPath:self.playingIndexPath animated:YES];
    self.playingIndexPath = 0;
    self.isPlaying = NO;
    
}

// Pulls chatting data from repository, appends to local-data
- (void) loadChattingDataFromRepository {
    
    // Parse implementation.
    PFQuery *query = [PFQuery queryWithClassName:@"UserRecording"];
    PFUser *user = [PFUser currentUser];
    
    NSDate *lastRetrieved = user[@"lastRetrieved"];
    NSDate *currentDate = [[NSDate alloc] init];
    
    NSString *docsDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
//    self.pathLocalToFile = [docsDir stringByAppendingPathComponent:@"localToFile.plist"];
//    self.pathLocalFromFile = [docsDir stringByAppendingPathComponent:@"localFromFile.plist"];
    self.pathLocalStorage = [docsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"localStorage.%@.plist",user.username]];

    if (lastRetrieved == nil) {
        lastRetrieved = [[NSDate alloc] initWithTimeIntervalSince1970:0];
    }
    
//    [self.allChatArray removeAllObjects];
    self.allChatArray = [[NSMutableArray alloc] initWithContentsOfFile:self.pathLocalStorage];
    NSLog(@"allChatArray now contains %d rows",self.allChatArray.count);

    if (self.allChatArray == nil) {
        NSLog(@"allChatArray is nil");
        self.allChatArray = [[NSMutableArray alloc] init];
    }
    
    // find recordings sent to me
    [query whereKey:@"toUser" equalTo:user.username];
    [query whereKey:@"timestamp" greaterThan:lastRetrieved];
    
    [query findObjectsInBackgroundWithBlock:^(NSArray *objects, NSError *error) {
        self.latestToUserArray = [NSMutableArray array];
        if (objects.count > 0) {
            for (PFObject *eachObject in objects) {
                NSMutableDictionary *vchat = [[NSMutableDictionary alloc] init];

                [vchat setValue:[eachObject objectForKey:@"toUser"] forKey:@"toUser"];
                [vchat setValue:[eachObject objectForKey:@"fromUser"] forKey:@"fromUser"];
                [vchat setValue:[eachObject objectForKey:@"timestamp"] forKey:@"timestamp"];

                // link to recording...
                [vchat setValue:[eachObject objectForKey:@"recording"] forKey:@"thisFile"];
                [vchat setValue:@"NO" forKey:@"readyToPlay"];

                [self.latestToUserArray addObject:vchat];
            }
            NSLog(@"Found %d new messages to this user", self.latestToUserArray.count);
            
            [self.allChatArray addObjectsFromArray:self.latestToUserArray];
            [self arrangeData];
            [self backgroundOperation];
            [self.myVChatTableView reloadData];

        }
        else {
            NSLog(@"Found no new messages to this user");
            return;
        }
    }];
    
    // find recordings sent by me -- this should not be necessary, but should
    // be kept local.  for now, this just makes the code easier.
    
    // Do I need to do this to reset the query
    query = [PFQuery queryWithClassName:@"UserRecording"];
    
    [query whereKey:@"fromUser" equalTo:user.username];
    [query whereKey:@"timestamp" greaterThan:lastRetrieved];
    
    [query findObjectsInBackgroundWithBlock:^(NSArray *objects, NSError *error) {
        self.latestFromUserArray = [NSMutableArray array];
        if (objects.count > 0) {
            for (PFObject *eachObject in objects) {
                
                // TODO. Change this to a custom model.
                
                NSMutableDictionary *vchat = [[NSMutableDictionary alloc] init];
                
                [vchat setValue:[eachObject objectForKey:@"toUser"] forKey:@"toUser"];
                [vchat setValue:[eachObject objectForKey:@"fromUser"] forKey:@"fromUser"];
                [vchat setValue:[eachObject objectForKey:@"timestamp"] forKey:@"timestamp"];
                
                
                PFFile *thisFile = [eachObject objectForKey:@"recording"];
//                [vchat setValue:thisFile.url forKey:@"recordingURL"];
                [vchat setValue:thisFile forKey:@"thisFile"];
                [vchat setValue:@"NO" forKey:@"readyToPlay"];

                [self.latestFromUserArray addObject:vchat];
            }
            NSLog(@"Found %d new messages from this user", self.latestFromUserArray.count);
            
            // start background operation
            [self.allChatArray addObjectsFromArray:self.latestFromUserArray];
            [self arrangeData];
            [self backgroundOperation];
            // this will load the view.  actual data will still be unavailable until
            // download finish.
            [self.myVChatTableView reloadData];

        }
        else {
            NSLog(@"Found no new messages from this user");
            return;
        }
    }];
    
    // Update user's lastRetrieved date
    user[@"lastRetrieved"] = currentDate;
    [user saveInBackgroundWithBlock:^(BOOL succeeded, NSError *error) {
        if (!error) {
            NSLog(@"Updated user with lastRetrieved timestamp of %@",currentDate);
        } else {
            NSLog(@"Error while updating user: %@",error);
        }
    }];
    [self.myVChatTableView reloadData];
    
}

- (void) backgroundOperation {
    if (!myQueue) {
        myQueue = dispatch_queue_create("load.parse.data", NULL);
    }
    dispatch_async(myQueue, ^{[self downloadData];});
    NSLog(@"started downloadData");
}

- (void) downloadData {
    // go through the latestFromUserArray and fix things.
    for (NSMutableDictionary *vchat in self.allChatArray) {

        if ([[vchat objectForKey:@"readyToPlay"] isEqualToString:@"NO"]) {
            // need to download

            PFFile *thisFile = [vchat objectForKey:@"thisFile"];
            NSData *playData = [thisFile getData];
            [vchat setValue:playData forKey:@"sound"];
        
            // this allows the file to be written.
            [vchat setValue:NULL forKey:@"thisFile"];
            [vchat setValue:@"YES" forKey:@"readyToPlay"];
            NSLog(@"finished downloading %@ msg",[vchat objectForKey:@"timestamp"]);
        } else {
            NSLog(@"already downloaded %@ msg",[vchat objectForKey:@"timestamp"]);
        }
    }
    [self.allChatArray writeToFile:self.pathLocalStorage atomically:YES];
    NSLog(@"saved downloaded to %@",self.pathLocalStorage);
    
}

// Build displayable list of chats
-(void) arrangeData {
    // sort the data from oldest to newest.
    
    NSLog(@"Presort:");
    // before sort
    for (NSDictionary *eachObj in self.allChatArray) {
        NSLog(@"time: %@",[eachObj objectForKey:@"timestamp"]);
    }
    
    [self.allChatArray sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        // each object is a NSDictionary with a timestamp value
        NSDate *date1 = [obj1 objectForKey:@"timestamp"];
        NSDate *date2 = [obj2 objectForKey:@"timestamp"];
        return (NSComparisonResult)[date1 compare:date2];
    }];
    
    NSLog(@"Post sort:");
    // before sort
    for (NSDictionary *eachObj in self.allChatArray) {
        NSLog(@"time: %@",[eachObj objectForKey:@"timestamp"]);
    }

}


#pragma mark - PFLogInViewControllerDelegate

// Sent to the delegate to determine whether the log in request should be submitted to the server.
- (BOOL)logInViewController:(PFLogInViewController *)logInController shouldBeginLogInWithUsername:(NSString *)username password:(NSString *)password {
    if (username && password && username.length && password.length) {
        return YES;
    }
    
    [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Missing Information", nil) message:NSLocalizedString(@"Make sure you fill out all of the information!", nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", nil) otherButtonTitles:nil] show];
    return NO;
}

// Sent to the delegate when a PFUser is logged in.
- (void)logInViewController:(PFLogInViewController *)logInController didLogInUser:(PFUser *)user {
    NSLog(@"User successfully logs in");
    [self dismissViewControllerAnimated:YES completion:NULL];
}

// Sent to the delegate when the log in attempt fails.
- (void)logInViewController:(PFLogInViewController *)logInController didFailToLogInWithError:(NSError *)error {
    NSLog(@"Failed to log in...");
}

// Sent to the delegate when the log in screen is dismissed.
- (void)logInViewControllerDidCancelLogIn:(PFLogInViewController *)logInController {
    NSLog(@"User dismissed the logInViewController");
    //[self.navigationController popViewControllerAnimated:YES];
}


#pragma mark - PFSignUpViewControllerDelegate

// Sent to the delegate to determine whether the sign up request should be submitted to the server.
- (BOOL)signUpViewController:(PFSignUpViewController *)signUpController shouldBeginSignUp:(NSDictionary *)info {
    BOOL informationComplete = YES;
    for (id key in info) {
        NSString *field = [info objectForKey:key];
        if (!field || field.length == 0) {
            informationComplete = NO;
            break;
        }
    }
    
    if (!informationComplete) {
        [[[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Missing Information", nil) message:NSLocalizedString(@"Make sure you fill out all of the information!", nil) delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", nil) otherButtonTitles:nil] show];
    }
    
    return informationComplete;
}

// Sent to the delegate when a PFUser is signed up.
- (void)signUpViewController:(PFSignUpViewController *)signUpController didSignUpUser:(PFUser *)user {
    [self dismissViewControllerAnimated:YES completion:NULL];
}

// Sent to the delegate when the sign up attempt fails.
- (void)signUpViewController:(PFSignUpViewController *)signUpController didFailToSignUpWithError:(NSError *)error {
    NSLog(@"Failed to sign up...");
}

// Sent to the delegate when the sign up screen is dismissed.
- (void)signUpViewControllerDidCancelSignUp:(PFSignUpViewController *)signUpController {
    NSLog(@"User dismissed the signUpViewController");
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)initLogInController {
    // Create the log in view controller
    self.logInViewController = [[LogInViewController alloc] init];
    [self.logInViewController setDelegate:self]; // Set ourselves as the delegate
    [self.logInViewController setFacebookPermissions:[NSArray arrayWithObjects:@"friends_about_me", nil]];
    [self.logInViewController setFields:PFLogInFieldsUsernameAndPassword
     | PFLogInFieldsFacebook
     | PFLogInFieldsSignUpButton];
    
    // Create the sign up view controller
    SignupViewController *signUpViewController = [[SignupViewController alloc] init];
    [signUpViewController setDelegate:self]; // Set ourselves as the delegate
    
    // Assign our sign up controller to be displayed from the login controller
    [self.logInViewController setSignUpController:signUpViewController];
}

- (void)logOutButtonTapAction {
    NSLog(@"User logged out");
    [PFUser logOut];
    if (self.logInViewController) {
        [self presentViewController:self.logInViewController animated:YES completion:NULL];

    } else {
        NSLog(@"loginviewcontroller is nil");
    }
}
@end
