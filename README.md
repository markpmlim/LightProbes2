### Light Probe Image to  EquiRectangular Image

<br />
<br />
<br />

As proof of concept, this program can convert Light Probe Images to EquiRectangular Images directly. It is not neccesary to produce an intermediate cubemap texture and then map this to an EquiRectangular texture.

<br />
<br />

An EquiRectangular projection of a scene is common. Light probe images, on the other hand, are specially formatted images which capture the illumination of a real-world scene. These images are High Dynamic Range images where each colour component is represented by a 32-bit floating point number.

On his website, Paul Debevec, a researcher at the University of Southern California, has detailed a number of steps for developers to follow in order to develop such images. He has also provided a number of such images that can be used as environment maps.

The Mathematics of mapping a Light Probe image to another format e.g. vertical cross cubemaps is simple. Basically, it requires a 3D vector to be generated and transformed to a pair of texture coordinates which is then used to access the 2D Light Probe image. This project attempts to map a Light Probe image to an EquiRectangular image.

<br />
<br />

This process starts with the vertex shader, *SimpleVertexShader.glsl* processing data associated with a vertex of a quad; eventually, the OpenGL's Rasterizer will receive the input primitives and generate fragments to be further processed by a fragment shader. In this program, the fragment shader *EquiRectFragmentShader.glsl* receives the interpolated values of a pair of texture coordinates which are transfomed into a 3D normalized vector using the equation:

```glsl

    vec3 dir = vec3(cos(phi) * sin(theta),
                    sin(phi),
                    cos(phi) * cos(theta));

```

Then the following equations:

```glsl

    float r = (0.5/M_PI) * acos(dir.z)/sqrt(dir.x*dir.x + dir.y*dir.y);

    uv = vec2(0.5 + r*dir.x, 0.5 + r*dir.y);

```

will convert the direction vector *dir* into a pair of texture coordinates which is used to access the Light Probe image.


The output using the 2 light probes, UffizProbe.hdr and StPetersProbe.hdr are shown below.


Expected output using UffiziProbe.hdr:

<p align="center">
  <img src="./UffiziPlaza.png">
</p>

**<p align="center" >Uffizi Plaza</p>**

Expected output using StPetersProbe.hdr:


<p align="center">
  <img src="./StPetersBasilica.png">
</p>


**<p align="center" >St Peter's Basilica</p>**

<br />
<br />


The interesting part of this project is an attempt to use Apple's classes **CIContext, CIImage, CGImage** etc. to write out an *.hdr* file.

Adopting a workflow that is similar to the *Cubemap2EquiRect* demo in the Cubemapping Project, an instance of *CIContext* is created with the call:

```objective-c

    CIContext *giCIContext = [CIContext contextWithCGLContext:CGLGetCurrentContext()
                                                  pixelFormat:[pf CGLPixelFormatObj]
                                                   colorSpace:cs
                                                      options:nil];

```

This is done early during initial setup of the program. According to Apple's documentation, *CIContext* objects are immutable and can be called from any thread. And these objects are expensive to create. There is a condition stipulated: Core Image objects must share resources with the OpenGL context the program is using.


The program will transfer control to the initialization method of the class *OpenGLRenderer*. As part of the renderer's initialization process, the method loads and instantiates a texture from the Light Probe image. Before returning control to the *OpenGLViewController* object, an offscreen *FBO* is created to capture an EquiRectangular texture which will be displayed during a per-frame update. See the *draw* methods of the *OpenGLViewController* and *OpenGLRenderer* classes.


When the user presses *s* to output the texture as an *.hdr* file, the *OpenGLViewController* method

```objective-c

    saveTexture:size:toURL:error:

```

will instantiated a *CIImage* object with the call:

```objective-c

    CIImage* ciImage = [CIImage imageWithTexture:textureName
                                            size:size
                                         flipped:NO
                                         options:options];


```

According to Apple's docs, data should be supplied by the OpenGL texture with the texture ID, *textureName*. Creating an instance of *CGImage* (Core Graphics Image) from the *CIImage* (Core Image) object is trivial.

```objective-c

    CGImageRef cgImage = [glCIContext createCGImage:ciImage
                                           fromRect:cgRect
                                             format:kCIFormatRGBAh
                                         colorSpace:[ciImage colorSpace]];

```

The following call should create an instance of *NSBitmapImageRep* whose *bitmapData* is a pointer to the raw data of the bitmap image representation.


```objective-c

    NSBitmapImageRep* bir = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];


```

The following properties of the NSBitmapImageRep object will provide information about the image to be written out:


*bitmapFormat, pixelsWide, pixelsHigh, samplesPerPixel, bitsPerSample, bitsPerPixel, numberOfPlanes, bytesPerRow* and *bytesPerPlane*.

<br />

The  *bitmapData* property of an *NSBitmapImageRep* object, should be a pointer to the a 16-bit bitmap data which must be converted to a 32-bit bitmap and then pass to the *stbi_write_hdr* function.

However, the output image is black indicating the bitmapData probably consists entirely of zeroes; the pointer to the 16-bit bitmap is not NIL.

<br />
<br />
<br />

As an alternative, we fallback on OpenGL function calls to extract the bitmap data and write it to a *.hdr* file. Re-compile the program using *OpenGLViewcontroller.m*. Remember to remove *OpenGLViewcontroller2.m* from #Compile Sources#. The resulting *.hdr* image needs to be flipped vertically.

<br />

**Note**: This Readme.md file contains several html tags which cannot be displayed by XCode's Editor.

<br />
<br />
<br />

## Web links:
<br />

https://www.pauldebevec.com/Probes/

https://www.pauldebevec.com/RNL/Source/

https://vgl.ict.usc.edu/Data/HighResProbes/

https://www.gamedev.net/forums/topic/324884-hdr-angular-maps/

https://forum.openframeworks.cc/t/offbo-and-core-image-filters-fix-sought/29051/7

https://bathatmedia.blogspot.com/2013/08/

<br />
<br />

**Developed with XCode 9.4.1**

<br />
<br />

**Runtime requirements:**

>macOS OpenGL 3.2

or

>iOS OpenGL ES 3.0
