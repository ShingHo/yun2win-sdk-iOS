//
//  UIImage+Color.m
//  API
//
//  Created by QS on 16/3/21.
//  Copyright © 2016年 SayGeronimo. All rights reserved.
//

#import "UIImage+Color.h"

@interface UIColorCache : NSObject
@property (nonatomic,strong)    NSCache *colorImageCache;
@end

@implementation UIColorCache
+ (instancetype)sharedCache
{
    static UIColorCache *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[UIColorCache alloc] init];
    });
    return instance;
}

- (instancetype)init
{
    if (self = [super init])
    {
        _colorImageCache = [[NSCache alloc] init];
    }
    return self;
}

- (UIImage *)image:(UIColor *)color
{
    return color ? [_colorImageCache objectForKey:[color description]] : nil;
}

- (void)setImage:(UIImage *)image
        forColor:(UIColor *)color
{
    [_colorImageCache setObject:image
                         forKey:[color description]];
}
@end



@implementation UIImage (Color)

+ (UIImage *)imageWithUIColor:(UIColor *)color {
    if (color == nil)
    {
        assert(0);
        return nil;
    }
    UIImage *image = [[UIColorCache sharedCache] image:color];
    if (image == nil)
    {
        CGFloat alphaChannel;
        [color getRed:NULL green:NULL blue:NULL alpha:&alphaChannel];
        BOOL opaqueImage = (alphaChannel == 1.0);
        CGRect rect = CGRectMake(0, 0, 1, 1);
        UIGraphicsBeginImageContextWithOptions(rect.size, opaqueImage, [UIScreen mainScreen].scale);
        [color setFill];
        UIRectFill(rect);
        image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        [[UIColorCache sharedCache] setImage:image
                                    forColor:color];
    }
    return image;
}


@end
