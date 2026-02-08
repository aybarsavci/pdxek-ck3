Includes = {
	"cw/pdxgui.fxh"
	"cw/pdxgui_sprite.fxh"
	"cw/utility.fxh"
}


ConstantBuffer( PdxConstantBuffer2 )
{
	float3 HighlightColor;
};


VertexShader =
{
	MainCode VertexShader
	{
		Input = "VS_INPUT_PDX_GUI"
		Output = "VS_OUTPUT_PDX_GUI"
		Code
		[[
			PDX_MAIN
			{
				return PdxGuiDefaultVertexShader( Input );
			}
		]]
	}
}


PixelShader =
{
	TextureSampler Texture
	{
		Ref = PdxTexture0
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Clamp"
		SampleModeV = "Clamp"
	}
	
	MainCode PixelShader
	{
		Input = "VS_OUTPUT_PDX_GUI"
		Output = "PDX_COLOR"
		Code
		[[
			PDX_MAIN
			{			
				float4 OutColor = SampleImageSprite( Texture, Input.UV0 );

				#ifdef HSV_SHIFT
					OutColor = RGBtoHSV(OutColor);
					OutColor += Input.Color;
					OutColor = HSVtoRGB(OutColor);
				#else

					OutColor *= Input.Color;

				#endif
				#ifndef NO_HIGHLIGHT
					OutColor.rgb += HighlightColor;
				#endif
				
				#ifdef DISABLED
					OutColor.rgb = DisableColor( OutColor.rgb );
				#endif
			    return OutColor;
			}
		]]
	}
}


BlendState BlendState
{
	BlendEnable = yes
	SourceBlend = "SRC_ALPHA"
	DestBlend = "INV_SRC_ALPHA"
}

BlendState BlendStateNoAlpha
{
	BlendEnable = no
}

DepthStencilState DepthStencilState
{
	DepthEnable = no
}


Effect Up
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
}

Effect Over
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
}

Effect Down
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
}

Effect Disabled
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
	
	Defines = { "DISABLED" }
}

Effect NoAlphaNoHighlightUp
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
	BlendState = BlendStateNoAlpha

	Defines = { "NO_HIGHLIGHT" }
}

Effect NoAlphaNoHighlightOver
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
	BlendState = BlendStateNoAlpha
	
	Defines = { "NO_HIGHLIGHT" }
}

Effect NoAlphaNoHighlightDown
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
	BlendState = BlendStateNoAlpha
	
	Defines = { "NO_HIGHLIGHT" }
}

Effect NoAlphaNoHighlightDisabled
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
	BlendState = BlendStateNoAlpha
	
	Defines = { "DISABLED" "NO_HIGHLIGHT" }
}

Effect NoHighlightUp
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
	
	Defines = { "NO_HIGHLIGHT" }
}

Effect NoHighlightOver
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
	
	Defines = { "NO_HIGHLIGHT" }
}

Effect NoHighlightDown
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
	
	Defines = { "NO_HIGHLIGHT" }
}

Effect NoHighlightDisabled
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
	
	Defines = { "DISABLED" "NO_HIGHLIGHT" }
}

Effect HSVShiftNoHighlightUp
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
	
	Defines = { "NO_HIGHLIGHT" "HSV_SHIFT" }
}

Effect HSVShiftNoHighlightOver
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
	
	Defines = { "NO_HIGHLIGHT" "HSV_SHIFT" }
}

Effect HSVShiftNoHighlightDown
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
	
	Defines = { "NO_HIGHLIGHT" "HSV_SHIFT" }
}

Effect HSVShiftNoHighlightDisabled
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
	
	Defines = { "DISABLED" "NO_HIGHLIGHT" "HSV_SHIFT" }
}

Effect GreyedOutUp
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
	Defines = { "DISABLED" }
}

Effect GreyedOutOver
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
	Defines = { "DISABLED" }
}

Effect GreyedOutDown
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
	Defines = { "DISABLED" }
}

Effect GreyedOutDisabled
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
	
	Defines = { "DISABLED" "NO_HIGHLIGHT" }
}

Effect NoDisabledUp
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
}

Effect NoDisabledOver
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
}

Effect NoDisabledDown
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
}

Effect NoDisabledDisabled
{
	VertexShader = "VertexShader"
	PixelShader = "PixelShader"
}
