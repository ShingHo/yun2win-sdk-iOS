//
//  LoginViewController.m
//  API
//
//  Created by ShingHo on 16/1/18.
//  Copyright © 2016年 SayGeronimo. All rights reserved.
//

#import "LoginViewController.h"
#import "RegisterViewController.h"
#import "MainViewController.h"
#import "Y2WUser.h"
#import "Y2WCurrentUser.h"
#import "Y2WUsers.h"
#import "EmojiManage.h"
@interface LoginViewController ()<UITextFieldDelegate,LoginViewControllerDelegate>

@property (weak, nonatomic) IBOutlet UITextField *accountTextField;

@property (weak, nonatomic) IBOutlet UITextField *psdTextField;

@property (weak, nonatomic) IBOutlet UIButton *loginButton;

@end


@implementation LoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.navigationBar.hidden = YES;
    
    self.accountTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.accountTextField.delegate = self;
    self.psdTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.psdTextField.secureTextEntry = YES;
    self.psdTextField.delegate = self;
    [self.loginButton addTarget:self action:@selector(login) forControlEvents:UIControlEventTouchUpInside];
    
    self.accountTextField.text = @"a";
    self.psdTextField.text = @"a";
//    [self login];
}

- (IBAction)registration:(UIButton *)sender {

    RegisterViewController *re = [[RegisterViewController alloc]initWithNibName:@"RegisterViewController" bundle:nil];
    re.delegate = self;
    [self.navigationController pushViewController:re animated:YES];
}


- (void)login
{
    [self loginWithAccount:self.accountTextField.text password:self.psdTextField.text];
}


- (void)loginWithAccount:(NSString *)account password:(NSString *)password {
    
    [[Y2WUsers getInstance].remote loginWithAccount:account password:password success:^(Y2WCurrentUser *currentUser) {
        
        
        [[Y2WUsers getInstance].getCurrentUser.remote syncIMTokenDidCompletion:^(NSError *error) {
            
        }];
        [[EmojiManage shareEmoji] syncEmoji];
        
        MainViewController *main = [[MainViewController alloc]init];
        [UIApplication sharedApplication].keyWindow.rootViewController = main;
        
    } failure:^(NSError *error) {
        
        [UIAlertView showTitle:nil message:[[NSString alloc] initWithData:error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey] encoding:NSUTF8StringEncoding]];
    }];
}




#pragma mark - TextFieldDelegate

-(void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    [self.view endEditing:YES];
}

-(BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self.accountTextField resignFirstResponder];
    [self.psdTextField resignFirstResponder];
    return YES;
}

@end
