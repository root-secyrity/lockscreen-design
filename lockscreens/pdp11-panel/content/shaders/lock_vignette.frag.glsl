#version 100
// qylock terminal - vignette-only layer effect (no scanlines / bloom / glitch).
// Darkens the edges of the console toward black; text stays crisp.
uniform sampler2D source;
uniform lowp float qt_Opacity;
varying vec2 qt_TexCoord0;
uniform float itemWidth;
uniform float itemHeight;
uniform float strength;

void main() {
    vec4 c = texture2D(source, qt_TexCoord0);
    vec2 uv = qt_TexCoord0 - vec2(0.5);
    float aspect = itemWidth / itemHeight;
    float dist = length(vec2(uv.x * aspect, uv.y));
    float vig = 1.0 - strength * smoothstep(0.35, 0.9, dist);
    gl_FragColor = vec4(c.rgb * vig, c.a) * qt_Opacity;
}
