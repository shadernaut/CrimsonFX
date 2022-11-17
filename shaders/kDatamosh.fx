
/*
    This is free and unencumbered software released into the public domain.

    Anyone is free to copy, modify, publish, use, compile, sell, or
    distribute this software, either in source code form or as a compiled
    binary, for any purpose, commercial or non-commercial, and by any
    means.

    In jurisdictions that recognize copyright laws, the author or authors
    of this software dedicate any and all copyright interest in the
    software to the public domain. We make this dedication for the benefit
    of the public at large and to the detriment of our heirs and
    successors. We intend this dedication to be an overt act of
    relinquishment in perpetuity of all present and future rights to this
    software under copyright law.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
    EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
    MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
    IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
    OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
    ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
    OTHER DEALINGS IN THE SOFTWARE.

    For more information, please refer to <http://unlicense.org/>
*/

#include "cMacros.fxh"
#include "cGraphics.fxh"
#include "cImageProcessing.fxh"
#include "cVideoProcessing.fxh"

/*
    [Shader parameters]
*/

uniform float _Time < source = "timer"; >;

CREATE_OPTION(int, _BlockSize, "Datamosh", "Block Size", "slider", 32, 16)
CREATE_OPTION(float, _Entropy, "Datamosh", "Entropy", "slider", 1.0, 0.5)
CREATE_OPTION(float, _Contrast, "Datamosh", "Contrast of noise", "slider", 4.0, 2.0)
CREATE_OPTION(float, _Scale, "Datamosh", "Velocity scale", "slider", 2.0, 1.0)
CREATE_OPTION(float, _Diffusion, "Datamosh", "Amount of random displacement", "slider", 4.0, 2.0)

CREATE_OPTION(float, _MipBias, "Optical flow", "Optical flow mipmap bias", "slider", 6.0, 2.0)
CREATE_OPTION(float, _BlendFactor, "Optical flow", "Temporal blending factor", "slider", 0.9, 0.5)

#ifndef LINEAR_SAMPLING
    #define LINEAR_SAMPLING 0
#endif

#if LINEAR_SAMPLING == 1
    #define FILTERING LINEAR
#else
    #define FILTERING POINT
#endif

/*
    [Textures and samplers]
*/

CREATE_TEXTURE(Tex1, BUFFER_SIZE_1, RG8, 3)
CREATE_SAMPLER(SampleTex1, Tex1, LINEAR, MIRROR)

CREATE_TEXTURE(Tex2a, BUFFER_SIZE_2, RGBA16F, 8)
CREATE_SAMPLER(SampleTex2a, Tex2a, LINEAR, MIRROR)

CREATE_TEXTURE(Tex2b, BUFFER_SIZE_2, RG16F, 8)
CREATE_SAMPLER(SampleTex2b, Tex2b, LINEAR, MIRROR)
CREATE_SAMPLER(SampleFilteredFlowTex, Tex2b, FILTERING, MIRROR)

CREATE_TEXTURE(Tex2c, BUFFER_SIZE_2, RG16F, 8)
CREATE_SAMPLER(SampleTex2c, Tex2c, LINEAR, MIRROR)

CREATE_TEXTURE(OFlowTex, BUFFER_SIZE_2, RG16F, 1)
CREATE_SAMPLER(SampleOFlowTex, OFlowTex, LINEAR, MIRROR)

CREATE_TEXTURE(Tex3, BUFFER_SIZE_3, RG16F, 1)
CREATE_SAMPLER(SampleTex3, Tex3, LINEAR, MIRROR)

CREATE_TEXTURE(Tex4, BUFFER_SIZE_4, RG16F, 1)
CREATE_SAMPLER(SampleTex4, Tex4, LINEAR, MIRROR)

CREATE_TEXTURE(Tex5, BUFFER_SIZE_5, RG16F, 1)
CREATE_SAMPLER(SampleTex5, Tex5, LINEAR, MIRROR)

CREATE_TEXTURE(AccumTex, BUFFER_SIZE_2, R16F, 1)
CREATE_SAMPLER(SampleAccumTex, AccumTex, FILTERING, MIRROR)

CREATE_TEXTURE(FeedbackTex, BUFFER_SIZE_0, RGBA8, 1)
CREATE_SRGB_SAMPLER(SampleFeedbackTex, FeedbackTex, LINEAR, MIRROR)

// Vertex shaders

VS2PS_Blur VS_HBlur(APP2VS Input)
{
    return GetVertexBlur(Input, 1.0 / BUFFER_SIZE_2, true);
}

VS2PS_Blur VS_VBlur(APP2VS Input)
{
    return GetVertexBlur(Input, 1.0 / BUFFER_SIZE_2, false);
}

VS2PS_Sobel VS_Sobel(APP2VS Input)
{
    return GetVertexSobel(Input, 1.0 / BUFFER_SIZE_2);
}

#define CREATE_VS_PYLK(METHOD_NAME, INV_BUFFER_SIZE) \
    VS2PS_LK METHOD_NAME(APP2VS Input) \
    { \
        return GetVertexPyLK(Input, INV_BUFFER_SIZE); \
    }

CREATE_VS_PYLK(VS_PyLK_Level1, 1.0 / BUFFER_SIZE_2)
CREATE_VS_PYLK(VS_PyLK_Level2, 1.0 / BUFFER_SIZE_3)
CREATE_VS_PYLK(VS_PyLK_Level3, 1.0 / BUFFER_SIZE_4)
CREATE_VS_PYLK(VS_PyLK_Level4, 1.0 / BUFFER_SIZE_5)

// Pixel shaders

// Normalize buffer

float4 PS_Normalize(VS2PS_Quad Input) : SV_TARGET0
{
    float4 OutputColor = 0.0;
    float4 Color = max(tex2D(SampleColorTex, Input.Tex0), exp2(-8.0));
    return float4(normalize(Color.rgb).xy, 0.0, 1.0);
}

// Prefiler buffer

float4 PS_HBlur_Prefilter(VS2PS_Blur Input) : SV_TARGET0
{
    return float4(GetPixelBlur(Input, SampleTex1).rg, 0.0, 1.0);
}

float4 PS_VBlur_Prefilter(VS2PS_Blur Input) : SV_TARGET0
{
    return float4(GetPixelBlur(Input, SampleTex2a).rg, 0.0, 1.0);
}

// Process spatial derivatives

float4 PS_Copy(VS2PS_Quad Input) : SV_TARGET0
{
    return tex2D(SampleTex2b, Input.Tex0);
}

float4 PS_Sobel(VS2PS_Sobel Input) : SV_TARGET0
{
    return GetPixelSobel_Chroma(Input, SampleTex2c);
}

// Run Lucas-Kanade

float2 PS_PyLK_Level4(VS2PS_LK Input) : SV_TARGET0
{
    float2 Vectors = 0.0;
    return GetPixelPyLK(Input, SampleTex2a, SampleTex2c, SampleTex2b, Vectors);
}

float2 PS_PyLK_Level3(VS2PS_LK Input) : SV_TARGET0
{
    float2 Vectors = tex2D(SampleTex5, Input.Tex0.xy).xy;
    return GetPixelPyLK(Input, SampleTex2a, SampleTex2c, SampleTex2b, Vectors);
}
float2 PS_PyLK_Level2(VS2PS_LK Input) : SV_TARGET0
{
    float2 Vectors = tex2D(SampleTex4, Input.Tex0.xy).xy;
    return GetPixelPyLK(Input, SampleTex2a, SampleTex2c, SampleTex2b, Vectors);
}

float4 PS_PyLK_Level1(VS2PS_LK Input) : SV_TARGET0
{
    float2 Vectors = tex2D(SampleTex3, Input.Tex0.xy).xy;
    return float4(GetPixelPyLK(Input, SampleTex2a, SampleTex2c, SampleTex2b, Vectors), 0.0, _BlendFactor);
}

// Postfilter blur

float4 PS_HBlur_Postfilter(VS2PS_Blur Input) : SV_TARGET0
{
    return float4(GetPixelBlur(Input, SampleOFlowTex).rg, 0.0, 1.0);
}

float4 PS_VBlur_Postfilter(VS2PS_Blur Input) : SV_TARGET0
{
    return float4(GetPixelBlur(Input, SampleTex2a).rg, 0.0, 1.0);
}

// Datamosh

float RandomNoise(float2 TexCoord)
{
    float f = dot(float2(12.9898, 78.233), TexCoord);
    return frac(43758.5453 * sin(f));
}

float4 PS_Accumulate(VS2PS_Quad Input) : SV_TARGET0
{
    float Quality = 1.0 - _Entropy;
    float2 Time = float2(_Time, 0.0);

    // Random numbers
    float3 Random;
    Random.x = RandomNoise(Input.HPos.xy + Time.xy);
    Random.y = RandomNoise(Input.HPos.xy + Time.yx);
    Random.z = RandomNoise(Input.HPos.yx - Time.xx);

    // Motion vector
    float2 MotionVectors = tex2Dlod(SampleFilteredFlowTex, float4(Input.Tex0, 0.0, _MipBias)).xy;
    MotionVectors = MotionVectors * BUFFER_SIZE_2; // Normalized screen space -> Pixel coordinates
    MotionVectors *= _Scale;
    MotionVectors += (Random.xy - 0.5)  * _Diffusion; // Small random displacement (diffusion)
    MotionVectors = round(MotionVectors); // Pixel perfect snapping

    // Accumulates the amount of motion.
    float MotionVectorLength = length(MotionVectors);

    // - Simple update
    float UpdateAccumulation = min(MotionVectorLength, _BlockSize) * 0.005;
    UpdateAccumulation = saturate(UpdateAccumulation + Random.z * lerp(-0.02, 0.02, Quality));

    // - Reset to random level
    float ResetAccumulation = saturate(Random.z * 0.5 + Quality);

    float4 OutputColor = float4((float3)UpdateAccumulation, 1.0);

    // - Reset if the amount of motion is larger than the block size.
    if(MotionVectorLength > _BlockSize)
    {
        OutputColor = float4((float3)ResetAccumulation, 0.0);
    }

    return OutputColor;
}

float4 PS_Datamosh(VS2PS_Quad Input) : SV_TARGET0
{
    float2 ScreenSize = float2(BUFFER_WIDTH, BUFFER_HEIGHT);
    const float2 DisplacementTexel = 1.0 / ScreenSize;
    const float Quality = 1.0 - _Entropy;

    // Random numbers
    float2 Time = float2(_Time, 0.0);
    float3 Random;
    Random.x = RandomNoise(Input.HPos.xy + Time.xy);
    Random.y = RandomNoise(Input.HPos.xy + Time.yx);
    Random.z = RandomNoise(Input.HPos.yx - Time.xx);

    float2 MotionVectors = tex2Dlod(SampleFilteredFlowTex, float4(Input.Tex0, 0.0, _MipBias)).xy;
    MotionVectors *= _Scale;

    float4 Source = tex2D(SampleColorTex, Input.Tex0); // Color from the original image
    float Displacement = tex2D(SampleAccumTex, Input.Tex0).r; // Displacement vector
    float4 Working = tex2D(SampleFeedbackTex, Input.Tex0 + (MotionVectors * DisplacementTexel));

    MotionVectors *= BUFFER_SIZE_2; // Normalized screen space -> Pixel coordinates
    MotionVectors += (Random.xy - 0.5) * _Diffusion; // Small random displacement (diffusion)
    MotionVectors = round(MotionVectors); // Pixel perfect snapping
    MotionVectors /= BUFFER_SIZE_2; // Pixel coordinates -> Normalized screen space

    // Generate some pseudo random numbers.
    float RandomMotion = RandomNoise(Input.Tex0 + length(MotionVectors));
    float4 RandomNumbers = frac(float4(1.0, 17.37135, 841.4272, 3305.121) * RandomMotion);

    // Generate noise patterns that look like DCT bases.
    float2 Frequency = Input.Tex0 * DisplacementTexel * (RandomNumbers.x * 80.0 / _Contrast);

    // - Basis wave (vertical or horizontal)
    float DCT = cos(lerp(Frequency.x, Frequency.y, 0.5 < RandomNumbers.y));

    // - Random amplitude (the high freq, the less amp)
    DCT *= RandomNumbers.z * (1.0 - RandomNumbers.x) * _Contrast;

    // Conditional weighting
    // - DCT-ish noise: acc > 0.5
    float ConditionalWeight = (Displacement > 0.5) * DCT;

    // - Original image: rand < (Q * 0.8 + 0.2) && acc == 1.0
    ConditionalWeight = lerp(ConditionalWeight, 1.0, RandomNumbers.w < lerp(0.2, 1.0, Quality) * (Displacement > 1.0 - 1e-3));

    // - If the conditions above are not met, choose work.
    return lerp(Working, Source, ConditionalWeight);
}

float4 PS_CopyColorTex(VS2PS_Quad Input) : SV_TARGET0
{
    return tex2D(SampleColorTex, Input.Tex0);
}

#define CREATE_PASS(VERTEX_SHADER, PIXEL_SHADER, RENDER_TARGET) \
    pass \
    { \
        VertexShader = VERTEX_SHADER; \
        PixelShader = PIXEL_SHADER; \
        RenderTarget0 = RENDER_TARGET; \
    }

technique kDatamosh
{
    // Normalize current frame
    CREATE_PASS(VS_Quad, PS_Normalize, Tex1)

    // Prefilter blur
    CREATE_PASS(VS_HBlur, PS_HBlur_Prefilter, Tex2a)
    CREATE_PASS(VS_VBlur, PS_VBlur_Prefilter, Tex2b)

    // Calculate derivatives
    CREATE_PASS(VS_Sobel, PS_Sobel, Tex2a)

    // Bilinear Lucas-Kanade Optical Flow
    CREATE_PASS(VS_PyLK_Level4, PS_PyLK_Level4, Tex5)
    CREATE_PASS(VS_PyLK_Level3, PS_PyLK_Level3, Tex4)
    CREATE_PASS(VS_PyLK_Level2, PS_PyLK_Level2, Tex3)
    pass
    {
        ClearRenderTargets = FALSE;
        BlendEnable = TRUE;
        BlendOp = ADD;
        SrcBlend = INVSRCALPHA;
        DestBlend = SRCALPHA;
        
        VertexShader = VS_PyLK_Level1;
        PixelShader = PS_PyLK_Level1;
        RenderTarget0 = OFlowTex;
    }
    
	// Copy current convolved frame for next frame
    CREATE_PASS(VS_Quad, PS_Copy, Tex2c)

    // Prefilter blur
    CREATE_PASS(VS_HBlur, PS_HBlur_Postfilter, Tex2a)
    CREATE_PASS(VS_VBlur, PS_VBlur_Postfilter, Tex2b)
    
    // Datamoshing
    pass
    {
        ClearRenderTargets = FALSE;
        BlendEnable = TRUE;
        BlendOp = ADD;
        SrcBlend = ONE;
        DestBlend = SRCALPHA; // The result about to accumulate

        VertexShader = VS_Quad;
        PixelShader = PS_Accumulate;
        RenderTarget0 = AccumTex;
    }

    pass
    {
        #if BUFFER_COLOR_BIT_DEPTH == 8
            SRGBWriteEnable = TRUE;
        #endif

        VertexShader = VS_Quad;
        PixelShader = PS_Datamosh;
    }

    // Copy frame for feedback
    pass
    {
        #if BUFFER_COLOR_BIT_DEPTH == 8
            SRGBWriteEnable = TRUE;
        #endif

        VertexShader = VS_Quad;
        PixelShader = PS_CopyColorTex;
        RenderTarget0 = FeedbackTex;
    }
}