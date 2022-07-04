/*

 */
#import "OpenGLViewController.h"
#import "OpenGLRenderer.h"
#import "AAPLMathUtilities.h"
#import <CoreImage/CoreImage.h>
#define STB_IMAGE_WRITE_IMPLEMENTATION
#import "stb_image_write.h"


#ifdef TARGET_MACOS
#define PlatformGLContext NSOpenGLContext
#else // if!(TARGET_IOS || TARGET_TVOS)
#define PlatformGLContext EAGLContext
#endif // !(TARGET_IOS || TARGET_TVOS)

@implementation OpenGLView

#if defined(TARGET_IOS) || defined(TARGET_TVOS)
// Implement this to override the default layer class (which is [CALayer class]).
// We do this so that our view will be backed by a layer that is capable of OpenGL ES rendering.
+ (Class) layerClass
{
    return [CAEAGLLayer class];
}
#endif

@end

@implementation OpenGLViewController
{
    // Instance vars
    OpenGLView *_view;
    OpenGLRenderer *_openGLRenderer;
    PlatformGLContext *_context;
    GLuint _defaultFBOName;
    CIContext *glCIContext;

#if defined(TARGET_IOS) || defined(TARGET_TVOS)
    GLuint _colorRenderbuffer;
    GLuint _depthRenderbuffer;
    CADisplayLink *_displayLink;
#else
    CVDisplayLinkRef _displayLink;
#endif
}

// Common method for iOS and macOS ports
- (void)viewDidLoad
{
    [super viewDidLoad];

    _view = (OpenGLView *)self.view;

    [self prepareView];

    [self makeCurrentContext];

    _openGLRenderer = [[OpenGLRenderer alloc] initWithDefaultFBOName:_defaultFBOName];

    if (!_openGLRenderer) {
        NSLog(@"OpenGL renderer failed initialization.");
        return;
    }

    [_openGLRenderer resize:self.drawableSize];
}

#if TARGET_MACOS

- (CGSize) drawableSize
{
    CGSize viewSizePoints = _view.bounds.size;

    CGSize viewSizePixels = [_view convertSizeToBacking:viewSizePoints];

    return viewSizePixels;
}

- (void)makeCurrentContext
{
    [_context makeCurrentContext];
}

static CVReturn OpenGLDisplayLinkCallback(CVDisplayLinkRef displayLink,
                                          const CVTimeStamp* now,
                                          const CVTimeStamp* outputTime,
                                          CVOptionFlags flagsIn,
                                          CVOptionFlags* flagsOut,
                                          void* displayLinkContext)
{
    OpenGLViewController *viewController = (__bridge OpenGLViewController*)displayLinkContext;

    [viewController draw];
    return YES;
}

// The CVDisplayLink object will call this method whenever a frame update is necessary.
- (void)draw
{
    CGLLockContext(_context.CGLContextObj);

    [_context makeCurrentContext];

    [_openGLRenderer draw];

    CGLFlushDrawable(_context.CGLContextObj);
    CGLUnlockContext(_context.CGLContextObj);
}

- (void)prepareView
{
    NSOpenGLPixelFormatAttribute attrs[] =
    {
        NSOpenGLPFAColorSize, 32,
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFADepthSize, 24,
        NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion3_2Core,
        0
    };

    NSOpenGLPixelFormat *pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];

    NSAssert(pixelFormat, @"No OpenGL pixel format.");

    // We can't share the view's initial NSOpenGLContext with the new one.
    _context = [[NSOpenGLContext alloc] initWithFormat:pixelFormat
                                          shareContext:nil];

    // We can't call CGLGetCurrentContext() to pass the CGLContext to
    //   CGLLockContext() because a nil is returned by the latter call.
    CGLLockContext(_context.CGLContextObj);

    // This call should set the current CGLContextObj to a non-nil.
    [_context makeCurrentContext];

    CGLUnlockContext(_context.CGLContextObj);

    glEnable(GL_FRAMEBUFFER_SRGB);
    _view.pixelFormat = pixelFormat;
    _view.openGLContext = _context;
    _view.wantsBestResolutionOpenGLSurface = YES;
    // This should confirm that the current CGLContextObj is the
    //  identical to that of the view's CGLContextObj
    NSLog(@"Current CGLContextObj: %p", CGLGetCurrentContext());
    NSLog(@"view's CGLContextObj: %p", _context.CGLContextObj);

    // Ref. Apple's documentation of the CIContext method:
    //  contextWithCGLContext:pixelFormat:colorSpace:options:
    // The Core Image Guide for processing images says:
    // "It’s important that the pixel format for the context includes the NSOpenGLPFANoRecovery constant as an
    // attribute. Otherwise Core Image may not be able to create another context that shares textures with this one."
    // Create the pixel format attributes...
    const NSOpenGLPixelFormatAttribute attr[] = {
        NSOpenGLPFAAccelerated,
        NSOpenGLPFANoRecovery,
        NSOpenGLPFAColorSize, 32,
        0
    };
    
    /*
     Core Image manages its own internal OpenGL context that shares resources with the
     OpenGL context you specify. To enable resource sharing, use the following code:
     */
    NSOpenGLPixelFormat *pf = [[NSOpenGLPixelFormat alloc] initWithAttributes:(void *)&attr];
    
    // Is the CIContext based on the same CGLContext used to create the texture?
    // Has the CGLContext been set properly? If yes, was it the one that was used to render the texture?
    // cs is a pointer to a struct named "CGColorSpace"
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    NSDictionary<NSString *, id> *options = @{kCIContextWorkingFormat : [NSNumber numberWithInt:kCIFormatRGBAh]};
    // A CIContext object is required to render CIImage objects.
    // Since CIContext objects are immutable, an instance of CIContext should
    //   created here so that it can be re-used.
    // Setup the core image context, tied to the Open GL context:
    glCIContext = [CIContext contextWithCGLContext:CGLGetCurrentContext()
                                       pixelFormat:[pf CGLPixelFormatObj]
                                        colorSpace:cs
                                           options:options];
    // Check: an instance is created successfully.
    NSLog(@"CIContext: %@", glCIContext);
    // To check that the 2 CGLContextObj objects are identical.
    //NSLog(@"Current CGLContextObj: %p", CGLGetCurrentContext());
    //NSLog(@"CGLContextObj: %p", _context.CGLContextObj);

    // The default framebuffer object (FBO) is 0 on macOS, because it uses
    //  a traditional OpenGL pixel format model. Might be different on other OSes.
    _defaultFBOName = 0;

    CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);

    // Set the renderer output callback function.
    CVDisplayLinkSetOutputCallback(_displayLink,
                                   &OpenGLDisplayLinkCallback, (__bridge void*)self);

    CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(_displayLink,
                                                      _context.CGLContextObj,
                                                      pixelFormat.CGLPixelFormatObj);
}

- (void)viewDidLayout
{
    CGLLockContext(_context.CGLContextObj);

    NSSize viewSizePoints = _view.bounds.size;

    NSSize viewSizePixels = [_view convertSizeToBacking:viewSizePoints];

    [self makeCurrentContext];

    [_openGLRenderer resize:viewSizePixels];

    CGLUnlockContext(_context.CGLContextObj);

    if(!CVDisplayLinkIsRunning(_displayLink))
    {
        CVDisplayLinkStart(_displayLink);
    }
}

- (void) viewDidAppear {
    [_view.window makeFirstResponder:self];
}


- (void) viewWillDisappear
{
    CVDisplayLinkStop(_displayLink);
}

- (void)dealloc
{
    CVDisplayLinkStop(_displayLink);

    CVDisplayLinkRelease(_displayLink);
}

// Override inherited method
- (BOOL) saveTexture:(GLuint)textureName
                size:(CGSize)size
               toURL:(NSURL *)fileURL
               error:(NSError **)error {
    
    NSLog(@"texture ID:%u URL:%@", textureName, fileURL);
    printf("width: %f height:%f\n",
           size.width, size.height);
 
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    NSDictionary *options = @{ kCIImageTextureFormat : [NSNumber numberWithInt:kCIFormatRGBAh],
                               kCIImageTextureTarget : [NSNumber numberWithInt:GL_TEXTURE_2D],
                               kCIImageColorSpace    : (__bridge id)cs
                               //kCIImageColorSpace    : [NSNull null]
                               };

    glBindTexture(GL_TEXTURE_2D, textureName);

    // According to documentation, this method should create the image source
    //  with data supplied by the OpenGL texture.
    CIImage* ciImage = [CIImage imageWithTexture:textureName
                                            size:size
                                         flipped:NO
                                         options:options];

    // Try adding a fence? Nope, doesn't work.
    GLsync sync = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
    GLenum value = glClientWaitSync(sync, GL_SYNC_FLUSH_COMMANDS_BIT, 1000000);
    printf("glClientWaitSync value:0x%0X\n", value);
    NSLog(@"CIImage: %@", ciImage);
    CGRect cgRect = ciImage.extent;
    // Do we need to perform a render to the CIImage since the CIImage object? - yes
    // A CIImage object has all the information necessary to produce an image,
    //  but Core Image doesn’t actually render an image until it is told to do so.
    CGAffineTransform transform = CGAffineTransformIdentity;
    transform = CGAffineTransformScale(transform, 1.0, 1.0);
    ciImage = [ciImage imageByApplyingTransform:transform];
    NSLog(@"CIImage: %@", ciImage);
    // Check if we are using the CIContext object created earlier for re-use.
    NSLog(@"CIContext: %@", glCIContext);

    // Adding this also doesn't work.
    CGRect inRect  = CGRectMake(0, 0, size.width, size.height);
    CGRect outRect = CGRectMake(0, 0, size.width, size.height);
    [glCIContext drawImage:ciImage
                    inRect:inRect
                  fromRect:outRect];

    // The call should render the output image
    // We must pass kCIFormatRGBAh as the "format" parameter
    // The call below creates a Quartz 2D image from the Core Image object
    CGImageRef cgImage = [glCIContext createCGImage:ciImage
                                           fromRect:cgRect
                                             format:kCIFormatRGBAh
                                         colorSpace:cs];
    NSLog(@"%@", cgImage);

    CGColorSpaceRelease(cs);

    // CIImage can be used to initialize an instance of NSBitmapImageRep
    NSBitmapImageRep* bir = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    // bitmapFormat should be 4 indicating FP format.
    NSLog(@"bitmap Format:%lu", (unsigned long)bir.bitmapFormat);
    size_t width = bir.pixelsWide;
    size_t height = bir.pixelsHigh;
    NSLog(@"image width:%ld image height:%ld", width, height);
    // It seems the raw data of the CGImage object is made up of pixels,
    //  which have 4 components, each component being 16 bits giving
    //  a total size of 64 bits per pixel.
    NSLog(@"%ld %ld %ld", bir.samplesPerPixel, bir.bitsPerSample, bir.bitsPerPixel);
    if (bir.isPlanar) {
        NSLog(@"Planar configuration: there are %ld planes", bir.numberOfPlanes);
    }
    else {
        NSLog(@"Meshed configuration: there should be one plane:%ld", bir.numberOfPlanes);
    }
    NSLog(@"%ld %ld", bir.bytesPerRow, bir.bytesPerPlane);

    uint16 *srcData = (uint16 *)bir.bitmapData;     // all zeros???
    NSLog(@"Pointer to Src Data:%p\n", srcData);

    if (![fileURL.absoluteString containsString:@"."]) {
        if (error != NULL) {
            *error = [[NSError alloc] initWithDomain:@"File write failure."
                                                code:0xdeadbeef
                                            userInfo:@{NSLocalizedDescriptionKey : @"No file extension provided."}];
        }
        return NO;
    }

    NSArray *subStrings = [fileURL.absoluteString componentsSeparatedByString:@"."];

    if ([subStrings[1] caseInsensitiveCompare:@"hdr"] != NSOrderedSame) {
        if (error != NULL) {
            *error = [[NSError alloc] initWithDomain:@"File write failure."
                                                code:0xdeadbeef
                                            userInfo:@{NSLocalizedDescriptionKey : @"Only (.hdr) files are supported."}];
        }
        return NO;
    }
    const char *filePath = [fileURL fileSystemRepresentation];
    printf("%s\n", filePath);

    if (srcData == NULL) {
        if (error != NULL) {
            *error = [[NSError alloc] initWithDomain:@"File write failure."
                                                code:0xdeadbeef
                                            userInfo:@{NSLocalizedDescriptionKey : @"Unable to access raw image data."}];
        }
        CGImageRelease(cgImage);  // Remember to release the CGImage
        return NO;
    }

    // This should match bir.samplesPerPixel
    const size_t kSrcChannelCount = 4;
    const size_t kBitsPerByte = 8;
    // This should matched bir.bitsPerPixel
    // bir.bitsPerSample should be 16 which is the size of uint16_t
    const size_t kExpectedBitsPerPixel = sizeof(uint16_t) * kSrcChannelCount * kBitsPerByte;
    printf("Expected bits per pixel (bpp):%lu\n", kExpectedBitsPerPixel);

    const size_t kPixelCount = size.width * size.height;
    printf("total # of pixels:%lu\n", kPixelCount);
    const size_t kDstChannelCount = 3;
    const size_t kDstSize = kPixelCount * sizeof(GLfloat) * kDstChannelCount;

    GLfloat *dstData = (GLfloat *)malloc(kDstSize);
    printf("Total Size:%lu\n", kDstSize);
     for (size_t pixelIdx = 0; pixelIdx < kPixelCount; ++pixelIdx) {
        const uint16_t *currSrc = srcData + (pixelIdx * kSrcChannelCount);
        GLfloat *currDst = dstData + (pixelIdx * kDstChannelCount);

        currDst[0] = float32_from_float16(currSrc[0]);
        currDst[1] = float32_from_float16(currSrc[1]);
        currDst[2] = float32_from_float16(currSrc[2]);
    }

    int err = stbi_write_hdr(filePath,
                             (int)size.width, (int)size.height,
                             3,
                             dstData);

    CGImageRelease(cgImage);  // Remember to release the CGImage
    free(dstData);

    if (err == 0) {
        if (error != NULL) {
            *error = [[NSError alloc] initWithDomain:@"File write failure."
                                                code:0xdeadbeef
                                            userInfo:@{NSLocalizedDescriptionKey : @"Unable to write hdr file."}];
        }
        return NO;
    }
    return YES;
}

// Override inherited method
- (void) keyDown:(NSEvent *)event {
    if( [[event characters] length] ) {
        unichar nKey = [[event characters] characterAtIndex:0];
        if (nKey == 115) {
            GLuint textureID = _openGLRenderer.equiRectTextureID;
            if (textureID != 0) {
                NSSavePanel *sp = [NSSavePanel savePanel];
                sp.canCreateDirectories = YES;
                sp.nameFieldStringValue = @"image";
                NSModalResponse buttonID = [sp runModal];
                if (buttonID == NSModalResponseOK) {
                    CGSize resolution = _openGLRenderer.equiRectResolution;
                    NSString* fileName = sp.nameFieldStringValue;
                    if (![fileName containsString:@"."]) {
                        fileName = [fileName stringByAppendingPathExtension:@"hdr"];
                    }
                    NSURL* folderURL = sp.directoryURL;
                    NSURL* fileURL = [folderURL URLByAppendingPathComponent:fileName];
                    NSError *err = nil;
                    [self saveTexture:textureID
                                 size:resolution
                                toURL:fileURL
                                error:&err];
                    if (err != nil) {
                        NSLog(@"%@", err);
                    }
                }
            }
        }
        else {
            [super keyDown:event];
        }
    }
}

- (void) passMouseCoords: (NSPoint)point {
    _openGLRenderer.mouseCoords = point;
}


- (void) mouseDown:(NSEvent *)event {
    NSPoint mousePoint = [self.view convertPoint:event.locationInWindow
                                        fromView:nil];

    _openGLRenderer.mouseCoords = mousePoint;
}

- (void) mouseDragged:(NSEvent *)event {
    NSPoint mousePoint = [self.view convertPoint:event.locationInWindow
                                        fromView:nil];
    
    _openGLRenderer.mouseCoords = mousePoint;

}
#else

// ===== iOS specific code. =====

// sender is an instance of CADisplayLink
- (void)draw:(id)sender
{
    [EAGLContext setCurrentContext:_context];
    [_openGLRenderer draw];

    glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderbuffer);
    [_context presentRenderbuffer:GL_RENDERBUFFER];
}

- (void)makeCurrentContext
{
    [EAGLContext setCurrentContext:_context];
}

- (void)prepareView
{
    CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.view.layer;

    eaglLayer.drawableProperties = @{kEAGLDrawablePropertyRetainedBacking : @NO,
                                     kEAGLDrawablePropertyColorFormat     : kEAGLColorFormatSRGBA8 };
    eaglLayer.opaque = YES;

    _context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];

    if (!_context || ![EAGLContext setCurrentContext:_context])
    {
        NSLog(@"Could not create an OpenGL ES context.");
        return;
    }

    [self makeCurrentContext];

    self.view.contentScaleFactor = [UIScreen mainScreen].nativeScale;

    // In iOS & tvOS, you must create an FBO and attach a drawable texture
    // allocated by Core Animation to use as the default FBO for a view.
    glGenFramebuffers(1, &_defaultFBOName);
    glBindFramebuffer(GL_FRAMEBUFFER, _defaultFBOName);

    glGenRenderbuffers(1, &_colorRenderbuffer);

    glGenRenderbuffers(1, &_depthRenderbuffer);

    [self resizeDrawable];

    glFramebufferRenderbuffer(GL_FRAMEBUFFER,
                              GL_COLOR_ATTACHMENT0,
                              GL_RENDERBUFFER,
                              _colorRenderbuffer);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER,
                              GL_DEPTH_ATTACHMENT,
                              GL_RENDERBUFFER,
                              _depthRenderbuffer);

    // Create the display link so you render at 60 frames per second (FPS).
    _displayLink = [CADisplayLink displayLinkWithTarget:self
                                               selector:@selector(draw:)];

    _displayLink.preferredFramesPerSecond = 60;

    // Set the display link to run on the default run loop (and the main thread).
    [_displayLink addToRunLoop:[NSRunLoop currentRunLoop]
                       forMode:NSDefaultRunLoopMode];
}

- (CGSize)drawableSize
{
    GLint backingWidth, backingHeight;
    glBindRenderbuffer(GL_RENDERBUFFER, _colorRenderbuffer);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &backingHeight);
    CGSize drawableSize = {backingWidth, backingHeight};
    return drawableSize;
}

- (void)resizeDrawable
{
    [self makeCurrentContext];

    // First, ensure that you have a render buffer.
    assert(_colorRenderbuffer != 0);

    glBindRenderbuffer(GL_RENDERBUFFER,
                       _colorRenderbuffer);
    // This call associates the storage for the current render buffer with the EAGLDrawable (our CAEAGLLayer)
    // allowing us to draw into a buffer that will later be rendered to screen wherever the
    // layer is (which corresponds with our view).
    [_context renderbufferStorage:GL_RENDERBUFFER
                     fromDrawable:(id<EAGLDrawable>)_view.layer];

    CGSize drawableSize = [self drawableSize];

    glBindRenderbuffer(GL_RENDERBUFFER,
                       _depthRenderbuffer);

    glRenderbufferStorage(GL_RENDERBUFFER,
                          GL_DEPTH_COMPONENT24,
                          drawableSize.width, drawableSize.height);

    GetGLError();
    // The custom render object is nil on first call to this method.
    [_openGLRenderer resize:self.drawableSize];
}

// overridden method
- (void)viewDidLayoutSubviews
{
    [self resizeDrawable];
}

// overridden method
- (void)viewDidAppear:(BOOL)animated
{
    [self resizeDrawable];
}


#endif
@end
