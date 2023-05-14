#include "shared/cGraphics.fxh"
#include "shared/cImageProcessing.fxh"
#include "shared/cVideoProcessing.fxh"

/*
    [Shader parameters]
*/

uniform float _FrameTime < source = "frametime"; > ;

CREATE_OPTION(float, _MipBias, "Optical flow", "Optical flow mipmap bias", "slider", 7.0, 4.5)
CREATE_OPTION(float, _BlendFactor, "Optical flow", "Temporal blending factor", "slider", 0.9, 0.25)
CREATE_OPTION(float, _Scale, "Main", "Blur scale", "slider", 2.0, 1.0)
CREATE_OPTION(bool, _FrameRateScaling, "Other", "Enable frame-rate scaling", "radio", 1.0, false)
CREATE_OPTION(float, _TargetFrameRate, "Other", "Target frame-rate", "drag", 144.0, 60.0)

CREATE_TEXTURE(Tex1, BUFFER_SIZE_1, RG8, 3)
CREATE_SAMPLER(SampleTex1, Tex1, LINEAR, MIRROR)

CREATE_TEXTURE(Tex2a, BUFFER_SIZE_2, RG16F, 8)
CREATE_SAMPLER(SampleTex2a, Tex2a, LINEAR, MIRROR)

CREATE_TEXTURE(Tex2b, BUFFER_SIZE_2, RG16F, 8)
CREATE_SAMPLER(SampleTex2b, Tex2b, LINEAR, MIRROR)

CREATE_TEXTURE(Tex2c, BUFFER_SIZE_2, RG16F, 8)
CREATE_SAMPLER(SampleTex2c, Tex2c, LINEAR, MIRROR)

CREATE_TEXTURE(OFlowTex, BUFFER_SIZE_2, RG16F, 1)
CREATE_SAMPLER(SampleOFlowTex, OFlowTex, LINEAR, MIRROR)

CREATE_TEXTURE(Tex3, BUFFER_SIZE_4, RG16F, 1)
CREATE_SAMPLER(SampleTex3, Tex3, LINEAR, MIRROR)

CREATE_TEXTURE(Tex4, BUFFER_SIZE_6, RG16F, 1)
CREATE_SAMPLER(SampleTex4, Tex4, LINEAR, MIRROR)

// Vertex shaders

VS2PS_Blur VS_HBlur(APP2VS Input)
{
    return GetVertexBlur(Input, 1.0 / BUFFER_SIZE_2, true);
}

VS2PS_Blur VS_VBlur(APP2VS Input)
{
    return GetVertexBlur(Input, 1.0 / BUFFER_SIZE_2, false);
}

// Pixel shaders

float2 PS_Normalize(VS2PS_Quad Input) : SV_TARGET0
{
    float3 Color = tex2D(CShade_SampleColorTex, Input.Tex0).rgb;
    return NormalizeRGB(Color);
}

float2 PS_HBlur_Prefilter(VS2PS_Blur Input) : SV_TARGET0
{
    return GetPixelBlur(Input, SampleTex1).rg;
}

float2 PS_VBlur_Prefilter(VS2PS_Blur Input) : SV_TARGET0
{
    return GetPixelBlur(Input, SampleTex2a).rg;
}

// Run Lucas-Kanade

float2 PS_PyLK_Level3(VS2PS_Quad Input) : SV_TARGET0
{
    float2 Vectors = 0.0;
    return GetPixelPyLK(Input.Tex0, Vectors, SampleTex2c, SampleTex2b, 2);
}

float2 PS_PyLK_Level2(VS2PS_Quad Input) : SV_TARGET0
{
    float2 Vectors = tex2D(SampleTex4, Input.Tex0).xy;
    return GetPixelPyLK(Input.Tex0, Vectors, SampleTex2c, SampleTex2b, 1);
}

float4 PS_PyLK_Level1(VS2PS_Quad Input) : SV_TARGET0
{
    float2 Vectors = tex2D(SampleTex3, Input.Tex0).xy;
    return float4(GetPixelPyLK(Input.Tex0, Vectors, SampleTex2c, SampleTex2b, 0), 0.0, _BlendFactor);
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

float Noise(float2 Pos)
{
    return frac(52.9829189 * frac(dot(Pos, float2(0.06711056, 0.00583715))));
}

float4 PS_MotionBlur(VS2PS_Quad Input) : SV_TARGET0
{
    float4 OutputColor = 0.0;
    const int Samples = 8;


    float FrameRate = 1e+3 / _FrameTime;
    float FrameTimeRatio = _TargetFrameRate / FrameRate;

    float2 ScreenSize = float2(BUFFER_WIDTH, BUFFER_HEIGHT);
    float2 ScreenCoord = Input.Tex0.xy;

    float2 Velocity = tex2Dlod(SampleTex2b, float4(Input.Tex0.xy, 0.0, _MipBias)).xy;

    float2 ScaledVelocity = Velocity * _Scale;
    ScaledVelocity = (_FrameRateScaling) ? ScaledVelocity / FrameTimeRatio : ScaledVelocity;

    for (int k = 0; k < Samples; ++k)
    {
        float2 Offset = ScaledVelocity * ((Noise(Input.HPos.xy + k) * 2.0) - 1.0);
        OutputColor += tex2D(CShade_SampleColorTex, ScreenCoord + Offset);
        OutputColor += tex2D(CShade_SampleColorTex, ScreenCoord - Offset);
    }

    return OutputColor / (Samples * 2.0);
}

#define CREATE_PASS(VERTEX_SHADER, PIXEL_SHADER, RENDER_TARGET) \
    pass \
    { \
        VertexShader = VERTEX_SHADER; \
        PixelShader = PIXEL_SHADER; \
        RenderTarget0 = RENDER_TARGET; \
    }

technique CShade_MotionBlur
{
    // Normalize current frame
    CREATE_PASS(VS_Quad, PS_Normalize, Tex1)

    // Prefilter blur
    CREATE_PASS(VS_HBlur, PS_HBlur_Prefilter, Tex2a)
    CREATE_PASS(VS_VBlur, PS_VBlur_Prefilter, Tex2b)

    // Bilinear Lucas-Kanade Optical Flow
    CREATE_PASS(VS_Quad, PS_PyLK_Level3, Tex4)
    CREATE_PASS(VS_Quad, PS_PyLK_Level2, Tex3)
    pass GetFineOpticalFlow
    {
        ClearRenderTargets = FALSE;
        BlendEnable = TRUE;
        BlendOp = ADD;
        SrcBlend = INVSRCALPHA;
        DestBlend = SRCALPHA;

        VertexShader = VS_Quad;
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

    // Motion blur
    pass
    {
        SRGBWriteEnable = WRITE_SRGB;

        VertexShader = VS_Quad;
        PixelShader = PS_MotionBlur;
    }
}