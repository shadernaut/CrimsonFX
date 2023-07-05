#include "shared/cBuffers.fxh"
#include "shared/cGraphics.fxh"
#include "shared/cImageProcessing.fxh"
#include "shared/cVideoProcessing.fxh"

namespace cBlockMatching
{
    /*
        [Shader Options]
    */

    uniform float _MipBias <
        ui_label = "Optical flow mipmap bias";
        ui_type = "slider";
        ui_min = 0.0;
        ui_max = 7.0;
    > = 4.5;

    uniform float _BlendFactor <
        ui_label = "Temporal blending factor";
        ui_type = "slider";
        ui_min = 0.0;
        ui_max = 0.9;
    > = 0.5;

    /*
        [Textures & Samplers]
    */

    CREATE_SAMPLER(SampleTempTex1, TempTex1_RG8, LINEAR, MIRROR)
    CREATE_SAMPLER(SampleTempTex2a, TempTex2a_RG16F, LINEAR, MIRROR)
    CREATE_SAMPLER(SampleTempTex3, TempTex3_RG16F, LINEAR, MIRROR)
    CREATE_SAMPLER(SampleTempTex4, TempTex4_RG16F, LINEAR, MIRROR)
    CREATE_SAMPLER(SampleTempTex5, TempTex5_RG16F, LINEAR, MIRROR)
    CREATE_SAMPLER(SampleTempTex6, TempTex6_RG16F, LINEAR, MIRROR)

    CREATE_TEXTURE(Tex2c, BUFFER_SIZE_2, RG16F, 8)
    CREATE_SAMPLER(SampleTempTex2c, Tex2c, LINEAR, MIRROR)

    CREATE_TEXTURE(OFlowTex, BUFFER_SIZE_2, RG16F, 1)
    CREATE_SAMPLER(SampleOFlowTex, OFlowTex, LINEAR, MIRROR)

    /*
        [Pixel Shaders]
    */

    float2 PS_Normalize(VS2PS_Quad Input) : SV_TARGET0
    {
        float3 Color = tex2D(CShade_SampleColorTex, Input.Tex0).rgb;
        return GetSphericalRG(Color, Input.HPos.xy);
    }

    float4 PS_Copy_0(VS2PS_Quad Input) : SV_TARGET0
    {
        return tex2D(SampleTempTex1, Input.Tex0.xy);
    }

    float2 PS_MFlow_Level5(VS2PS_Quad Input) : SV_TARGET0
    {
        float2 Vectors = 0.0;
        return GetPixelMFlow(Input.Tex0, Vectors, SampleTempTex2c, SampleTempTex2a, 4);
    }

    float2 PS_MFlow_Level4(VS2PS_Quad Input) : SV_TARGET0
    {
        float2 Vectors = tex2D(SampleTempTex6, Input.Tex0).xy;
        return GetPixelMFlow(Input.Tex0, Vectors, SampleTempTex2c, SampleTempTex2a, 3);
    }

    float2 PS_MFlow_Level3(VS2PS_Quad Input) : SV_TARGET0
    {
        float2 Vectors = tex2D(SampleTempTex5, Input.Tex0).xy;
        return GetPixelMFlow(Input.Tex0, Vectors, SampleTempTex2c, SampleTempTex2a, 2);
    }

    float2 PS_MFlow_Level2(VS2PS_Quad Input) : SV_TARGET0
    {
        float2 Vectors = tex2D(SampleTempTex4, Input.Tex0).xy;
        return GetPixelMFlow(Input.Tex0, Vectors, SampleTempTex2c, SampleTempTex2a, 1);
    }

    float4 PS_MFlow_Level1(VS2PS_Quad Input) : SV_TARGET0
    {
        float2 Vectors = tex2D(SampleTempTex3, Input.Tex0).xy;
        return float4(GetPixelMFlow(Input.Tex0, Vectors, SampleTempTex2c, SampleTempTex2a, 0), 0.0, _BlendFactor);
    }

    float4 PS_Copy_1(VS2PS_Quad Input) : SV_TARGET0
    {
        return tex2D(SampleTempTex2a, Input.Tex0.xy);
    }

    float4 PS_Display(VS2PS_Quad Input) : SV_TARGET0
    {
        float2 InvTexSize = float2(ddx(Input.Tex0.x), ddy(Input.Tex0.y));

        float2 Vectors = tex2Dlod(SampleOFlowTex, float4(Input.Tex0.xy, 0.0, _MipBias)).xy;
        Vectors = DecodeVectors(Vectors, InvTexSize);

        float3 NVectors = normalize(float3(Vectors, 1.0));
        NVectors = saturate((NVectors * 0.5) + 0.5);

        return float4(NVectors, 1.0);
    }

    #define CREATE_PASS(VERTEX_SHADER, PIXEL_SHADER, RENDER_TARGET) \
        pass \
        { \
            VertexShader = VERTEX_SHADER; \
            PixelShader = PIXEL_SHADER; \
            RenderTarget0 = RENDER_TARGET; \
        }


}