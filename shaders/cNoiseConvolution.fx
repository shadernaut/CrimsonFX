
uniform float _Radius <
    ui_label = "Convolution radius";
    ui_type = "drag";
    ui_min = 0.0;
> = 32.0;

uniform int _Samples <
    ui_label = "Convolution sample count";
    ui_type = "drag";
    ui_min = 0;
> = 8;

texture2D Render_Color : COLOR;

sampler2D Sample_Color
{
    Texture = Render_Color;
    MagFilter = LINEAR;
    MinFilter = LINEAR;
    MipFilter = LINEAR;
    #if BUFFER_COLOR_BIT_DEPTH == 8
        SRGBTexture = TRUE;
    #endif
};

// Vertex shaders

void Basic_VS(in uint ID : SV_VERTEXID, out float4 Position : SV_POSITION, out float2 TexCoord : TEXCOORD0)
{
    TexCoord.x = (ID == 2) ? 2.0 : 0.0;
    TexCoord.y = (ID == 1) ? 2.0 : 0.0;
    Position = float4(TexCoord * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
}

// Pixel Shaders
// Vogel disk sampling: http://blog.marmakoide.org/?p=1
// Rotated noise sampling: http://www.iryoku.com/next-generation-post-processing-in-call-of-duty-advanced-warfare (slide 123)

static const float Pi = 3.1415926535897932384626433832795;

float2 Vogel_Sample(int Index, int SamplesCount)
{
    const float GoldenAngle = Pi * (3.0 - sqrt(5.0));
    float Radius = sqrt(float(Index) + 0.5) * rsqrt(float(SamplesCount));
    float Theta = float(Index) * GoldenAngle;

    float2 SinCosTheta = 0.0;
    sincos(Theta, SinCosTheta.x, SinCosTheta.y);
    return Radius * SinCosTheta;
}

float Gradient_Noise(float2 Position)
{
    const float3 Numbers = float3(0.06711056f, 0.00583715f, 52.9829189f);
    return frac(Numbers.z * frac(dot(Position.xy, Numbers.xy)));
}

void Noise_Convolution_PS(in float4 Position : SV_POSITION, in float2 TexCoord : TEXCOORD0, out float4 OutputColor0 : SV_TARGET0)
{
    OutputColor0 = 0.0;

    const float2 PixelSize = 1.0 / int2(BUFFER_WIDTH, BUFFER_HEIGHT);
    float Noise = 2.0 * Pi * Gradient_Noise(Position.xy);

    float2 Rotation = 0.0;
    sincos(Noise, Rotation.y, Rotation.x);

    float2x2 RotationMatrix = float2x2(Rotation.x, Rotation.y,
                                      -Rotation.y, Rotation.x);

    for(int i = 0; i < _Samples; i++)
    {
        float2 SampleOffset = mul(Vogel_Sample(i, _Samples) * _Radius, RotationMatrix);
        OutputColor0 += tex2Dlod(Sample_Color, float4(TexCoord.xy + (SampleOffset * PixelSize), 0.0, 0.0));
    }

    OutputColor0 = OutputColor0 / _Samples;
}

technique cNoiseConvolution
{
    pass
    {
        VertexShader = Basic_VS;
        PixelShader = Noise_Convolution_PS;
        #if BUFFER_COLOR_BIT_DEPTH == 8
            SRGBWriteEnable = TRUE;
        #endif
    }
}
