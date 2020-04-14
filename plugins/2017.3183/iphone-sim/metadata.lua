local metadata =
{
	plugin =
	{
		format = "staticLibrary",

		-- This is the name without the 'lib' prefix.
		-- In this case, the static library is called: libSTATIC_LIB_NAME.a
		staticLibs = { "InMobiPlugin", "InMobiSDK", "z" }, 

		frameworks = { "WebKit" },
		frameworksOptional = { "AdSupport", "SafariServices" },
	}
}

return metadata
