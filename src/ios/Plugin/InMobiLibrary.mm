//----------------------------------------------------------------------------
// InMobiLibrary.mm
//
// Copyright (c) 2016 Corona Labs. All rights reserved.
//----------------------------------------------------------------------------

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AVFoundation/AVFoundation.h>
#import <AdSupport/ASIdentifierManager.h>

#import "CoronaRuntime.h"
#import "CoronaAssert.h"
#import "CoronaEvent.h"
#import "CoronaLua.h"
#import "CoronaLuaIOS.h"
#import "CoronaLibrary.h"

// Plugin specific imports
#import "InMobiLibrary.h"
#import <InMobiSDK/IMSdk.h>
#import <InMobiSDK/IMCommonConstants.h>
#import <InMobiSDK/IMBanner.h>
#import <InMobiSDK/IMBannerDelegate.h>
#import <InMobiSDK/IMInterstitial.h>
#import <InMobiSDK/IMInterstitialDelegate.h>
#import <InMobiSDK/IMRequestStatus.h>

// Macros
#define UTF8Str(str) [NSString stringWithUTF8String:str]
#define isUTF8StrEqualToNSString(str1, str2) [[NSString stringWithUTF8String:str1] isEqualToString:str2]

// Add the missing placement id to interstitial ads
@interface IMInterstitial (additions)
@property (nonatomic, assign) long long placementId;
@end

// The Plugin Delegate
@interface InMobiDelegate : UIViewController <IMBannerDelegate, IMInterstitialDelegate>
@property (nonatomic, assign) id<CoronaRuntime> fRuntime;
@property (nonatomic, assign) CoronaLuaRef fListener;
@property (nonatomic, assign) NSString *kEvent;
@property (nonatomic, assign) NSString *kProviderName;
@end

//----------------------------------------------------------------------------

class InMobiLibrary
{
  public:
    typedef InMobiLibrary Self;
  
  public:
		static const char kName[];
		static const char kVersion[];
		static const char kEvent[];
		static const char kProviderName[];
  
  protected:
		InMobiLibrary();
  
  public:
		bool Initialize(void *platformContext);
  
  public:
		static int Open(lua_State *L);
  
  protected:
		static int Finalizer(lua_State *L);
  
  public:
		static Self *ToLibrary(lua_State *L);
  
  public:
		static int init(lua_State *L);
		static int setUserDetails(lua_State *L);
		static int load(lua_State *L);
		static int isLoaded(lua_State *L);
		static int show(lua_State *L);
		static int hide(lua_State *L);
  
  public:
		CoronaLuaRef GetListener() const { return fListener; }
  
  public:
		UIViewController* GetAppViewController() const { return fAppViewController; }
  
  private:
		CoronaLuaRef fListener;
		UIViewController *fAppViewController;
};

//----------------------------------------------------------------------------

// This corresponds to the name of the library, e.g. [Lua] require "plugin.library"
const char InMobiLibrary::kName[] = "plugin.inMobi";
// The plugins version
const char InMobiLibrary::kVersion[] = "1.1.8";
const char InMobiLibrary::kEvent[] = "adsRequest";
const char InMobiLibrary::kProviderName[] = "inMobi";
// Constants
static NSString * const BANNER_AD_NAME = @"banner";
static NSString * const INTERSTITIAL_AD_NAME = @"interstitial";
// Dictionary keys
static NSString * const HAS_LOADED_KEY = @"hasLoaded";
static NSString * const AD_VIEW_KEY = @"adView";
static NSString * const AD_UNIT_TYPE_KEY = @"adType";
static NSString * const BANNER_WIDTH_KEY = @"bannerWidth";
static NSString * const BANNER_HEIGHT_KEY = @"bannerHeight";
static NSString * const REWARD_COMPLETED = @"rewardComplete";
// Event names
NSString * const LOADED_EVENT = @"loaded";
NSString * const FAILED_EVENT = @"failed";
NSString * const DISPLAYED_EVENT = @"displayed";
NSString * const CLICKED_EVENT = @"clicked";
NSString * const HIDDEN_EVENT = @"closed";
// Delegate instance pointer
static InMobiDelegate *inMobiDelegate = nil;
// InMobi ads dictionary
static NSMutableDictionary *inMobiAds = nil;

InMobiLibrary::InMobiLibrary()
:	fListener(NULL)
{
}

bool
InMobiLibrary::Initialize(void *platformContext)
{
  bool result = (inMobiDelegate == nil);
  
  if (result)
  {
    id<CoronaRuntime> runtime = (id<CoronaRuntime>)platformContext;
    fAppViewController = runtime.appViewController;
    
    // Initialise the delegate
    inMobiDelegate = [[InMobiDelegate alloc] init];
    // Assign the delegate's runtime pointer
    inMobiDelegate.fRuntime = runtime;
    // Assign the InMobi delegate's Lua event name
    inMobiDelegate.kEvent = [[NSString alloc] initWithUTF8String:kEvent];
    // Assign the InMobi delegate's Lua event provider name
    inMobiDelegate.kProviderName = [[NSString alloc] initWithUTF8String:kProviderName];
    // Initialise the InMobi ads dictionary
    inMobiAds = [[NSMutableDictionary alloc] init];
  }
  
  return result;
}

// Open the library
int
InMobiLibrary::Open(lua_State *L)
{
  // Register __gc callback
  const char kMetatableName[] = __FILE__; // Globally unique string to prevent collision
  CoronaLuaInitializeGCMetatable(L, kMetatableName, Finalizer);
  
  //CoronaLuaInitializeGCMetatable( L, kMetatableName, Finalizer );
  void *platformContext = CoronaLuaGetContext(L);
  
  // Set library as upvalue for each library function
  Self *library = new Self;
  
  if (library->Initialize(platformContext))
  {
    // Functions in library
    static const luaL_Reg kFunctions[] =
    {
      {"init", init},
      {"setUserDetails", setUserDetails},
      {"load", load},
      {"isLoaded", isLoaded},
      {"show", show},
      {"hide", hide},
      {NULL, NULL}
    };
    
    // Register functions as closures, giving each access to the
    // 'library' instance via ToLibrary()
    {
      CoronaLuaPushUserdata(L, library, kMetatableName);
      luaL_openlib(L, kName, kFunctions, 1); // leave "library" on top of stack
    }
  }
  
  return 1;
}

int
InMobiLibrary::Finalizer(lua_State *L)
{
  Self *library = (Self *)CoronaLuaToUserdata(L, 1);
  // Remove the listener
  CoronaLuaDeleteRef(L, library->GetListener());
  
  // Remove the inMobiAds dict
  [inMobiAds release];
  inMobiAds = nil;
  
  // Remove the delegate
  [inMobiDelegate release];
  inMobiDelegate = nil;
  
  delete library;
  
  return 0;
}

InMobiLibrary *
InMobiLibrary::ToLibrary(lua_State *L)
{
  // library is pushed as part of the closure
  Self *library = (Self *)CoronaLuaToUserdata(L, lua_upvalueindex(1));
  return library;
}

// Get the corona sdk version
static const char *
getCoronaVersion(lua_State *L)
{
  lua_getglobal(L, "system");
  lua_getfield(L, -1, "getInfo");
  lua_pushstring(L, "build");
  lua_call(L, 1, 1);
  const char *buildString = lua_tostring(L, -1);
  lua_pop(L, 2);
  
  return buildString;
}

// Handle the beacon response
static int perkBeaconListener(lua_State *L)
{
  // NOP - We currently do anything on failure or success
  //lua_getfield(L, -1, "response");
  //NSLog(@"Network listener: response: %s", lua_tostring(L, -1));
  
  return 0;
}

// Set the Corona atrribution (so delivered Ads will show as coming from Corona)
static NSDictionary *coronaAttributionExtras(lua_State *L)
{
  // Get the Corona SDK version
  NSString *coronaSDKVersion = UTF8Str(getCoronaVersion(L));
  // The Corona extras
  NSDictionary *coronaExtras = nil;
  
  // If the coronaSDKVersion isn't nil
  if (coronaSDKVersion != nil)
  {
    coronaExtras = [NSDictionary dictionaryWithObjectsAndKeys:
      @"p_corona", @"tp",
      coronaSDKVersion, @"tp-ver",
      nil
    ];
  }
  
  return coronaExtras;
}


// [Lua] inMobi.init(listener, options)
int
InMobiLibrary::init(lua_State *L)
{
  // Corona namespace
  using namespace Corona;
  // Context
  Self *context = ToLibrary(L);
  
  // If context is valid
  if (context)
  {
    Self& library = *context;
    
    // If the listener is null
    if (library.GetListener() == NULL)
    {
      // The inMobi account id
      const char *inMobiAccountId = NULL;
      // Log level
      const char *logLevel = NULL;
      NSNumber *hasUserConsent = nil;
      
      // Set the delegate's listenerRef to reference the Lua listener function (if it exists)
      if (CoronaLuaIsListener(L, 1, kProviderName))
      {
        // Assign the listener references
        library.fListener = CoronaLuaNewRef(L, 1);
        inMobiDelegate.fListener = library.GetListener();
      }
      // Listener not passed, throw error
      else
      {
        CoronaLuaError(L, "ERROR: inMobi.init() listener expected, got %s", lua_typename(L, lua_type(L, 1)));
        return 0;
      }
      
      // Get the options table
      if (lua_type(L, 2) == LUA_TTABLE)
      {
        // Get the accountId field
        lua_getfield(L, -1, "accountId");
        
        // Ensure the accountId is a string
        if (lua_type(L, -1) == LUA_TSTRING)
        {
          inMobiAccountId = lua_tostring(L, -1);
        }
        else
        {
          CoronaLuaError(L, "ERROR: inMobi.init() options.accountId (string) expected, got %s", lua_typename(L, lua_type(L, -1)));
          return 0;
        }
        // Pop the accountId key
        lua_pop(L, 1);
        
        // Get the logLevel field
        lua_getfield(L, -1, "logLevel");
        
        // Ensure the logLevel is a string
        if (lua_type(L, -1) == LUA_TSTRING)
        {
          logLevel = lua_tostring(L, -1);
        }
        // Pop the logLevel field
        lua_pop(L, 1);

          // Get the logLevel field
          lua_getfield(L, -1, "hasUserConsent");

          // Ensure the accountId is a string
          if (lua_type(L, -1) == LUA_TBOOLEAN)
          {
              hasUserConsent = [NSNumber numberWithBool:lua_toboolean(L, -1)];
          }
          // Pop the logLevel field & options table
          lua_pop(L, 2);
      }
      else
      {
        CoronaLuaError(L, "ERROR: inMobi.init() options (table) expected, got %s", lua_typename(L, lua_type(L, 2)));
        return 0;
      }


        NSNumber *gdpr = @1;
        NSString *consent = @"";

        if (hasUserConsent != nil) {
            if ([hasUserConsent boolValue]) {
                consent = @"true";
            } else {
                consent = @"false";
            }
        } else {
            gdpr = @0;
        }

        //consent value needs to be collected from the end user
        NSMutableDictionary *consentDict=[[NSMutableDictionary alloc]init];
        [consentDict setObject:consent forKey:IM_GDPR_CONSENT_AVAILABLE];
        [consentDict setObject:gdpr forKey:@"gdpr"];
        //Initialize InMobi SDK with the users account ID
        [IMSdk initWithAccountID:UTF8Str(inMobiAccountId) consentDictionary:consentDict];
      
      // Set the log level
      if (logLevel != NULL)
      {
        if (strcmp(logLevel, "debug") == 0)
        {
          [IMSdk setLogLevel:kIMSDKLogLevelDebug];
        }
        else if (strcmp(logLevel, "error") == 0)
        {
          [IMSdk setLogLevel:kIMSDKLogLevelError];
        }
      }
      
      // Log plugin version to device console
      NSLog(@"%s: %s (SDK %@)", kName, kVersion, [IMSdk getVersion]);
      
      // Dispatch an init event
      [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        // Dispatch the init event
        CoronaLuaNewEvent(L, kEvent);
        
        // Push the status string
        lua_pushstring(L, "init");
        lua_setfield(L, -2, CoronaEventPhaseKey());
        
        // Provider
        lua_pushstring(L, kProviderName);
        lua_setfield(L, -2, CoronaEventProviderKey());
        
        // Dispatch the event
        CoronaLuaDispatchEvent(L, library.GetListener(), 1);
      }];
    }
  }
  
  return 0;
}

// [Lua] inMobi.setUserDetails(options)
int
InMobiLibrary::setUserDetails(lua_State *L)
{
  // Corona namespace
  using namespace Corona;
  // Context
  Self *context = ToLibrary(L);
  
  // If context is valid
  if (context)
  {
    // If the userDetails is a table
    if (lua_type(L, 1) == LUA_TTABLE)
    {
      // Get the gender field
      lua_getfield(L, -1, "gender");
      
      // If gender is a string
      if (lua_type(L, -1) == LUA_TSTRING)
      {
        // Get the user gender
        const char *gender = lua_tostring(L, -1);
        
        // Set the gender based on the passed type
        if (strcmp(gender, "male") == 0)
        {
          [IMSdk setGender:kIMSDKGenderMale];
        }
        else if (strcmp(gender, "female") == 0)
        {
          [IMSdk setGender:kIMSDKGenderFemale];
        }
      }
      lua_pop(L, 1);
      
      // Get the postCode field
      lua_getfield(L, -1, "postCode");
      
      // If postCode is a string
      if (lua_type(L, -1) == LUA_TSTRING)
      {
        // Get the postCode
        const char *postCode = lua_tostring(L, -1);
        
        // If the postCode is less than 1 character
        if (strlen(postCode) == 0)
        {
          CoronaLuaError(L, "ERROR: inMobi.setUserDetails(options) options.postCode (string) must not be empty. (eg. '24533')");
          return 0;
        }
        
        // Set the post code
        [IMSdk setPostalCode:UTF8Str(postCode)];
      }
      lua_pop(L, 1);
      
      // Get the phoneAreaCode field
      lua_getfield(L, -1, "phoneAreaCode");
      
      // If phoneAreaCode is a string
      if (lua_type(L, -1) == LUA_TSTRING)
      {
        // Get the phoneArea code
        const char *phoneAreaCode = lua_tostring(L, -1);
        
        // If the phoneAreaCode is less than 1 character
        if (strlen(phoneAreaCode) == 0)
        {
          CoronaLuaError(L, "ERROR: inMobi.setUserDetails(options) options.phoneAreaCode (string) must not be empty. (eg. '353')");
          return 0;
        }
        
        // Set the phoneArea code
        [IMSdk setAreaCode:UTF8Str(phoneAreaCode)];
      }
      lua_pop(L, 1);
      
      // Get the language field
      lua_getfield(L, -1, "language");
      
      // If language is a string
      if (lua_type(L, -1) == LUA_TSTRING)
      {
        // Get the language
        const char *language = lua_tostring(L, -1);
        
        // If the language is less than 1 character
        if (strlen(language) == 0)
        {
          CoronaLuaError(L, "ERROR: inMobi.setUserDetails(options) options.language (string) must not be empty. (eg. 'eng')");
          return 0;
        }
        
        // Set the language
        [IMSdk setLanguage:UTF8Str(language)];
      }
      lua_pop(L, 1);
      
      // Get the birthYear field
      lua_getfield(L, -1, "birthYear");
      
      // If birthYear is a number
      if (lua_type(L, -1) == LUA_TNUMBER)
      {
        // Get the users birth year
        NSNumber *birthYear = [NSNumber numberWithInt:lua_tonumber(L, -1)];
        
        // Get the length of the birthYear (must be 4 digits long)
        if ([[birthYear stringValue] length] != 4)
        {
          CoronaLuaError(L, "ERROR: inMobi.setUserDetails(options) options.birthYear (number) must be a number with at least 4 digits (eg. 1991)");
          return 0;
        }
        
        // Set the birth year
        [IMSdk setYearOfBirth:[birthYear integerValue]];
      }
      lua_pop(L, 1);
      
      // Get the age field
      lua_getfield(L, -1, "age");
      
      // If age is a number
      if (lua_type(L, -1) == LUA_TNUMBER)
      {
        // Get the users age
        unsigned short age = lua_tonumber(L, -1);
        
        // If the users age is less than 1
        if (age < 1)
        {
          CoronaLuaError(L, "ERROR: inMobi.setUserDetails(options) options.age (number) must be equal to, or greater than 1 (years old). (eg. 25)");
          return 0;
        }
        
        // Set the age
        [IMSdk setAge:age];
      }
      lua_pop(L, 1);
      
      // Get the age group field
      lua_getfield(L, -1, "ageGroup");
      
      // If ageGroup is a string
      if (lua_type(L, -1) == LUA_TSTRING)
      {
        // Get the users age group
        const char *ageGroup = lua_tostring(L, -1);
        // The InMobi SDK age group (default to below 18)
        IMSDKAgeGroup imAgeGroup = kIMSDKAgeGroupBelow18;
        
        // If the users age group is less than 1 character
        if (strlen(ageGroup) == 0)
        {
          CoronaLuaError(L, "ERROR: inMobi.setUserDetails(options) options.ageGroup (string) must not be empty");
          return 0;
        }
        
        // Set the correct age group based on the value from Lua
        if (strcmp(ageGroup, "below18") == 0)
        {
          imAgeGroup = kIMSDKAgeGroupBelow18;
        }
        else if (strcmp(ageGroup, "18to24") == 0)
        {
          imAgeGroup = kIMSDKAgeGroupBetween18And24;
        }
        else if (strcmp(ageGroup, "25to29") == 0)
        {
          imAgeGroup = kIMSDKAgeGroupBetween25And29;
        }
        else if (strcmp(ageGroup, "30to34") == 0)
        {
          imAgeGroup = kIMSDKAgeGroupBetween30And34;
        }
        else if (strcmp(ageGroup, "35to44") == 0)
        {
          imAgeGroup = kIMSDKAgeGroupBetween35And44;
        }
        else if (strcmp(ageGroup, "45to54") == 0)
        {
          imAgeGroup = kIMSDKAgeGroupBetween45And54;
        }
        else if (strcmp(ageGroup, "55to65") == 0)
        {
          imAgeGroup = kIMSDKAgeGroupBetween55And65;
        }
        else if (strcmp(ageGroup, "above65") == 0)
        {
          imAgeGroup = kIMSDKAgeGroupAbove65;
        }

        // Set the age group
        [IMSdk setAgeGroup:imAgeGroup];
      }
      lua_pop(L, 1);
      
      // Get the users education field
      lua_getfield(L, -1, "education");
      
      // If education is a string
      if (lua_type(L, -1) == LUA_TSTRING)
      {
        // Get the users education
        const char *education = lua_tostring(L, -1);
        // The InMobi SDK education (default to high school or less)
        IMSDKEducation imEducation = kIMSDKEducationHighSchoolOrLess;
        
        // If the users education is less than 1 character
        if (strlen(education) == 0)
        {
          CoronaLuaError(L, "ERROR: inMobi.setUserDetails(options) options.education (string) must not be empty. (eg. 'highSchoolOrLess')");
          return 0;
        }
        
        // Set the correct education based on the value from Lua
        if (strcmp(education, "highSchoolOrLess") == 0)
        {
          imEducation = kIMSDKEducationHighSchoolOrLess;
        }
        else if (strcmp(education, "collegeOrGraduate") == 0)
        {
          imEducation = kIMSDKEducationCollegeOrGraduate;
        }
        else if (strcmp(education, "graduateOrAbove") == 0)
        {
          imEducation = kIMSDKEducationPostGraduateOrAbove;
        }
        
        // Set the education
        [IMSdk setEducation:imEducation];
      }
      lua_pop(L, 1);
      
      // Get the userInterests field
      lua_getfield(L, -1, "userInterests");
      
      // If userInterests is a table
      if (lua_type(L, -1) == LUA_TTABLE)
      {
        // The valid user interests
        const char *validUserInterests[11] = {"Business", "Tech", "Travel", "Shopping", "Entertainment", "Fashion", "Fitness", "Foodie", "Gamer", "Jobs", "Sports"};
        // The user interests string
        NSString *userInterests = @"";
        
        // Get each interest from the table
        for (int i = 0; i < lua_objlen(L, 2); i++)
        {
          // Get the current object
          lua_rawgeti(L, 2, (i + 1));
          
          // If the current user interest is a string
          if (lua_type(L, -1) == LUA_TSTRING)
          {
            // Is the current user interest valid?
            bool isCurrentInterestValid = false;
            // Get the current user interest
            const char *currentInterest = lua_tostring(L, -1);
            
            // Loop over the validUserInterests
            for (int j = 0; j < 11; j++)
            {
              // Ensure that the current user interest matches one of the valid user interest options
              if (strcmp(currentInterest, validUserInterests[j]) == 0)
              {
                // Append the user interest
                if (i == 0)
                {
                  userInterests = [userInterests stringByAppendingFormat:@"%s", currentInterest];
                }
                else
                {
                  userInterests = [userInterests stringByAppendingFormat:@", %s", currentInterest];
                }
                
                // This is a valid user interest
                isCurrentInterestValid = true;
                break;
              }
            }
            
            // If the current user interest isn't valid, then show an error
            if (!isCurrentInterestValid)
            {
              CoronaLuaError(L, "ERROR: inMobi.setUserDetails(options) options.userInterests - found invalid user interest");
              return 0;
            }
          }
          
          // Set the user interests
          if ([userInterests length] > 1)
          {
            [IMSdk setInterests:userInterests];
          }
        }
      }
      lua_pop(L, 1);
    }
    else
    {
      CoronaLuaError(L, "ERROR: inMobi.setUserDetails(options) options (table) expected, got %s", lua_typename(L, lua_type(L, 1)));
      return 0;
    }
  }
  
  return 0;
}

// [Lua] inMobi.load(adUnitType, placementId, [options])
int
InMobiLibrary::load(lua_State *L)
{
  // Corona namespace
  using namespace Corona;
  // Context
  Self *context = ToLibrary(L);
  
  // If context is valid
  if (context)
  {
    // The Ad unit type
    const char *adUnitType = NULL;
    // The Ad placement id
    const char *placementId = NULL;
    // The banner's width/height
    int bannerWidth = 320;
    int bannerHeight = 50;
    // Should a banner auto refresh?
    bool shouldBannerAutoRefresh = false;
    // The banners refresh interval
    int bannerRefreshInterval = 60;
    Self& library = *context;
    
    // Ensure that .init() has been called first (fListener will not be null if init is called, as it's a required param)
    if (library.GetListener() == NULL)
    {
      CoronaLuaError(L, "ERROR: inMobi.load(adUnitType, placementId) you must call inMobi.init() before making any other inMobi.* Api calls");
      return 0;
    }
    
    // Get the Ad unit type
    if (lua_type(L, 1) == LUA_TSTRING)
    {
      adUnitType = lua_tostring(L, 1);
    }
    else
    {
      CoronaLuaError(L, "ERROR: inMobi.load(adUnitType, placementId) adUnitType (string) expected, got %s", lua_typename(L, lua_type(L, 1)));
      return 0;
    }
    
    // Get the placement id
    if (lua_type(L, 2) == LUA_TSTRING)
    {
      placementId = lua_tostring(L, 2);
    }
    else
    {
      CoronaLuaError(L, "ERROR: inMobi.load(adUnitType, placementId) placementId (string) expected, got %s", lua_typename(L, lua_type(L, 2)));
      return 0;
    }
    
    // Get the banner size (optional arg)
    if (lua_type(L, 3) == LUA_TTABLE)
    {
      // Get the banner width
      lua_getfield(L, -1, "width");
      
      // Ensure the banner width is a number
      if (lua_type(L, -1) == LUA_TNUMBER)
      {
        bannerWidth = (int)lua_tonumber(L, -1);
      }
      // Pop the width key
      lua_pop(L, 1);
      
      // Get the banner height
      lua_getfield(L, -1, "height");
      
      // Ensure the banner height is a number
      if (lua_type(L, -1) == LUA_TNUMBER)
      {
        bannerHeight = (int)lua_tonumber(L, -1);
      }
      // Pop the height key
      lua_pop(L, 1);
      
      // Get the banner auto refresh bool
      lua_getfield(L, -1, "autoRefresh");
      
      // Ensure the banner height is a bool
      if (lua_type(L, -1) == LUA_TBOOLEAN)
      {
        shouldBannerAutoRefresh = lua_toboolean(L, -1);
      }
      // Pop the autoRefresh key
      lua_pop(L, 1);
      
      // Get the banner refresh interval
      lua_getfield(L, -1, "refreshInterval");
      
      // Ensure the banner height is a number
      if (lua_type(L, -1) == LUA_TNUMBER)
      {
        bannerRefreshInterval = (int)lua_tonumber(L, -1);
      }
      // Pop the refreshInterval key and options table
      lua_pop(L, 2);
    }
    
    // If the Ad hasn't already been loaded
    if (![inMobiAds objectForKey:UTF8Str(placementId)])
    {
      // Get the app view controller
      UIViewController *appViewController = library.GetAppViewController();
      // Create a dictionary for this Ad
      NSMutableDictionary *adDict = [[NSMutableDictionary alloc] init];
      // Get the corona attribution extras
      NSDictionary *attributionExtras = coronaAttributionExtras(L);
      
      // Create the correct ad based on the adUnitType
      
      // Load a banner Ad
      if (isUTF8StrEqualToNSString(adUnitType, BANNER_AD_NAME))
      {
        // Create the Ad object
        IMBanner *bannerAd = [[IMBanner alloc] initWithFrame:CGRectMake(0, -100, bannerWidth, bannerHeight) placementId:[UTF8Str(placementId) longLongValue]];
        // Set the Ads delegate
        bannerAd.delegate = inMobiDelegate;
        // Set if the banner should auto refresh
        [bannerAd shouldAutoRefresh:shouldBannerAutoRefresh];
        // Set the banners refresh interval
        [bannerAd setRefreshInterval:bannerRefreshInterval];
        // Add the Banner Ad to the view
        [appViewController.view addSubview:bannerAd];
        // Hide the Ad
        bannerAd.hidden = true;
        // If the attribution extras are not nil
        if (attributionExtras != nil)
        {
          // Set the extras
          bannerAd.extras = attributionExtras;
        }
        // Load the Ad
        [bannerAd load];
        // Add the Ads width/height to the adDict
        [adDict setObject:[NSNumber numberWithInt:bannerWidth] forKey:BANNER_WIDTH_KEY];
        [adDict setObject:[NSNumber numberWithInt:bannerHeight] forKey:BANNER_HEIGHT_KEY];
        // Add this Ad to the adDict
        [adDict setObject:bannerAd forKey:AD_VIEW_KEY];
      }
      // Load an interstitial Ad
      else if (isUTF8StrEqualToNSString(adUnitType, INTERSTITIAL_AD_NAME))
      {
        // Create the Ad object
        IMInterstitial *interstitialAd = [[IMInterstitial alloc] initWithPlacementId:[UTF8Str(placementId) longLongValue]];
        // Set the Ads delegate
        interstitialAd.delegate = inMobiDelegate;
        interstitialAd.placementId = [UTF8Str(placementId) longLongValue];
        // If the attribution extras are not nil
        if (attributionExtras != nil)
        {
          // Set the extras
          interstitialAd.extras = attributionExtras;
        }
        
        // Load the Ad
        [interstitialAd load];
        // Add this Ad to the adDict
        [adDict setObject:interstitialAd forKey:AD_VIEW_KEY];
      }
      else
      {
        [adDict release];
        adDict = nil;
        CoronaLuaError(L, "ERROR: Unsupported Ad unit type");
        return 0;
      }
      
      // Only add this Ads properties to the adDict/inMobiAds dict if it was created successfully
      if (adDict != nil)
      {
        // Set the Ad's unit type
        [adDict setObject:UTF8Str(adUnitType) forKey:AD_UNIT_TYPE_KEY];
        // Set the Ad as not loaded by default
        [adDict setObject:[NSNumber numberWithBool:false] forKey:HAS_LOADED_KEY];
        // Add the adDict to the inMobiAds dict
        [inMobiAds setObject:adDict forKey:UTF8Str(placementId)];
      }
    }
    else {
      CoronaLuaError(L, "WARNING: placementId '%s' already loaded", placementId);
      return 0;
    }
  }
  
  return 0;
}

// [Lua] inMobi.isLoaded(placementId)
int
InMobiLibrary::isLoaded(lua_State *L)
{
  // Corona namespace
  using namespace Corona;
  // Context
  Self *context = ToLibrary(L);
  bool hasLoaded = false;
  
  // If context is valid
  if (context)
  {
    const char *placementId = NULL;
    Self& library = *context;
    
    // Ensure that .init() has been called first (fListener will not be null if init is called, as it's a required param)
    if (library.GetListener() == NULL)
    {
      CoronaLuaError(L, "ERROR: inMobi.isLoaded(placementId) you must call inMobi.init() before making any other inMobi.* Api calls");
      return 0;
    }
    
    // Get the placement id
    if (lua_type(L, 1) == LUA_TSTRING)
    {
      placementId = lua_tostring(L, 1);
    }
    else
    {
      CoronaLuaError(L, "ERROR: inMobi.isLoaded(placementId) placementId (string) expected, got %s", lua_typename(L, lua_type(L, 1)));
      return 0;
    }
    
    // Ensure the Ad exists in the inMobiAds dict
    if ([inMobiAds objectForKey:UTF8Str(placementId)])
    {
      // Get the adDict for this Ad
      NSDictionary *adDict = [inMobiAds objectForKey:UTF8Str(placementId)];
      // Check if the Ad is loaded
      hasLoaded = [[adDict objectForKey:HAS_LOADED_KEY] boolValue];
    }
  }
  
  // Push the result
  lua_pushboolean(L, hasLoaded);
  
  return 1;
}

// [Lua] inMobi.show(placementId)
int
InMobiLibrary::show(lua_State *L)
{
  // Corona namespace
  using namespace Corona;
  // Context
  Self *context = ToLibrary(L);
  
  // If context is valid
  if (context)
  {
    Self& library = *context;
    const char *placementId = NULL;
    
    // Ensure that .init() has been called first (fListener will not be null if init is called, as it's a required param)
    if (library.GetListener() == NULL)
    {
      CoronaLuaError(L, "ERROR: inMobi.show() you must call inMobi.init() before making any other inMobi.* Api calls");
      return 0;
    }
    
    // Get the placement id
    if (lua_type(L, 1) == LUA_TSTRING)
    {
      placementId = lua_tostring(L, 1);
    }
    else
    {
      CoronaLuaError(L, "ERROR: inMobi.show(placementId, options) placementId (string) expected, got %s", lua_typename(L, lua_type(L, 1)));
      return 0;
    }
    
    // Ensure the Ad exists in the inMobiAds dict
    if ([inMobiAds objectForKey:UTF8Str(placementId)])
    {
      // Get the app view controller
      UIViewController *appViewController = library.GetAppViewController();
      // Get the adDict for this ad
      NSDictionary *adDict = [inMobiAds objectForKey:UTF8Str(placementId)];
      // Get the adUnitType
      NSString *adUnitType = [adDict objectForKey:AD_UNIT_TYPE_KEY];
      // Check if the Ad has loaded
      bool hasLoaded = [[adDict objectForKey:HAS_LOADED_KEY] boolValue];
      
      // If the Ad has loaded
      if (hasLoaded)
      {
        // Show a banner Ad
        if ([adUnitType isEqualToString:BANNER_AD_NAME])
        {
          bool isValidAlignment = false;
          const char *bannerAlignY = "top";
          const char *bannerAlignOptions[3] = {"top", "center", "bottom"};
          
          // Get the options table (if it exists)
          if (lua_type(L, 2) == LUA_TTABLE)
          {
            // Get the yAlign key
            lua_getfield(L, -1, "yAlign");
            
            // Ensure that yAlign is a string
            if (lua_type(L, -1) == LUA_TSTRING)
            {
              bannerAlignY = lua_tostring(L, -1);
            }
            else
            {
              CoronaLuaError(L, "ERROR: inMobi.show(placementId, options) options.yAlign (string) expected, got %s", lua_typename(L, lua_type(L, -1)));
              return 0;
            }
            // Pop the yAlign key
            lua_pop(L, 1);
            
            // Ensure the chosen alignment is valid
            for (int i = 0; i < 3; i++)
            {
              // If the chosen alignment matches one of the valid alignments
              if (strcmp(bannerAlignY, bannerAlignOptions[i]) == 0)
              {
                isValidAlignment = true;
                break;
              }
            }
            
            // Set the banner alignment
            if (!isValidAlignment)
            {
              bannerAlignY = "top";
              CoronaLuaWarning(L, "WARNING: Invalid banner alignment specified. Using the default alignment 'top'");
            }
            
            // Pop the options table
            lua_pop(L, 1);
          }
          
          // Get the banner Ad
          IMBanner *bannerAd = [adDict objectForKey:AD_VIEW_KEY];
          // Get the banner Ads width
          const int bannerWidth = [[adDict objectForKey:BANNER_WIDTH_KEY] intValue];
          const int bannerHeight = [[adDict objectForKey:BANNER_HEIGHT_KEY] intValue];
          // The screen size
          const CGRect screenSize = [UIScreen mainScreen].applicationFrame;
          // The screen height
          const float screenWidth = screenSize.size.width;
          const float screenHeight = screenSize.size.height;
          const float kScreenCenterX = ((screenWidth - bannerWidth) / 2); // Banners are anchored to x zero, so we need to factor in their width
          const float kScreenTopY = 0;
          const float kScreenCenterY = ((screenHeight - bannerHeight) / 2); // Banners are anchored to y zero, so we need to factor in their height
          const float kScreenBottomY = (screenHeight - bannerHeight);
          // The horizontal position to use
          float verticalPosition = kScreenTopY;
          
          // Set the banners vertical aligment
          if (strcmp("top", bannerAlignY) == 0)
          {
            verticalPosition = kScreenTopY;
          }
          else if (strcmp("center", bannerAlignY) == 0)
          {
            verticalPosition = kScreenCenterY;
          }
          else if (strcmp("bottom", bannerAlignY) == 0)
          {
            verticalPosition = kScreenBottomY;
          }
          // Set the banner Ads position and size
          bannerAd.frame = CGRectMake(kScreenCenterX, verticalPosition, bannerWidth, bannerHeight);
          
          // Show the Ad
          bannerAd.layer.hidden = false;
          bannerAd.hidden = false;
          
          // Dispatch the displayed event
          [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            CoronaLuaNewEvent(L, kEvent);
            
            // Push the status string
            lua_pushstring(L, [DISPLAYED_EVENT UTF8String]);
            lua_setfield(L, -2, CoronaEventPhaseKey());
            
            // Provider
            lua_pushstring(L, kProviderName);
            lua_setfield(L, -2, CoronaEventProviderKey());
            
            // Type
            lua_pushstring(L, [BANNER_AD_NAME UTF8String]);
            lua_setfield(L, -2, CoronaEventTypeKey());
            
            // Placement id
            lua_pushstring(L, placementId);
            lua_setfield(L, -2, "placementId");
            
            // Dispatch the event
            CoronaLuaDispatchEvent(L, library.GetListener(), 1);
          }];
          
        }
        // Show an interstitial Ad
        else if ([adUnitType isEqualToString:INTERSTITIAL_AD_NAME])
        {
          // Get the interstitial Ad
          IMInterstitial *interstitialAd = [adDict objectForKey:AD_VIEW_KEY];
          // Show the Ad
          [interstitialAd showFromViewController:appViewController];
        }
      }
      else
      {
        CoronaLuaWarning(L, "inMobi.show(placementId, options) placementId '%s' not loaded yet", placementId);
        return 0;
      }
    }
    else
    {
      CoronaLuaWarning(L, "inMobi.show(placementId, options) placementId '%s' not loaded", placementId);
      return 0;
    }
    
  }
  
  return 0;
}

// [Lua] inMobi.hide(placementId)
int
InMobiLibrary::hide(lua_State *L)
{
  // Corona namespace
  using namespace Corona;
  // Context
  Self *context = ToLibrary(L);
  
  // If context is valid
  if (context)
  {
    const char *placementId = NULL;
    Self& library = *context;
    
    // Ensure that .init() has been called first (fListener will not be null if init is called, as it's a required param)
    if (library.GetListener() == NULL)
    {
      CoronaLuaError(L, "inMobi.hide(placementId) you must call inMobi.init() before making any other inMobi.* Api calls");
      return 0;
    }
    
    // Get the placement id
    if (lua_type(L, 1) == LUA_TSTRING)
    {
      placementId = lua_tostring(L, 1);
    }
    else
    {
      CoronaLuaError(L, "inMobi.hide(placementId) placementId (string) expected, got %s", lua_typename(L, lua_type(L, 1)));
      return 0;
    }
    
    // Ensure the Ad exists in the inMobiAds dict
    if ([inMobiAds objectForKey:UTF8Str(placementId)])
    {
      // Get the adDict for this Ad
      NSDictionary *adDict = [inMobiAds objectForKey:UTF8Str(placementId)];
      // Get the adUnitType
      NSString *adUnitType = [adDict objectForKey:AD_UNIT_TYPE_KEY];
      // If the adUnitType is a banner
      if ([adUnitType isEqualToString:BANNER_AD_NAME])
      {
        // Get the banner Ad
        IMBanner *bannerAd = [adDict objectForKey:AD_VIEW_KEY];
        // Hide the banner Ad
        bannerAd.hidden = true;
        // Remove the banner Ad from the view
        [bannerAd removeFromSuperview];
        // Remove the banner ad from the inMobiAds dict
        [inMobiAds removeObjectForKey:UTF8Str(placementId)];
        // Nil the banner Ad
        bannerAd = nil;
        // Remove the adDict
        [adDict release];
        adDict = nil;
      }
      else
      {
        CoronaLuaWarning(L, "inMobi.hide(placementId) placementId '%s' is not a banner", placementId);
      }
    }
    else
    {
      CoronaLuaWarning(L, "inMobi.hide(placementId) placementId '%s' not loaded", placementId);
    }
  }
  
  return 0;
}

//----------------------------------------------------------------------------

// Plugin Delegate implementation
@implementation InMobiDelegate

// Dispatch a Lua event to the callback
- (void)dispatchLuaEvent:(NSString *)phase type:(NSString *)type placementId:(NSString *)placementId data:(NSDictionary *)data error:(NSError *)error
{
  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
    // Get the Lua runtime
    lua_State *L = self.fRuntime.L;
    
    // Create the event
    CoronaLuaNewEvent(L, [self.kEvent UTF8String]);
    
    // Type
    if (type)
    {
      lua_pushstring(L, [type UTF8String]);
      lua_setfield(L, -2, CoronaEventTypeKey());
    }
    
    // Phase
    if (phase)
    {
      lua_pushstring(L, [phase UTF8String]);
      lua_setfield(L, -2, CoronaEventPhaseKey());
    }
    
    // Placement id
    if (placementId)
    {
      lua_pushstring(L, [placementId UTF8String]);
      lua_setfield(L, -2, "placementId");
    }
    
    // Data
    if (data)
    {
      // Push the dictionary
      CoronaLuaPushValue(L, data);
      lua_setfield(L, -2, "data");
    }
    
    // Error message
    if (error)
    {
      // Push the event error flag
      lua_pushboolean(L, true);
      lua_setfield(L, -2, CoronaEventIsErrorKey());
      
      // Structure the error message
      NSString *errorMessage = [NSString stringWithFormat:@"%@ - Error Code %ld", [error localizedDescription], (long)error.code];
      
      // Push the event response
      lua_pushstring(L, [errorMessage UTF8String]);
      lua_setfield(L, -2, CoronaEventResponseKey());
    }
    
    // Provider
    if (self.kProviderName)
    {
      lua_pushstring(L, [self.kProviderName UTF8String]);
      lua_setfield(L, -2, CoronaEventProviderKey());
    }
    
    // Dispatch the event
    CoronaLuaDispatchEvent(self.fRuntime.L, self.fListener, 1);
  }];
}

// Plugin delegate methods

// Banner Ad delegate methods

// Indicates that the banner has received an ad.
- (void)bannerDidFinishLoading:(IMBanner *)banner
{
  // The Ads placement id
  NSString *placementId = [NSString stringWithFormat:@"%lld", banner.placementId];
  
  // Ensure the Ad exists in the inMobiAds dict
  if ([inMobiAds objectForKey:placementId])
  {
    // Get the ad dict
    NSMutableDictionary *adDict = [inMobiAds objectForKey:placementId];
    // Set the Ad as loaded
    [adDict setObject:[NSNumber numberWithBool:true] forKey:HAS_LOADED_KEY];
    // Dispatch the event
    [self dispatchLuaEvent:LOADED_EVENT type:BANNER_AD_NAME placementId:placementId data:nil error:nil];
  }
}

// Indicates that the banner has failed to receive an ad
- (void)banner:(IMBanner *)banner didFailToLoadWithError:(IMRequestStatus *)error
{
  // The Ads placement id
  NSString *placementId = [NSString stringWithFormat:@"%lld", banner.placementId];
  
  // Ensure the Ad exists in the inMobiAds dict
  if ([inMobiAds objectForKey:placementId])
  {
    // Remove the ad from the inMobiAds dict
    [inMobiAds removeObjectForKey:placementId];
    // Dispatch the event
    [self dispatchLuaEvent:FAILED_EVENT type:BANNER_AD_NAME placementId:placementId data:nil error:error];
  }
}

// Indicates that the banner is going to present a screen.
- (void)bannerWillPresentScreen:(IMBanner *)banner
{
  // NOP
}

// Indicates that the banner has presented a screen.
- (void)bannerDidPresentScreen:(IMBanner *)banner
{
  // We don't dispatch the event here, as it would fire on Ad load because
  // banner ads are immediately displayed, and we hide to to get consistent behavior
}

// Indicates that the banner is going to dismiss the presented screen.
- (void)bannerWillDismissScreen:(IMBanner *)banner
{
  // NOP
}

// Indicates that the banner has dismissed a screen.
- (void)bannerDidDismissScreen:(IMBanner *)banner
{
  // The Ads placement id
  NSString *placementId = [NSString stringWithFormat:@"%lld", banner.placementId];
  
  // Ensure the Ad exists in the inMobiAds dict
  if ([inMobiAds objectForKey:placementId])
  {
    // Remove the ad from the inMobiAds dict
    [inMobiAds removeObjectForKey:placementId];
    // Dispatch the event
    [self dispatchLuaEvent:HIDDEN_EVENT type:BANNER_AD_NAME placementId:placementId data:nil error:nil];
  }
}

// Indicates that the user will leave the app.
- (void)userWillLeaveApplicationFromBanner:(IMBanner *)banner
{
  // The Ads placement id
  NSString *placementId = [NSString stringWithFormat:@"%lld", banner.placementId];
  
  // Dispatch the event
  [self dispatchLuaEvent:CLICKED_EVENT type:BANNER_AD_NAME placementId:placementId data:nil error:nil];
}

// banner:didInteractWithParams: Indicates that the banner was interacted with.
-(void)banner:(IMBanner *)banner didInteractWithParams:(NSDictionary *)params
{
  // NOP
}

// Notifies the delegate that the user has completed the action to be incentivised with
-(void)banner:(IMBanner *)banner rewardActionCompletedWithRewards:(NSDictionary*)rewards
{
  // The Ads placement id
  NSString *placementId = [NSString stringWithFormat:@"%lld", banner.placementId];
  
  // Dispatch the event
  [self dispatchLuaEvent:REWARD_COMPLETED type:BANNER_AD_NAME placementId:placementId data:rewards error:nil];
}

// Interstitial Ad delegate methods

// Notifies the delegate that the interstitial has finished loading
-(void)interstitialDidFinishLoading:(IMInterstitial *)interstitial
{
  // The Ads placement id
  NSString *placementId = [NSString stringWithFormat:@"%lld", interstitial.placementId];
  
  // Ensure the Ad exists in the inMobiAds dict
  if ([inMobiAds objectForKey:placementId])
  {
    // Get the ad dict
    NSMutableDictionary *adDict = [inMobiAds objectForKey:placementId];
    // Set the Ad as loaded
    [adDict setObject:[NSNumber numberWithBool:true] forKey:HAS_LOADED_KEY];
    // Dispatch the event
    [self dispatchLuaEvent:LOADED_EVENT type:INTERSTITIAL_AD_NAME placementId:placementId data:nil error:nil];
  }
}

// Notifies the delegate that the interstitial has failed to load with some error
-(void)interstitial:(IMInterstitial *)interstitial didFailToLoadWithError:(IMRequestStatus*)error
{
  // The Ads placement id
  NSString *placementId = [NSString stringWithFormat:@"%lld", interstitial.placementId];
  
  // Ensure the Ad exists in the inMobiAds dict
  if ([inMobiAds objectForKey:placementId])
  {
    // Remove the ad from the inMobiAds dict
    [inMobiAds removeObjectForKey:placementId];
    // Dispatch the event
    [self dispatchLuaEvent:FAILED_EVENT type:INTERSTITIAL_AD_NAME placementId:placementId data:nil error:error];
  }
}
// Notifies the delegate that the interstitial would be presented
-(void)interstitialWillPresent:(IMInterstitial*)interstitial
{
  // NOP
}

// Notifies the delegate that the interstitial has been presented
-(void)interstitialDidPresent:(IMInterstitial *)interstitial
{
  // The Ads placement id
  NSString *placementId = [NSString stringWithFormat:@"%lld", interstitial.placementId];
  
  // Dispatch the event
  [self dispatchLuaEvent:DISPLAYED_EVENT type:INTERSTITIAL_AD_NAME placementId:placementId data:nil error:nil];
  
}

// Notifies the delegate that the interstitial has failed to present with some error
-(void)interstitial:(IMInterstitial*)interstitial didFailToPresentWithError:(IMRequestStatus*)error
{
  // NOP
}

// Notifies the delegate that the interstitial will be dismissed
-(void)interstitialWillDismiss:(IMInterstitial*)interstitial
{
  // NOP
}

// Notifies the delegate that the interstitial has been dismissed
-(void)interstitialDidDismiss:(IMInterstitial*)interstitial
{
  // The Ads placement id
  NSString *placementId = [NSString stringWithFormat:@"%lld", interstitial.placementId];
  
  // Ensure the Ad exists in the inMobiAds dict
  if ([inMobiAds objectForKey:placementId])
  {
    // Remove the ad from the inMobiAds dict
    [inMobiAds removeObjectForKey:placementId];
    // Dispatch the event
    [self dispatchLuaEvent:HIDDEN_EVENT type:INTERSTITIAL_AD_NAME placementId:placementId data:nil error:nil];
  }
}

-(void)userWillLeaveApplicationFromInterstitial:(IMInterstitial *)interstitial
{
  NSString *placementId = [NSString stringWithFormat:@"%lld", interstitial.placementId];
  [self dispatchLuaEvent:CLICKED_EVENT type:INTERSTITIAL_AD_NAME placementId:placementId data:nil error:nil];
}

// Notifies the delegate that the interstitial has been interacted with
-(void)interstitial:(IMInterstitial*)interstitial didInteractWithParams:(NSDictionary*)params
{
  // NOP
}

// Notifies the delegate that the user has performed the action to be incentivised with
-(void)interstitial:(IMInterstitial *)interstitial rewardActionCompletedWithRewards:(NSDictionary *)rewards
{
  // The Ads placement id
  NSString *placementId = [NSString stringWithFormat:@"%lld", interstitial.placementId];
  
  // Dispatch the event
  [self dispatchLuaEvent:REWARD_COMPLETED type:INTERSTITIAL_AD_NAME placementId:placementId data:rewards error:nil];
}

@end

//----------------------------------------------------------------------------

CORONA_EXPORT int luaopen_plugin_inMobi(lua_State *L)
{
  return InMobiLibrary::Open(L);
}
