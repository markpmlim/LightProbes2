#ifdef GL_ES
precision mediump float;
#endif

#if __VERSION__ >= 140
in vec2 texCoords;

out vec4 FragColor;

#else

varying vec2 texCoords;

#endif

uniform sampler2D equiRectImage;
uniform vec2 u_resolution;  // Canvas size (width,height) - dimensions of view port
uniform vec2 u_mouse;       // mouse position in screen pixels
uniform float u_time;       // Time in seconds since load

void main(void) {
    vec2 uv = texCoords;

#if __VERSION__ >= 140
    FragColor = texture(equiRectImage, uv);
#else
    gl_FragColor = texture2D(equiRectImage, uv);
#endif
}
