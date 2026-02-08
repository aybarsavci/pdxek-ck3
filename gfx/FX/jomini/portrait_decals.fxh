includes = {
	"jomini/texture_decals_base.fxh"
	"jomini/portrait_user_data.fxh"
}

PixelShader =
{
	TextureSampler DecalDiffuseArray
	{
		Ref = JominiPortraitDecalDiffuseArray
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		type = "2darray"
	}

	TextureSampler DecalNormalArray
	{
		Ref = JominiPortraitDecalNormalArray
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		type = "2darray"
	}

	TextureSampler DecalPropertiesArray
	{
		Ref = JominiPortraitDecalPropertiesArray
		MagFilter = "Linear"
		MinFilter = "Linear"
		MipFilter = "Linear"
		SampleModeU = "Wrap"
		SampleModeV = "Wrap"
		type = "2darray"
	}

	BufferTexture DecalDataBuffer
	{
		Ref = JominiPortraitDecalData
		type = uint
	}

	Code
	[[		
		//EK2
		#define BODYPART_EYES 2

		//Following make MIP decoding code easier to read
		static const float3 RED 	= 	float3(1.0f,0.0f,0.0f);
		static const float3 GREEN 	= 	float3(0.0f,1.0f,0.0f);
		static const float3 BLUE 	= 	float3(0.0f,0.0f,1.0f);
		static const float3 CYAN 	=	float3(0.0f,1.0f,1.0f);
		static const float3 MAGENTA =	float3(1.0f,0.0f,1.0f);
		static const float3 YELLOW 	=	float3(1.0f,1.0f,0.0f);

		#define DIFFUSE_DECAL uint(0)	
		#define NORMAL_DECAL uint(1)	
		#define PROPERTIES_DECAL uint(2)

		//Custom DX/OPENGL Defines

		#ifndef PDX_OPENGL
			#define GH_PdxTex2DArrayLoad(samp,uvi,lod) (samp)._Texture.Load( int4((uvi), (lod)) )
			#define EK2_PdxTex2DArraySize(samp,size) (samp)._Texture.GetDimensions( (size).x, (size).y, (size).z )


		#else
			#define GH_PdxTex2DArrayLoad texelFetch
			#define EK2_PdxTex2DArraySize(samp,size) size = textureSize((samp), 0)
		#endif
		//EK2

		struct DecalData
		{
			uint _DiffuseIndex;
			uint _NormalIndex;
			uint _PropertiesIndex;
			uint _BodyPartIndex;

			uint _DiffuseBlendMode;
			uint _NormalBlendMode;
			uint _PropertiesBlendMode;
			float _Weight;

			uint2 _AtlasPos;
			float2 _UVOffset;
			uint2 _UVTiling;

			uint _AtlasSize;
		};

		DecalData GetDecalData( int Index )
		{
			// Data for each decal is stored in multiple texels as specified by DecalData

			DecalData Data;

			Data._DiffuseIndex = PdxReadBuffer( DecalDataBuffer, Index );
			Data._NormalIndex = PdxReadBuffer( DecalDataBuffer, Index + 1 );
			Data._PropertiesIndex = PdxReadBuffer( DecalDataBuffer, Index + 2 );
			Data._BodyPartIndex = PdxReadBuffer( DecalDataBuffer, Index + 3 );

			Data._DiffuseBlendMode = PdxReadBuffer( DecalDataBuffer, Index + 4 );
			Data._NormalBlendMode = PdxReadBuffer( DecalDataBuffer, Index + 5 );
			if ( Data._NormalBlendMode == BLEND_MODE_OVERLAY )
			{
				Data._NormalBlendMode = BLEND_MODE_OVERLAY_NORMAL;
			}
			Data._PropertiesBlendMode = PdxReadBuffer( DecalDataBuffer, Index + 6 );
			Data._Weight = Unpack16BitUnorm( PdxReadBuffer( DecalDataBuffer, Index + 7 ) );

			Data._AtlasPos = uint2( PdxReadBuffer( DecalDataBuffer, Index + 8 ), PdxReadBuffer( DecalDataBuffer, Index + 9 ) );
			Data._UVOffset = float2( Unpack16BitUnorm( PdxReadBuffer( DecalDataBuffer, Index + 10 ) ), Unpack16BitUnorm( PdxReadBuffer( DecalDataBuffer, Index + 11 ) ) );
			Data._UVTiling = uint2( PdxReadBuffer( DecalDataBuffer, Index + 12 ), PdxReadBuffer( DecalDataBuffer, Index + 13 ) );

			Data._AtlasSize = PdxReadBuffer( DecalDataBuffer, Index + 14 );

			return Data;
		}

		//EK2 


		// This function tells us which MIP level we need to sample, to retrieve the "absulute" MIP6 containing our encoded pixels.
		// It's needed because using lower texture settings in the game change which MIP level is beings sampled.
		// I.e. Sampling MIP6 on "Ultra" settings would sample MIP6 texture correctly
		// But Sampling MIP6 on "High" settings would actually sample MIP7, because the game is using the texture MIP1 as MIP0 in the shader for lower graphical settings.
		// Essentially this figures out which MIP level we need to sample to find the one with 16x16px dimensions.

		uint GetMIP6Level()
		{
			/////////////////////////// FIND CURRENT MIP LEVEL ///////////////////////////
			float3 TextureSize;
			EK2_PdxTex2DArraySize(DecalDiffuseArray, TextureSize);

			//Get log base 2 for current texture size (1024px - 10, 512px - 9, etc.)
			//Take that away from 10 to find the current MIP level.
			//Take that away from 6 to find which MIP We need to sample in the texture buffer to retrieve the "absulute" MIP6 containing our encoded pixels
			uint MIP = uint(6.0f-(10.0f - log2(TextureSize.x)));
			return MIP;
		}

		bool AlmostEquals(float3 Sample, float3 Mask)
		{
			//Allowing for a little bit of compression error.
			float MaskTolerance = 0.03f;

			if (
			Sample.r >= (Mask.r-MaskTolerance) &&
			Sample.r <= (Mask.r+MaskTolerance) &&
			Sample.g >= (Mask.g-MaskTolerance) &&
			Sample.g <= (Mask.g+MaskTolerance) &&
			Sample.b >= (Mask.b-MaskTolerance) &&
			Sample.b <= (Mask.b+MaskTolerance)
			)
			{			
				return true;
			}
			else
			{
				return false;
			}	


		}

		//Loops through all decals until it finds a decal matching the DecalMask colour in MIP6, then returns it's decal data.
 		//Used for getting weight of a decal to use for various types of blending effects outside of PS_Skin, like decaying clothing.

		DecalData GetDecalData(float3 DecalMask, uint DecalType, int To)
		{
			float3 DecalMIP6_1_1_Sample;

			const int TEXEL_COUNT_PER_DECAL = 15;
			int ToDataTexel = To * TEXEL_COUNT_PER_DECAL;
			static const uint MAX_VALUE = 65535;
			uint CurrentLOD = GetMIP6Level();
			DecalData Data;

			for ( int i = 0; i <= ToDataTexel; i += TEXEL_COUNT_PER_DECAL )
			{
				Data = GetDecalData( i );

				if (DecalType == DIFFUSE_DECAL)
				{
				DecalMIP6_1_1_Sample = GH_PdxTex2DArrayLoad( DecalDiffuseArray, int3(1, 1, int(Data._DiffuseIndex)), int(CurrentLOD)).rgb;
				}

				else if (DecalType == NORMAL_DECAL)
				{
				DecalMIP6_1_1_Sample = GH_PdxTex2DArrayLoad( DecalNormalArray, int3(1, 1, int(Data._NormalIndex)), int(CurrentLOD)).rgb;
				}

				else
				{
				DecalMIP6_1_1_Sample = GH_PdxTex2DArrayLoad( DecalPropertiesArray, int3(1, 1, int(Data._PropertiesIndex)), int(CurrentLOD)).rgb;
				}



						if ( Data._DiffuseIndex < MAX_VALUE )
						{

							if (AlmostEquals(DecalMIP6_1_1_Sample,DecalMask))
								{			
									break;
								}
						}
				
			}
			return Data;
		
		}


		void SPlitDecalRGBA(inout float4 Decal, inout float Weight )
		{
			//Below If statements normalize the weight value to 0.0 - 1.0 then tells which channel to use as alpha at increments of 25%.
			if (Weight < 0.25f)
			{
			Weight = Weight * 4.0f;
			Decal.a = Decal.r;
			}

			else if (Weight >= 0.25f && Weight < 0.5f)
			{
			Weight = (Weight - 0.25f) * 4.0f;
			Decal.a = Decal.g;
			}

			else if (Weight >= 0.5f && Weight < 0.75f)
			{
			Weight = (Weight - 0.5f) * 4.0f;
			Decal.a = Decal.b;
			}

			else
			{
			Weight = (Weight - 0.75f) * 4.0f;
			}
		}

		void SPlitDecal512(inout float4 Decal, inout float Weight, float2 UV , float DiffuseIndex )
		{
			//Below If statements normalize the weight value to 0.0 - 1.0 then tells which channel to use as alpha at increments of 25%.
			if (Weight < 0.25f)
			{
			Weight = Weight * 4.0f;
			Decal = PdxTex2D( DecalDiffuseArray, float3( (UV.x / 2.0f) , (UV.y / 2.0f) , DiffuseIndex ) );
			}

			else if (Weight >= 0.25f && Weight < 0.5f)
			{
			Weight = (Weight - 0.25f) * 4.0f;
			Decal = PdxTex2D( DecalDiffuseArray, float3( (UV.x / 2.0f) + 0.5f , (UV.y / 2.0f) , DiffuseIndex ) );
			}

			else if (Weight >= 0.5f && Weight < 0.75f)
			{
			Weight = (Weight - 0.5f) * 4.0f;
			Decal = PdxTex2D( DecalDiffuseArray, float3( (UV.x / 2.0f) , (UV.y / 2.0f) + 0.5f , DiffuseIndex ) );
			}

			else
			{
			Weight = (Weight - 0.75f) * 4.0f;
			Decal = PdxTex2D( DecalDiffuseArray, float3( (UV.x / 2.0f) + 0.5f , (UV.y / 2.0f) + 0.5f , DiffuseIndex ) );
			}
		}

		void SPlitDecalRGBA512(inout float4 Decal, inout float Weight, float2 UV , float DiffuseIndex )
		{
			//Below If statements normalize the weight value to 0.0 - 1.0 then tells which channel to use as alpha at increments of 6.25%.
			if (Weight < 0.0625f)
			{
			Weight = Weight * 16.0f;
			Decal = PdxTex2D( DecalDiffuseArray, float3( (UV.x / 2.0f) , (UV.y / 2.0f) , DiffuseIndex ) );
			Decal.a = Decal.r;
			}

			else if (Weight >= 0.0625f && Weight < 0.125f)
			{
			Weight = (Weight - 0.0625f) * 16.0f;
			Decal = PdxTex2D( DecalDiffuseArray, float3( (UV.x / 2.0f) + 0.5f , (UV.y / 2.0f) , DiffuseIndex ) );
			Decal.a = Decal.r;
			}

			else if (Weight >= 0.125f && Weight < 0.1875f)
			{
			Weight = (Weight - 0.125f) * 16.0f;
			Decal = PdxTex2D( DecalDiffuseArray, float3( (UV.x / 2.0f) , (UV.y / 2.0f) + 0.5f , DiffuseIndex ) );
			Decal.a = Decal.r;
			}

			else if (Weight >= 0.1875f && Weight < 0.25f)
			{
			Weight = (Weight - 0.1875f) * 16.0f;
			Decal = PdxTex2D( DecalDiffuseArray, float3( (UV.x / 2.0f) + 0.5f , (UV.y / 2.0f) + 0.5f , DiffuseIndex ) );
			Decal.a = Decal.r;
			}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////

			else if (Weight >= 0.25f && Weight < 0.3125f)
			{
			Weight = (Weight - 0.25f) * 16.0f;
			Decal = PdxTex2D( DecalDiffuseArray, float3( (UV.x / 2.0f) , (UV.y / 2.0f) , DiffuseIndex ) );
			Decal.a = Decal.g;
			}

			else if (Weight >= 0.3125f && Weight < 0.375f)
			{
			Weight = (Weight - 0.3125f) * 16.0f;
			Decal = PdxTex2D( DecalDiffuseArray, float3( (UV.x / 2.0f) + 0.5f , (UV.y / 2.0f) , DiffuseIndex ) );
			Decal.a = Decal.g;
			}

			else if (Weight >= 0.375f && Weight < 0.4375f)
			{
			Weight = (Weight - 0.375f) * 16.0f;
			Decal = PdxTex2D( DecalDiffuseArray, float3( (UV.x / 2.0f) , (UV.y / 2.0f) + 0.5f , DiffuseIndex ) );
			Decal.a = Decal.g;
			}

			else if (Weight >= 0.4375f && Weight < 0.5f)
			{
			Weight = (Weight - 0.4375f) * 16.0f;
			Decal = PdxTex2D( DecalDiffuseArray, float3( (UV.x / 2.0f) + 0.5f , (UV.y / 2.0f) + 0.5f , DiffuseIndex ) );
			Decal.a = Decal.g;
			}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////

			else if (Weight >= 0.5f && Weight < 0.5625f)
			{
			Weight = (Weight - 0.5f) * 16.0f;
			Decal = PdxTex2D( DecalDiffuseArray, float3( (UV.x / 2.0f) , (UV.y / 2.0f) , DiffuseIndex ) );
			Decal.a = Decal.b;
			}

			else if (Weight >= 0.5625f && Weight < 0.625f)
			{
			Weight = (Weight - 0.5625) * 16.0f;
			Decal = PdxTex2D( DecalDiffuseArray, float3( (UV.x / 2.0f) + 0.5f , (UV.y / 2.0f) , DiffuseIndex ) );
			Decal.a = Decal.b;
			}

			else if (Weight >= 0.625f && Weight < 0.6875f)
			{
			Weight = (Weight - 0.625f) * 16.0f;
			Decal = PdxTex2D( DecalDiffuseArray, float3( (UV.x / 2.0f) , (UV.y / 2.0f) + 0.5f , DiffuseIndex ) );
			Decal.a = Decal.b;
			}

			else if (Weight >= 0.6875f && Weight < 0.75f)
			{
			Weight = (Weight - 0.6875f) * 16.0f;
			Decal = PdxTex2D( DecalDiffuseArray, float3( (UV.x / 2.0f) + 0.5f , (UV.y / 2.0f) + 0.5f , DiffuseIndex ) );
			Decal.a = Decal.b;
			}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////

			else if (Weight >= 0.75f && Weight < 0.8125f)
			{
			Weight = (Weight - 0.75f) * 16.0f;
			Decal = PdxTex2D( DecalDiffuseArray, float3( (UV.x / 2.0f) , (UV.y / 2.0f) , DiffuseIndex ) );
			}

			else if (Weight >= 0.8125f && Weight < 0.875f)
			{
			Weight = (Weight - 0.8125f) * 16.0f;
			Decal = PdxTex2D( DecalDiffuseArray, float3( (UV.x / 2.0f) + 0.5f , (UV.y / 2.0f) , DiffuseIndex ) );
			}

			else if (Weight >= 0.875f && Weight < 0.9375f)
			{
			Weight = (Weight - 0.875f) * 16.0f;
			Decal = PdxTex2D( DecalDiffuseArray, float3( (UV.x / 2.0f) , (UV.y / 2.0f) + 0.5f , DiffuseIndex ) );
			}

			else
			{
			Weight = (Weight - 0.9375f) * 16.0f;
			Decal = PdxTex2D( DecalDiffuseArray, float3( (UV.x / 2.0f) + 0.5f , (UV.y / 2.0f) + 0.5f , DiffuseIndex ) );
			}
		}
		//EK2

	//////////////////////////////////////////////////////////////////////////////
/////////////////////////			DECODE MIPS			///////////////////////////////
	//////////////////////////////////////////////////////////////////////////////

		void DecodeDiffuseMIPs( uint InstanceIndex, inout float4 Sample, float2 UV, inout DecalData Data, inout float3 WeightMatrix, int CustomBodyPart )
		{

			uint CurrentLOD = 	GetMIP6Level();

/////////////////////////// CONTROL DECALS //////////////////////////////////

			// These decals will only be used to control effects somewhere else. Only their weight is saved.

			//R - CLOTHES DECAY CONTROL
			//G - SALT AND PEPPER HAIR CONTROL
			//B - FACEPAINT SELECTION DECAL
			//C - ATTACHMENT PATTERN PALETTE SELECTION
			//M - FUR COLOUR TRANSITION
			// float3 (0.5f,0.0f,0.0f) - Body hair colour selection
			//Y - SKELETON TRANSITION EFFECT - HEAD
			// float3 (0.0f,0.5f,0.0f) -SKELETON TRANSITION EFFECT - BODY

			float3 DecalMIP6_1_1_Sample = GH_PdxTex2DArrayLoad( DecalDiffuseArray, int3(1, 1, int(InstanceIndex)), int(CurrentLOD)).rgb;

			//RESERVE MIP6BL SAMPLE FOR FUTURE TO ALLOW EVEN MORE CONTROL DECALS BY CHECKING FOR COMBINATION WITH ABOVE, LIKE ADDING AN EXTRA BIT.


			 if (AlmostEquals(DecalMIP6_1_1_Sample,BLUE))
			 {	
			 	WeightMatrix.x = 0.0f;		
			 	WeightMatrix.y = Data._Weight;
			 	return;
			 }			

			 else if (AlmostEquals(DecalMIP6_1_1_Sample,float3 (0.5f,0.0f,0.0f)))
			 {	
			 	WeightMatrix.x = 0.0f;		
			 	WeightMatrix.z = Data._Weight;
			 	return;
			 }			


/////////////////////////// CUSTOM DECAL "BODYPARTS" //////////////////////////////////

			float3 DecalMIP6_5_1_Sample = GH_PdxTex2DArrayLoad( DecalDiffuseArray, int3(5, 1, int(InstanceIndex)), int(CurrentLOD)).rgb;

			//R - DO NOT DRAW THE DECAL - IT WILL BE USED OUTSIDE OF ADDDECALS FUNCTIONS FOR DECALS THAT CONTROL EFFECTS LIKE SALT N' PEPPER HAIR, AND CLOTHES DECAY
			if (AlmostEquals(DecalMIP6_5_1_Sample,RED))
			{			
				WeightMatrix.x = 0.0f;
				return;
			}

			//G - EYE DECAL - SO DECAL IS ONLY DRAWN ON EYES
			//If MIP6-TR is green, and bodypartindex is set to eyes apply decal.

			//This sets custom body parts. At 0 decals are applied like normal.
			//If set at anything other than 0 it will override where the decal is supposed to show
			// 0 - Head
			// 1 - Torso
			// 2 - Eyes, etc.

			//If not using a custom body part, but decal is encoded to display only on custom body parts list above, hide the decal.
			if (CustomBodyPart == 0)
			{
				if (AlmostEquals(DecalMIP6_5_1_Sample,GREEN))
				{			
					WeightMatrix.x = 0.0f;
					return;
				}
			}

			//If using custom body part, and the decal encoding matches the body part in the list, display the decal.
			else if (CustomBodyPart == 2)
			{
				if (AlmostEquals(DecalMIP6_5_1_Sample,GREEN))
				{			
					WeightMatrix.x = Data._Weight;
				}

				// Else if using custom body part, but the decal encoding doesn't match, hide decals.
				else
				{
					WeightMatrix.x = 0.0f;
					return;
				}
			}


/////////////////////////// CUSTOM UV MAPPING AND CHANNEL SPLITTING //////////////////////////////////			



			//Sample bottom left corner pixel of decal MIP5.
			//Used to tell the shader how to split the decal:
			//R - SPLIT INTO 4 DECALS THAT CHANGE EVERY 25% USING RGBA AS MASKS
			//G - SPLIT INTO 4 DECALS THAT CHANGE EVERY 25% BY SPLITTING IT INTO 4 512PX TEXTURES (ATLAS)
			//B - SPLIT INTO 16 DECALS BY COMBINING BOTH OF THE ABOVE
			float3 DecalMIP6_9_1_Sample = GH_PdxTex2DArrayLoad( DecalDiffuseArray, int3(9, 1, int(InstanceIndex)), int(CurrentLOD)).rgb;

			// If bottom left corner pixel is RED - Split into 4 decals every 25% of weight slider masked by channel
			if ( AlmostEquals(DecalMIP6_9_1_Sample, RED))
			{
				SPlitDecalRGBA(Sample, WeightMatrix.x );
			}

			// If bottom left corner pixel is GREEN - Split into 4 decals every 25% of weight slider by splitting it into 4x 512x512px decals.
			else if ( AlmostEquals(DecalMIP6_9_1_Sample, GREEN))
			{
				SPlitDecal512(Sample, WeightMatrix.x , UV , InstanceIndex );
			}

			// If bottom left corner pixel is BLUE - Split into 16 decals every 6.125% of weight slider by splitting it into 4x 512x512px decals & by splitting the channels.
			else if ( AlmostEquals(DecalMIP6_9_1_Sample, BLUE))
			{
				SPlitDecalRGBA512(Sample, WeightMatrix.x , UV , InstanceIndex );
			}


/////////////////////////// CUSTOM COLOUR OVERRIDES //////////////////////////////////	

			//Sample top right corner pixel of decal MIP5.
			//For overwriting color of decal 
			//R - OVERRIDE COLOUR BY SAMPLING A COLOUR PALETTE, CHANGES COLOUR WITH WEIGHT OF DECAL - SETS WEIGHT TO 100%
			//G - OVERRIDE COLOUR TO CURRENT SKIN COLOUR PALETTE
			//B - OVERRIDE COLOUR TO CURRENT HAIR COLOUR PALETTE
			//Y - OVERRIDE COLOUR TO CURRENT EYE COLOUR PALETTE
			//C - OVERRIDE COLOUR BY SAMPLING TOP LEFT CORNER OF MIP WHICH STORES A COLOUR PALETTE, CHANGES COLOUR WITH WEIGHT OF DECAL - KEEPS WEIGHT AS IS (ALLOWS ADJUSTING TRASPARENCY)
			//M - REPLACES DECAL COLOR WITH SAMPLED PALETTE AND SETS OPACITY TO 100%
			//float3 (0.5f,0.0f,0.0f) - BODY HAIR DECAL COLOUR CHANGE
			float3 DecalMIP6_13_1_Sample = GH_PdxTex2DArrayLoad( DecalDiffuseArray, int3(13, 1, int(InstanceIndex)), int(CurrentLOD)).rgb;

						// If top right corner pixel is RED - REPLACES DECAL COLOR WITH SAMPLED PALETTE FROM TOP LEFT OF THE DECAL AND SETS OPACITY TO 100%  - USE ANOTHER DECAL TO CONTROL THE STRENGTH
			if ( AlmostEquals(DecalMIP6_13_1_Sample,RED))
			{
				//Sample top left corner pixels of the image MIP5 as makeshift color palette for the facepaint, then apply that color and the correct alpha and set Weight (transperancy to 100%)
				float3 EKDecalPaletteColor = GH_PdxTex2DArrayLoad( DecalDiffuseArray, int3(int(WeightMatrix.y*16), 13, int(InstanceIndex)), int(CurrentLOD)).rgb;
				Sample.rgb = EKDecalPaletteColor;
				WeightMatrix.x = 1.0f;
			}

			// If top right corner pixel is GREEN - REPLACES DECAL COLOR WITH SKIN COLOR,
			else if ( AlmostEquals(DecalMIP6_13_1_Sample,GREEN))
			{
				Sample.rgb = vPaletteColorSkin.rgb;
			}

			// If top right corner pixel is BLUE - REPLACES DECAL COLOR WITH HAIR COLOR
			else if ( AlmostEquals(DecalMIP6_13_1_Sample,BLUE))
			{
				Sample.rgb = vPaletteColorHair.rgb;
			}

			// If top right corner pixel is YELLOW - REPLACES DECAL COLOR WITH EYE COLOR
			else if ( AlmostEquals(DecalMIP6_13_1_Sample,YELLOW))
			{
				Sample.rgb = vPaletteColorEyes.rgb;
			}

			// If top right corner pixel is CYAN - REPLACES DECAL COLOR WITH SAMPLED COLOR FROM BOTTOM LEFT OF THE MIP6 AND LEAVE OPACITY NORMALISED PER DECAL
			else if ( AlmostEquals(DecalMIP6_13_1_Sample,CYAN))
			{
				//Sample bottom left corner pixels of the image as color for the decal, then apply that color
				float3 EKDecalPaletteColor = GH_PdxTex2DArrayLoad( DecalDiffuseArray, int3(1, 13, int(InstanceIndex)), int(CurrentLOD)).rgb;
				Sample.rgb = EKDecalPaletteColor;
			}

			// If top right corner pixel is MAGENTA - REPLACES DECAL COLOR WITH SAMPLED PALETTE FROM TOP LEFT OF THE DECAL AND SETS OPACITY TO 100%
			else if ( AlmostEquals(DecalMIP6_13_1_Sample,MAGENTA))
			{

				//Sample top left corner pixels of the image MIP6 as makeshift color palette for the facepaint, then apply that color and the correct alpha and set Weight (transperancy to 100%)
				float3 EKDecalPaletteColor = GH_PdxTex2DArrayLoad( DecalDiffuseArray, int3(int(WeightMatrix.y*16), 13, int(InstanceIndex)), int(CurrentLOD)).rgb;
				Sample.rgb = EKDecalPaletteColor;
				WeightMatrix.x = 1.0f;
			}

			// Interpolates between a black and hair colour, for body/facial hair decals.
			else if ( AlmostEquals(DecalMIP6_13_1_Sample,float3 (0.5f,0.0f,0.0f)))
			{
				Sample.rgb = lerp (lerp(vPaletteColorHair.rgb, vPaletteColorHair.rgb*vPaletteColorSkin.rgb, 0.8f), float3(0.0f,0.0f,0.0f), WeightMatrix.z);
			}



/////////////////////////// CUSTOM BLEND MODES //////////////////////////////////	

			//Sample bottom right corner pixel of decal MIP5.
			//For assigning custom blendmodes
			//R - SCREEN 
			//G - ADDITIVE.
			float3 DecalMIP6_1_5_Sample = GH_PdxTex2DArrayLoad( DecalDiffuseArray, int3(1, 5, int(InstanceIndex)), int(CurrentLOD)).rgb;

			// If bottom right corner pixel is RED - CHANGE BLEND MODE TO SCREEN - EYE GLOW DECAL
			if ( AlmostEquals(DecalMIP6_1_5_Sample, RED))
			{
				Data._DiffuseBlendMode = BLEND_MODE_SCREEN;
			}

			// If bottom right corner pixel is GREEN - CHANGE BLEND MODE TO ADDITIVE - EYE WHITE GLOW DECAL
			else if ( AlmostEquals(DecalMIP6_1_5_Sample, GREEN))
			{
				Data._DiffuseBlendMode = BLEND_MODE_ADDITIVE;
			}

			// If bottom right corner pixel is BLUE - CHANGE BLEND MODE TO MAX VALUE - KHAJIIT FUR
			else if ( AlmostEquals(DecalMIP6_1_5_Sample, BLUE))
			{
				Data._DiffuseBlendMode = BLEND_MODE_MAX_VALUE;
			}

//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////


			WeightMatrix.x *= Sample.a;
		}



		void DecodePropertiesMIPs( uint InstanceIndex , inout DecalData Data, inout float Weight, int CustomBodyPart )
		{

			uint CurrentLOD = GetMIP6Level();


/////////////////////////// MIP SAMPLING //////////////////////////////////


			//Sample top right corner pixel of decal MIP6. - WIP
			//R - DO NOT DRAW THE DECAL - USED FOR DECALS THAT CONTROL EFFECTS LIKE SALT N' PEPPER HAIR, AND CLOTHES DECAY
			//G - EYE DECAL - SO DECAL IS ONLY DRAWN ON EYES - CustomBodyPart = 1
			//REST OF CHANNELS WILL BE USED TO ASSIGN DECALS TO OTHER TYPES OF ATTACHMENTS IF NEEDED.

			float3 DecalMIP6_5_1_Sample = GH_PdxTex2DArrayLoad( DecalPropertiesArray, int3(5, 1, int(InstanceIndex)), int(CurrentLOD)).rgb;


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////			


 			if (AlmostEquals(DecalMIP6_5_1_Sample, RED))
			{			
				Weight = 0.0f;
				return;
			}

			//If MIP6-TR is green, and bodypartindex is set to eyes apply decal.
			if (CustomBodyPart == 0)
			{
				if (AlmostEquals(DecalMIP6_5_1_Sample,GREEN))
				{			
					Weight = 0.0f;
					return;
				}
			}

			//If using custom body part, and the decal encoding matches the body part in the list, display the decal.
			else if (CustomBodyPart == 2)
			{
				if (AlmostEquals(DecalMIP6_5_1_Sample,GREEN))
				{			
					Weight = Data._Weight;
				}

				// Else if using custom body part, but the decal encoding doesn't match, hide decals.
				else
				{
					Weight = 0.0f;
			 		return;
				}
			}

		}


		void AddDecals( inout float4 Diffuse, inout float3 Normals, inout float4 Properties, float2 UV, uint InstanceIndex, int From, int To /* EK2 - CUSTOM BODY PART */ , int CustomBodyPart )
		{
			// Body part index is scripted on the mesh asset and should match ECharacterPortraitPart
			uint BodyPartIndex = GetBodyPartIndex( InstanceIndex );

			const int TEXEL_COUNT_PER_DECAL = 15;
			int FromDataTexel = From * TEXEL_COUNT_PER_DECAL;
			int ToDataTexel = To * TEXEL_COUNT_PER_DECAL;

			static const uint MAX_VALUE = 65535;

			//EK2
			//Create a matrix for decal weights. Add more as needed (up to 16 in 4x4)
			//This is to allow using multiple genes to control a single effect.
			//For example x controls which facepaint design is used, and y will select a colour.

			//x = Decal opacity
			//y = Facepaint Selection
			float3 WeightMatrix = float3 (0.0f, 0.0f, 0.0f);
			//EK2

			// Sorted after priority
			for ( int i = FromDataTexel; i <= ToDataTexel; i += TEXEL_COUNT_PER_DECAL )
			{
				DecalData Data = GetDecalData( i );



				// Max index => unused
				if ( Data._BodyPartIndex == BodyPartIndex || CustomBodyPart != 0)
				{

					//EK2
					WeightMatrix.x = Data._Weight;
					//EK2

					// Assumes that the cropped area size corresponds to the atlas factor
					float AtlasFactor = 1.0f / Data._AtlasSize;
					if ( ( ( UV.x >= Data._UVOffset.x ) && ( UV.x < ( Data._UVOffset.x + AtlasFactor ) ) ) &&
						 ( ( UV.y >= Data._UVOffset.y ) && ( UV.y < ( Data._UVOffset.y + AtlasFactor ) ) ) )
					{
						float2 DecalUV;
						float TilingMaskSample = 1;
						//UVTiling is incompatible with Decal Atlases, so we only use one of them. 
						//If a tiling value is provided, the tiling feature will be used.
						if ( Data._UVTiling.x == 1 && Data._UVTiling.y == 1 )
						{
							DecalUV = ( UV - Data._UVOffset ) + ( Data._AtlasPos * AtlasFactor );
						} 
						else
						{
							DecalUV = UV * Data._UVTiling;
							float2 TilingMaskUV = ( UV - Data._UVOffset ) + ( Data._AtlasPos * AtlasFactor );
							TilingMaskSample = PdxTex2D( DecalPropertiesArray, float3( TilingMaskUV, Data._PropertiesIndex ) ).r;
						}

						if ( Data._DiffuseIndex < MAX_VALUE )
						{

							// MOD(ek2)
							WeightMatrix.x *= TilingMaskSample;
							// END MOD

							//EK2
							//Sample LOD0 for eyes to avoid fading problems. TODO: Encode Mips to lower level to avoid this hack.
							#ifdef EYE_DECAL
							float4 DiffuseSample = PdxTex2DLod0( DecalDiffuseArray, float3( DecalUV, Data._DiffuseIndex ) );
							#else

							float4 DiffuseSample = PdxTex2D( DecalDiffuseArray, float3( DecalUV, Data._DiffuseIndex ) );
							#endif
							

							DecodeDiffuseMIPs( Data._DiffuseIndex, DiffuseSample, DecalUV , Data, WeightMatrix, CustomBodyPart  );	

							Diffuse = BlendDecal( Data._DiffuseBlendMode, Diffuse, DiffuseSample, WeightMatrix.x );
							//END EK2
						}

						if ( Data._NormalIndex < MAX_VALUE )
						{
							

							float3 NormalSample = UnpackDecalNormal( PdxTex2D( DecalNormalArray, float3( DecalUV, Data._NormalIndex ) ), WeightMatrix.x );

							Normals = BlendDecal( Data._NormalBlendMode, float4( Normals, 0.0f ), float4( NormalSample, 0.0f ), WeightMatrix.x ).xyz;
						}

						if ( Data._PropertiesIndex < MAX_VALUE )
						{
							//EK2
							//Sample LOD0 for eyes to avoid fading problems. TODO: Encode Mips to lower level to avoid this hack.
							#ifdef EYE_DECAL
							float4 PropertiesSample = PdxTex2DLod0( DecalPropertiesArray, float3( DecalUV, Data._PropertiesIndex ) );
							#else

							float4 PropertiesSample = PdxTex2D( DecalPropertiesArray, float3( DecalUV, Data._PropertiesIndex ) );
							#endif

							


							//EK2

							DecodePropertiesMIPs( Data._PropertiesIndex , Data, WeightMatrix.x, CustomBodyPart );	

							//END EK2
							Properties = BlendDecal( Data._PropertiesBlendMode, Properties, PropertiesSample, WeightMatrix.x );
						}
					}
				}
			}

			Normals = normalize( Normals );
		}
	]]
}
