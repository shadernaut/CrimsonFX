
#include "cMacros.fxh"
#include "cGraphics.fxh"
#include "cImageProcessing.fxh"
#include "cVideoProcessing.fxh"

/*
    [Shader parameters]
*/

CREATE_OPTION(float, _MipBias, "Optical flow", "Optical flow mipmap bias", "slider", 7.0, 0.0)
CREATE_OPTION(float, _BlendFactor, "Optical flow", "Temporal blending factor", "slider", 0.9, 0.0)

CREATE_TEXTURE(Tex1, BUFFER_SIZE_1, RG8, 3)
CREATE_SAMPLER(SampleTex1, Tex1, LINEAR, MIRROR)

CREATE_TEXTURE(Tex2a, BUFFER_SIZE_2, RGBA16F, 8)
CREATE_SAMPLER(SampleTex2a, Tex2a, LINEAR, MIRROR)

CREATE_TEXTURE(Tex2b, BUFFER_SIZE_2, RG16F, 8)
CREATE_SAMPLER(SampleTex2b, Tex2b, LINEAR, MIRROR)

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
    float4 Color = tex2D(SampleColorTex, Input.Tex0);
    float SumRGB = dot(Color.rgb, 1.0);
    float2 Chroma = saturate(Color.xy / SumRGB);
    Chroma = (SumRGB != 0.0) ? Chroma : 1.0 / 3.0;
    return float4(Chroma, 0.0, 1.0);
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

float4 PS_Sobel(VS2PS_Sobel Input) : SV_TARGET0
{
    return GetPixelSobel_Chroma(Input, SampleTex2c);
}

// Run Lucas-Kanade

float2 PS_PyLK_Level4(VS2PS_LK Input) : SV_TARGET0
{
    float2 Vectors = 0.0;
    return GetPixelPyLK(Input, SampleTex2a, SampleTex2c, SampleTex2b, Vectors, true);
}

float2 PS_PyLK_Level3(VS2PS_LK Input) : SV_TARGET0
{
    float2 Vectors = tex2D(SampleTex5, Input.Tex1.xz).xy;
    return GetPixelPyLK(Input, SampleTex2a, SampleTex2c, SampleTex2b, Vectors, false);
}

float2 PS_PyLK_Level2(VS2PS_LK Input) : SV_TARGET0
{
    float2 Vectors = tex2D(SampleTex4, Input.Tex1.xz).xy;
    return GetPixelPyLK(Input, SampleTex2a, SampleTex2c, SampleTex2b, Vectors, false);
}

float4 PS_PyLK_Level1(VS2PS_LK Input) : SV_TARGET0
{
    float2 Vectors = tex2D(SampleTex3, Input.Tex1.xz).xy;
    return float4(GetPixelPyLK(Input, SampleTex2a, SampleTex2c, SampleTex2b, Vectors, false), 0.0, _BlendFactor);
}

// Postfilter blur

// We use MRT to immeduately copy the current blurred frame for the next frame
float4 PS_HBlur_Postfilter(VS2PS_Blur Input, out float4 Copy : SV_TARGET0) : SV_TARGET1
{
    Copy = tex2D(SampleTex2b, Input.Tex0.xy);
    return float4(GetPixelBlur(Input, SampleOFlowTex).rg, 0.0, 1.0);
}

float4 PS_VBlur_Postfilter(VS2PS_Blur Input) : SV_TARGET0
{
    return float4(GetPixelBlur(Input, SampleTex2a).rg, 0.0, 1.0);
}

float4 PS_Display(VS2PS_Quad Input) : SV_TARGET0
{
    float2 InvTexSize = 1.0 / float2(ddx(Input.Tex0.x), ddy(Input.Tex0.y));
    float2 Velocity = tex2Dlod(SampleTex2b, float4(Input.Tex0.xy, 0.0, _MipBias)).xy;
    Velocity = Velocity * InvTexSize;
    float3 NVelocity = normalize(float3(Velocity, 1.0));
    return float4(saturate((NVelocity * 0.5) + 0.5),  1.0);
}

#define CREATE_PASS(VERTEX_SHADER, PIXEL_SHADER, RENDER_TARGET) \
    pass \
    { \
        VertexShader = VERTEX_SHADER; \
        PixelShader = PIXEL_SHADER; \
        RenderTarget0 = RENDER_TARGET; \
    }

technique cOpticalFlow
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

    pass GetFineOpticalFlow
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

    // Postfilter blur
    pass MRT_CopyAndBlur
    {
        VertexShader = VS_HBlur;
        PixelShader = PS_HBlur_Postfilter;
        RenderTarget0 = Tex2c;
        RenderTarget1 = Tex2a;
    }

    pass
    {
        VertexShader = VS_VBlur;
        PixelShader = PS_VBlur_Postfilter;
        RenderTarget0 = Tex2b;
    }

    // Display
    pass
    {
        #if BUFFER_COLOR_BIT_DEPTH == 8
            SRGBWriteEnable = TRUE;
        #endif

        VertexShader = VS_Quad;
        PixelShader = PS_Display;
    }
}