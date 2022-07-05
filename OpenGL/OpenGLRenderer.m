/*

 */

#import "OpenGLRenderer.h"
#import "AAPLMathUtilities.h"
#import <Foundation/Foundation.h>
#import <simd/simd.h>
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"


@implementation OpenGLRenderer {
    GLuint _defaultFBOName;
    CGSize _viewSize;

    // For rendering to the default framebuffer object
    GLuint _glslProgram;
    GLuint _equiRectTextureID;

    GLint _equiRectMapLoc;
    GLint _resolutionLoc;
    GLint _mouseLoc;
    GLint _timeLoc;
    GLfloat _currentTime;

    // For rendering into an offscreen FrameBuffer Object.
    GLuint _equiRectProgram;
    GLuint _lightProbeTextureID;

    GLuint _triangleVAO;

    CGSize _equiRectResolution;
    GLint _angularMapLoc;
    CGSize _tex0Resolution;

    matrix_float4x4 _projectionMatrix;
}

- (instancetype)initWithDefaultFBOName:(GLuint)defaultFBOName {

    self = [super init];
    if(self) {
        NSLog(@"%s %s", glGetString(GL_RENDERER), glGetString(GL_VERSION));

        // Build all of your objects and setup initial state here.
        _defaultFBOName = defaultFBOName;
        glGenVertexArrays(1, &_triangleVAO);
        // Must bind or buildProgramWithVertexSourceURL:withFragmentSourceURLwill crash on validation.
        glBindVertexArray(_triangleVAO);

        // Program that will render the equirectangular texture offscreen.
        NSBundle *mainBundle = [NSBundle mainBundle];
        NSURL *vertexSourceURL = [mainBundle URLForResource:@"SimpleVertexShader"
                                              withExtension:@"glsl"];
        NSURL *fragmentSourceURL = [mainBundle URLForResource:@"EquiRectFragmentShader"
                                              withExtension:@"glsl"];
        _equiRectProgram = [OpenGLRenderer buildProgramWithVertexSourceURL:vertexSourceURL
                                                     withFragmentSourceURL:fragmentSourceURL];

        printf("%u\n", _equiRectProgram);
        _angularMapLoc = glGetUniformLocation(_equiRectProgram, "angularMapImage");
        printf("angular map location:%u\n", _angularMapLoc);

        //printf("%d %d %d\n", _resolutionLoc, _mouseLoc, _timeLoc);
        _lightProbeTextureID = [self textureWithContentsOfFile:@"StPetersProbe.hdr"
                                                    resolution:&_tex0Resolution];
        printf("texture ID:%u\n", _lightProbeTextureID);
        printf("%f %f\n", _tex0Resolution.width, _tex0Resolution.height);
        // Dimensions of the EquiRectangular texture.
        _equiRectResolution.width = 2048;
        _equiRectResolution.height = 1024;
        // Capture the equirectangular texture using an offscreen framebuffer
        _equiRectTextureID = [self renderEquiRectMap:_lightProbeTextureID
                                          resolution:_equiRectResolution];
        printf("output texture ID:%u\n", _equiRectTextureID);
        glBindVertexArray(_triangleVAO);
        vertexSourceURL = [mainBundle URLForResource:@"SimpleVertexShader"
                                        withExtension:@"glsl"];
        fragmentSourceURL = [mainBundle URLForResource:@"SimpleFragmentShader"
                                        withExtension:@"glsl"];

        // Program used to texture a quad using the texture created offscreen.
        _glslProgram = [OpenGLRenderer buildProgramWithVertexSourceURL:vertexSourceURL
                                            withFragmentSourceURL:fragmentSourceURL];
        _equiRectMapLoc = glGetUniformLocation(_glslProgram, "equiRectImage");
        glBindVertexArray(0);
    }

    return self;
}

- (void) dealloc {
    glDeleteProgram(_glslProgram);
    glDeleteProgram(_equiRectProgram);
    glDeleteVertexArrays(1, &_triangleVAO);
    glDeleteTextures(1, &_lightProbeTextureID);
    glDeleteTextures(1, &_equiRectTextureID);
}


- (void)resize:(CGSize)size
{
    // Handle the resize of the draw rectangle. In particular, update the perspective projection matrix
    // with a new aspect ratio because the view orientation, layout, or size has changed.
    _viewSize = size;
    float aspect = (float)size.width / size.height;
    _projectionMatrix = matrix_perspective_right_hand_gl(65.0f * (M_PI / 180.0f),
                                                         aspect,
                                                         1.0f, 5000.0);
}

/*
 All light probe images are in HDR format.
 */
- (GLuint) textureWithContentsOfFile:(NSString *)name
                          resolution:(CGSize *)size
{
    GLuint textureID = 0;
    
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSArray<NSString *> *subStrings = [name componentsSeparatedByString:@"."];
    NSString *path = [mainBundle pathForResource:subStrings[0]
                                          ofType:subStrings[1]];
    
    GLint width;
    GLint height;
    GLint nrComponents;
    
    stbi_set_flip_vertically_on_load(true);
    GLfloat *data = stbi_loadf([path UTF8String], &width, &height, &nrComponents, 0);
    if (data) {
        size_t dataSize = width * height * nrComponents * sizeof(GLfloat);
        
        // Create and allocate space for a new buffer object
        GLuint pbo;
        glGenBuffers(1, &pbo);
        // Bind the newly-created buffer object to initialise it.
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, pbo);
        // NULL means allocate GPU memory to the PBO.
        // GL_STREAM_DRAW is a hint indicating the PBO will stream a texture upload
        glBufferData(GL_PIXEL_UNPACK_BUFFER,
                     dataSize,
                     NULL,
                     GL_STREAM_DRAW);
        
        // The following call will return a pointer to the buffer object.
        // We are going to write data to the PBO. The call will only return when
        //  the GPU finishes its work with the buffer object.
        void* mappedPtr = glMapBuffer(GL_PIXEL_UNPACK_BUFFER,
                                      GL_WRITE_ONLY);
        
        // Write data into the mapped buffer, possibly on another thread.
        // This should upload image's raw data to GPU
        memcpy(mappedPtr, data, dataSize);
        
        // After reading is complete, back on the current thread
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, pbo);
        // Release pointer to mapping buffer
        glUnmapBuffer(GL_PIXEL_UNPACK_BUFFER);
        
        glGenTextures(1, &textureID);
        glBindTexture(GL_TEXTURE_2D, textureID);
        // Read the texel data from the buffer object
        glTexImage2D(GL_TEXTURE_2D,
                     0,
                     GL_RGB16F,
                     width, height,
                     0,
                     GL_RGB,
                     GL_FLOAT,
                     NULL);     // byte offset into the buffer object's data store
        
        // Unbind and delete the buffer object
        glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0);
        glDeleteBuffers(1, &pbo);
        
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        stbi_image_free(data);
    }
    else {
        printf("Error reading hdr file\n");
        exit(1);
    }
    
    return textureID;
}

- (GLuint) renderEquiRectMap:(GLuint)textureID
                resolution:(CGSize)size {
    
    printf("%u\n", textureID);
    printf("%f %f\n", size.width, size.height);

    GLuint equiRectTextureID = 0;
    glGenTextures(1, &equiRectTextureID);

    glBindTexture(GL_TEXTURE_2D, equiRectTextureID);
    glTexImage2D(GL_TEXTURE_2D,
                 0,
                 GL_RGB16F,                 // internal format
                 size.width, size.height,   // width, height
                 0,
                 GL_RGB,                    // format
                 GL_FLOAT,                  // type
                 nil);                      // allocate space for the pixels.

    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

    GLuint captureFBO;
    GLuint captureRBO;
    glGenFramebuffers(1, &captureFBO);
    glGenRenderbuffers(1, &captureRBO);

    glBindFramebuffer(GL_FRAMEBUFFER, captureFBO);
    glBindRenderbuffer(GL_RENDERBUFFER, captureRBO);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, size.width, size.height);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, captureRBO);
    GLenum framebufferStatus = glCheckFramebufferStatus(GL_FRAMEBUFFER);

    if (framebufferStatus != GL_FRAMEBUFFER_COMPLETE) {
        printf("FrameBuffer is incomplete\n");
        GetGLError();
        return 0;
    }

    glUseProgram(_equiRectProgram);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, textureID);
    glViewport(0, 0, size.width, size.height);

    glBindFramebuffer(GL_FRAMEBUFFER, captureFBO);
    glFramebufferTexture2D(GL_FRAMEBUFFER,
                           GL_COLOR_ATTACHMENT0,
                           GL_TEXTURE_2D,
                           equiRectTextureID,
                           0);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    glBindVertexArray(_triangleVAO);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glUseProgram(0);
    glBindVertexArray(0);

    glBindFramebuffer(GL_FRAMEBUFFER, _defaultFBOName);
    return equiRectTextureID;
}



- (void) updateTime {
    _currentTime += 1/60;
}

- (void)draw {
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
  // Bind the quad vertex array object.
    glClearColor(0.5, 0.5, 0.5, 1.0);
    glViewport(0, 0,
               _viewSize.width, _viewSize.height);
    glBindVertexArray(_triangleVAO);
    glUseProgram(_glslProgram);
    glUniform1f(_timeLoc, _currentTime);
    glUniform2f(_mouseLoc, _mouseCoords.x, _mouseCoords.y);
    // We should pass the resolution of the canvas.
    glUniform2f(_resolutionLoc,
                _viewSize.width, _viewSize.height);
    glUniform1i(_angularMapLoc, 0);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, _equiRectTextureID);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glUseProgram(0);
    glBindVertexArray(0);
} // draw


+ (GLuint)buildProgramWithVertexSourceURL:(NSURL*)vertexSourceURL
                    withFragmentSourceURL:(NSURL*)fragmentSourceURL {

    NSError *error;

    NSString *vertSourceString = [[NSString alloc] initWithContentsOfURL:vertexSourceURL
                                                                encoding:NSUTF8StringEncoding
                                                                   error:&error];

    NSAssert(vertSourceString, @"Could not load vertex shader source, error: %@.", error);

    NSString *fragSourceString = [[NSString alloc] initWithContentsOfURL:fragmentSourceURL
                                                                encoding:NSUTF8StringEncoding
                                                                   error:&error];

    NSAssert(fragSourceString, @"Could not load fragment shader source, error: %@.", error);

    // Prepend the #version definition to the vertex and fragment shaders.
    float  glLanguageVersion;

#if TARGET_IOS
    sscanf((char *)glGetString(GL_SHADING_LANGUAGE_VERSION), "OpenGL ES GLSL ES %f", &glLanguageVersion);
#else
    sscanf((char *)glGetString(GL_SHADING_LANGUAGE_VERSION), "%f", &glLanguageVersion);
#endif

    // `GL_SHADING_LANGUAGE_VERSION` returns the standard version form with decimals, but the
    //  GLSL version preprocessor directive simply uses integers (e.g. 1.10 should be 110 and 1.40
    //  should be 140). You multiply the floating point number by 100 to get a proper version number
    //  for the GLSL preprocessor directive.
    GLuint version = 100 * glLanguageVersion;

    NSString *versionString = [[NSString alloc] initWithFormat:@"#version %d", version];
#if TARGET_IOS
    if ([[EAGLContext currentContext] API] == kEAGLRenderingAPIOpenGLES3)
        versionString = [versionString stringByAppendingString:@" es"];
#endif

    vertSourceString = [[NSString alloc] initWithFormat:@"%@\n%@", versionString, vertSourceString];
    fragSourceString = [[NSString alloc] initWithFormat:@"%@\n%@", versionString, fragSourceString];

    GLuint prgName;

    GLint logLength, status;

    // Create a GLSL program object.
    prgName = glCreateProgram();

    /*
     * Specify and compile a vertex shader.
     */

    GLchar *vertexSourceCString = (GLchar*)vertSourceString.UTF8String;
    GLuint vertexShader = glCreateShader(GL_VERTEX_SHADER);
    glShaderSource(vertexShader, 1, (const GLchar **)&(vertexSourceCString), NULL);
    glCompileShader(vertexShader);
    glGetShaderiv(vertexShader, GL_INFO_LOG_LENGTH, &logLength);

    if (logLength > 0) {
        GLchar *log = (GLchar*) malloc(logLength);
        glGetShaderInfoLog(vertexShader, logLength, &logLength, log);
        NSLog(@"Vertex shader compile log:\n%s.\n", log);
        free(log);
    }

    glGetShaderiv(vertexShader, GL_COMPILE_STATUS, &status);

    NSAssert(status, @"Failed to compile the vertex shader:\n%s.\n", vertexSourceCString);

    // Attach the vertex shader to the program.
    glAttachShader(prgName, vertexShader);

    // Delete the vertex shader because it's now attached to the program, which retains
    // a reference to it.
    glDeleteShader(vertexShader);

    /*
     * Specify and compile a fragment shader.
     */

    GLchar *fragSourceCString =  (GLchar*)fragSourceString.UTF8String;
    GLuint fragShader = glCreateShader(GL_FRAGMENT_SHADER);
    glShaderSource(fragShader, 1, (const GLchar **)&(fragSourceCString), NULL);
    glCompileShader(fragShader);
    glGetShaderiv(fragShader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0)
    {
        GLchar *log = (GLchar*)malloc(logLength);
        glGetShaderInfoLog(fragShader, logLength, &logLength, log);
        NSLog(@"Fragment shader compile log:\n%s.\n", log);
        free(log);
    }

    glGetShaderiv(fragShader, GL_COMPILE_STATUS, &status);

    NSAssert(status, @"Failed to compile the fragment shader:\n%s.", fragSourceCString);

    // Attach the fragment shader to the program.
    glAttachShader(prgName, fragShader);

    // Delete the fragment shader because it's now attached to the program, which retains
    // a reference to it.
    glDeleteShader(fragShader);

    /*
     * Link the program.
     */

    glLinkProgram(prgName);
    glGetProgramiv(prgName, GL_LINK_STATUS, &status);
    NSAssert(status, @"Failed to link program.");
    if (status == 0) {
        glGetProgramiv(prgName, GL_INFO_LOG_LENGTH, &logLength);
        if (logLength > 0)
        {
            GLchar *log = (GLchar*)malloc(logLength);
            glGetProgramInfoLog(prgName, logLength, &logLength, log);
            NSLog(@"Program link log:\n%s.\n", log);
            free(log);
        }
    }

    // Added code
    // Call the 2 functions below if VAOs have been bound prior to creating the shader program
    // iOS will not complain if VAOs have NOT been bound.
    glValidateProgram(prgName);
    glGetProgramiv(prgName, GL_VALIDATE_STATUS, &status);
    NSAssert(status, @"Failed to validate program.");

    if (status == 0) {
        fprintf(stderr,"Program cannot run with current OpenGL State\n");
        glGetProgramiv(prgName, GL_INFO_LOG_LENGTH, &logLength);
        if (logLength > 0) {
            GLchar *log = (GLchar*)malloc(logLength);
            glGetProgramInfoLog(prgName, logLength, &logLength, log);
            NSLog(@"Program validate log:\n%s\n", log);
            free(log);
        }
    }

    //GLint samplerLoc = glGetUniformLocation(prgName, "baseColorMap");

    //NSAssert(samplerLoc >= 0, @"No uniform location found from `baseColorMap`.");

    //glUseProgram(prgName);

    // Indicate that the diffuse texture will be bound to texture unit 0.
   // glUniform1i(samplerLoc, AAPLTextureIndexBaseColor);

    GetGLError();

    return prgName;
}

@end
