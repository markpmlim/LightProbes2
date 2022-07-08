/*
 OpenGLRenderer.h
 LightProbe2EquiRect
 
 Created by Mark Lim Pak Mun on 01/07/2022.
 Copyright © 2022 Mark Lim Pak Mun. All rights reserved.

 */

#import <Foundation/Foundation.h>
#include <CoreGraphics/CoreGraphics.h>
#import "OpenGLHeaders.h"

static const CGSize AAPLInteropTextureSize = {1024, 1024};

@interface OpenGLRenderer : NSObject {
}

- (instancetype)initWithDefaultFBOName:(GLuint)defaultFBOName;

- (void)draw;

- (void)resize:(CGSize)size;

// These properties are automatically backed by instance vars declared in
//  the implementation header.
@property CGPoint mouseCoords;
// For saving to a HDR file
@property GLuint equiRectTextureID;
@property CGSize equiRectResolution;

@end
