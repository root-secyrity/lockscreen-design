#version 440

// qylock terminal - vignette-only layer effect (no scanlines / bloom / glitch
// / curvature / flicker). Darkens the edges toward black; the console text
// stays crisp. `strength` is the vignette depth: 0 = passthrough, 1 = full.
// This replaces the CRT shader for a clean, flat phosphor-console look.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float itemWidth;
    float itemHeight;
    float strength;
} ubuf;

layout(binding = 1) uniform sampler2D source;

void main() {
    vec4 c = texture(source, qt_TexCoord0);
    vec2 uv = qt_TexCoord0 - vec2(0.5);
    float aspect = ubuf.itemWidth / ubuf.itemHeight;
    float dist = length(vec2(uv.x * aspect, uv.y));
    float vig = 1.0 - ubuf.strength * smoothstep(0.35, 0.9, dist);
    fragColor = vec4(c.rgb * vig, c.a) * ubuf.qt_Opacity;
}