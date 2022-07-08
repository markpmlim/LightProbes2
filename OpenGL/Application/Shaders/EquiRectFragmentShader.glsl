// To map the LightProbe image onto an EquiRectangular Image.
#ifdef GL_ES
precision highp float;
#endif

#if __VERSION__ >= 140

in vec2 texCoords;

out vec4 FragColor;

#else

varying vec2 texCoords;

#endif


uniform sampler2D angularMapImage;      // Texture of Light Probe image

#define M_PI 3.1415926535897932384626433832795

// Note: the view's dimensions are set as 2:1 using XCode's IB.
// To save the equirectangular texture as a 2:1 graphic, we might
//  have to run a second pair of vertex-fragment shader to scale
//  the texture produced by this shader by 2:1
void main(void) {

    vec2 uv = texCoords;
    // Map uv's range from [0.0, 1.0) --> [-1.0, 1.0)
    uv = 2.0 * uv - 1.0;

    // Convert u, v to (θ, φ) angle
    // uv.x: [-1.0, 1.0) ---> [-π, π)
    // uv.y: [-1.0, 1.0) ---> [-π/2, π/2)
    float theta = uv.x * M_PI;      // azimuth  (longitude)
    float phi = uv.y * M_PI/2.0;    // altitude (latitude)

    // rd is a vector from the centre of the cube to the surface of unit sphere
    // Already normalised. Can be proved using trigonometry.
    // Left side of the scene is at the centre of the EquiRectangular map.
    vec3 dir = vec3(cos(phi) * sin(theta),
                    sin(phi),
                    cos(phi) * cos(theta));

    // dir is already normalized.
    float r = (0.5/M_PI) * acos(dir.z)/sqrt(dir.x*dir.x + dir.y*dir.y);
    // Range of vec2(r*dir.x, r*dir.y): [-0.5, 0.5]
    // Range of uv: [0, 1]
    uv = vec2(0.5 + r*dir.x, 0.5 + r*dir.y);


#if __VERSION__ >= 140
    FragColor = texture(angularMapImage, uv);
#else
    gl_FragColor = texture(angularMapImage, uv);
#endif
}
