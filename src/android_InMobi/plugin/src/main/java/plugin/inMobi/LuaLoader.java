//
//  LuaLoader.java
//  inMobi Plugin
//
//  Copyright (c) 2016 CoronaLabs inc. All rights reserved.
//

// @formatter:off

package plugin.inMobi;

import java.util.*;

import android.util.Log;
import android.view.View;
import android.widget.FrameLayout.LayoutParams;
import android.view.Gravity;

import com.naef.jnlua.LuaState;
import com.naef.jnlua.LuaType;
import com.naef.jnlua.JavaFunction;
import com.naef.jnlua.NamedJavaFunction;

import com.ansca.corona.CoronaActivity;
import com.ansca.corona.CoronaEnvironment;
import com.ansca.corona.CoronaLua;
import com.ansca.corona.CoronaRuntime;
import com.ansca.corona.CoronaRuntimeListener;
import com.ansca.corona.CoronaRuntimeTask;
import com.ansca.corona.CoronaRuntimeTaskDispatcher;
import com.ansca.corona.CoronaLuaEvent;
import com.ansca.corona.CoronaBeacon;

// SDK provider imports
import com.inmobi.sdk.InMobiSdk;
import com.inmobi.ads.InMobiAdRequestStatus;
import com.inmobi.ads.InMobiBanner;
import com.inmobi.ads.InMobiInterstitial;
import com.inmobi.sdk.InMobiSdk.Gender;
import com.inmobi.sdk.InMobiSdk.Education;
import com.inmobi.sdk.InMobiSdk.AgeGroup;
import com.inmobi.sdk.InMobiSdk.LogLevel;

import org.json.JSONException;
import org.json.JSONObject;

/**
 * Implements the Lua interface for the plugin.
 * <p>
 * Only one instance of this class will be created by Corona for the lifetime of the application.
 * This instance will be re-used for every new Corona activity that gets created.
 */
public class LuaLoader implements JavaFunction, CoronaRuntimeListener
{
  // This corresponds to the name of the library, e.g. [Lua] require "plugin.library"
  private final String kName = "plugin.inMobi";
  // The plugins version number
  private final String kVersionNumber = "1.1.9";
  // The adRequest event name
  private final String kEvent = "adsRequest";
  // The ad provider name
  private final String kProviderName = "inMobi";
  // Corona log tag name
  private final String CORONA_LOG_TAG = "Corona";
  // Constants
  private final String BANNER_AD_NAME = "banner";
  private final String INTERSTITIAL_AD_NAME = "interstitial";
  private final String VIDEO_AD_NAME = "video";
  // Dictionary keys
  private final String HAS_LOADED_KEY = "hasLoaded";
  private final String AD_VIEW_KEY = "adView";
  private final String AD_UNIT_TYPE_KEY = "adType";
  private final String BANNER_WIDTH_KEY = "bannerWidth";
  private final String BANNER_HEIGHT_KEY = "bannerHeight";
  private final String BANNER_LAYOUT = "layout";
  // Event names
  private final String CORONA_PHASE_EVENT = "phase";
  private final String CORONA_TYPE_EVENT = "type";
  private final String CORONA_PLACEMENT_ID_EVENT = "placementId";
  private final String CORONA_DATA_EVENT = "data";
  private final String LOADED_EVENT = "loaded";
  private final String FAILED_EVENT = "failed";
  private final String DISPLAYED_EVENT = "displayed";
  private final String CLICKED_EVENT = "clicked";
  private final String HIDDEN_EVENT = "closed";
  private final String REWARD_COMPLETED = "rewardComplete";
  // Runtime task dispatcher pointer
  private CoronaRuntimeTaskDispatcher fRuntimeTaskDispatcher;
  // Lua registry ID to the Lua function to be called when the ad request finishes
  private int fListener = CoronaLua.REFNIL;
  // InMobi ads dictionary
  private static Map<String, Object> inMobiAds;

  // Dispatch a Lua event to our callback
  public void dispatchLuaEvent(final Map<String, Object> event)
  {
    if (fRuntimeTaskDispatcher != null) {
      fRuntimeTaskDispatcher.send(new CoronaRuntimeTask() {
        @Override
        public void executeUsing(CoronaRuntime runtime) {
          try {
            LuaState L = runtime.getLuaState();
            CoronaLua.newEvent(L, kEvent);
            boolean hasErrorKey = false;

            // add event parameters from map
            for (String key: event.keySet()) {
              CoronaLua.pushValue(L, event.get(key));           // push value
              L.setField(-2, key);                              // push key

              if (! hasErrorKey) {
                hasErrorKey = key.equals(CoronaLuaEvent.ISERROR_KEY);
              }
            }

            // add error key if not in map
            if (! hasErrorKey) {
              L.pushBoolean(false);
              L.setField(-2, CoronaLuaEvent.ISERROR_KEY);
            }

            // add provider
            L.pushString(kProviderName);
            L.setField(-2, CoronaLuaEvent.PROVIDER_KEY);

            CoronaLua.dispatchEvent(L, fListener, 0);
          }
          catch (Exception ex) {
            ex.printStackTrace();
          }
        }
      });
    }
  }

  // Banner listener class
  private class InMobiBannerAdListenerClass implements InMobiBanner.BannerAdListener
  {
    // The Ads placement id
    private final String kPlacementId;
    // The Ad type
    private final String kAdType;

    // Initializer
    public InMobiBannerAdListenerClass(final String placementId, final String adType)
    {
      // Set the placement id
      if (placementId != null)
      {
        kPlacementId = placementId;
      }
      else
      {
        kPlacementId = null;
      }

      // Set the ad type
      if (adType != null)
      {
        kAdType = adType;
      }
      else
      {
        kAdType = null;
      }
    }

    @Override
    public void onAdLoadSucceeded(InMobiBanner ad)
    {
      // Ensure the Ad exists in the inMobi dict
      if (inMobiAds.containsKey(kPlacementId))
      {
        // Get the ad dict
        final Map<String, Object> adDict = (Map<String, Object>)inMobiAds.get(kPlacementId);
        // If the ad has not already been loaded (for instance, if the ad has loaded once already and is just refreshing itself)
        if (Boolean.FALSE.equals(adDict.get(HAS_LOADED_KEY)))
        {
          // Make the Ad invisible
          ad.setVisibility(View.GONE);
        }
        // Set the Ad as loaded
        adDict.put(HAS_LOADED_KEY, true);
        // Create the event
        Map<String, Object> coronaEvent = new HashMap<>();
        coronaEvent.put(CORONA_PHASE_EVENT, LOADED_EVENT);
        coronaEvent.put(CORONA_TYPE_EVENT, kAdType);
        coronaEvent.put(CORONA_PLACEMENT_ID_EVENT, kPlacementId);
        // Dispatch the event
        dispatchLuaEvent(coronaEvent);
      }
    }

    @Override
    public void onAdLoadFailed(InMobiBanner ad, InMobiAdRequestStatus statusCode)
    {
      // Ensure the Ad exists in the inMobi dict
      if (inMobiAds.containsKey(kPlacementId))
      {
        // Remove the ad from the dict
        inMobiAds.remove(kPlacementId);
        // Create the event
        Map<String, Object> coronaEvent = new HashMap<>();
        coronaEvent.put(CORONA_PHASE_EVENT, FAILED_EVENT);
        coronaEvent.put(CORONA_TYPE_EVENT, kAdType);
        coronaEvent.put(CORONA_PLACEMENT_ID_EVENT, kPlacementId);
        coronaEvent.put(CoronaLuaEvent.ISERROR_KEY, true);
        coronaEvent.put(CoronaLuaEvent.RESPONSE_KEY, statusCode.getStatusCode() + " - " + statusCode.getMessage());
        // Dispatch the event
        dispatchLuaEvent(coronaEvent);
      }
    }

    @Override
    public void onAdDisplayed(InMobiBanner ad)
    {
      // We don't dispatch the event here, as it would fire on Ad load because
      // banner ads are immediately displayed, and we hide to to get consistent behavior
    }

    @Override
    public void onAdDismissed(InMobiBanner ad)
    {
      // This event doesn't exist (a leftover), as Ads cannot be offically hidden in the inMobi SDK
    }

    @Override
    public void onAdInteraction(InMobiBanner ad, Map<Object, Object> params)
    {
      // NOP
    }

    @Override
    public void onUserLeftApplication(InMobiBanner ad)
    {
      // Create the event
      Map<String, Object> coronaEvent = new HashMap<>();
      coronaEvent.put(CORONA_PHASE_EVENT, CLICKED_EVENT);
      coronaEvent.put(CORONA_TYPE_EVENT, kAdType);
      coronaEvent.put(CORONA_PLACEMENT_ID_EVENT, kPlacementId);
      // Dispatch the event
      dispatchLuaEvent(coronaEvent);
    }

    @Override
    public void onAdRewardActionCompleted(InMobiBanner ad, Map<Object, Object> rewards)
    {
      // Create the event
      Map<String, Object> coronaEvent = new HashMap<>();
      coronaEvent.put(CORONA_PHASE_EVENT, REWARD_COMPLETED);
      coronaEvent.put(CORONA_TYPE_EVENT, kAdType);
      coronaEvent.put(CORONA_PLACEMENT_ID_EVENT, kPlacementId);
      coronaEvent.put(CORONA_DATA_EVENT, rewards);
      // Dispatch the event
      dispatchLuaEvent(coronaEvent);
    }
  }

  // Interstitial listener class
  private class InMobiInterstitialAdListenerClass implements InMobiInterstitial.InterstitialAdListener2
  {
    // The Ads placement id
    private final String kPlacementId;
    // The Ad type
    private final String kAdType;

    // Initializer
    InMobiInterstitialAdListenerClass(final String placementId, final String adType)
    {
      // Set the placement id
      if (placementId != null)
      {
        kPlacementId = placementId;
      }
      else
      {
        kPlacementId = null;
      }

      // Set the ad type
      if (adType != null)
      {
        kAdType = adType;
      }
      else
      {
        kAdType = null;
      }
    }

    @Override
    public void onAdDisplayFailed(InMobiInterstitial inMobiInterstitial) {
      // NOP
    }

    @Override
    public void onAdReceived(InMobiInterstitial inMobiInterstitial) {
      // NOP
    }

    @Override
    public void onAdWillDisplay(InMobiInterstitial inMobiInterstitial) {
      // NOP
    }

    @Override
    public void onAdLoadSucceeded(InMobiInterstitial ad)
    {
      // Ensure the Ad exists in the inMobi dict
      if (inMobiAds.containsKey(kPlacementId))
      {
        // Get the ad dict
        final Map<String, Object> adDict = (Map<String, Object>)inMobiAds.get(kPlacementId);
        // Set the Ad as loaded
        adDict.put(HAS_LOADED_KEY, true);
        // Create the event
        Map<String, Object> coronaEvent = new HashMap<>();
        coronaEvent.put(CORONA_PHASE_EVENT, LOADED_EVENT);
        coronaEvent.put(CORONA_TYPE_EVENT, kAdType);
        coronaEvent.put(CORONA_PLACEMENT_ID_EVENT, kPlacementId);
        // Dispatch the event
        dispatchLuaEvent(coronaEvent);
      }
    }

    @Override
    public void onAdLoadFailed(InMobiInterstitial ad, InMobiAdRequestStatus statusCode)
    {
      // Ensure the Ad exists in the inMobi dict
      if (inMobiAds.containsKey(kPlacementId))
      {
        // Remove the ad from the dict
        inMobiAds.remove(kPlacementId);
        // Create the event
        Map<String, Object> coronaEvent = new HashMap<>();
        coronaEvent.put(CORONA_PHASE_EVENT, FAILED_EVENT);
        coronaEvent.put(CORONA_TYPE_EVENT, kAdType);
        coronaEvent.put(CORONA_PLACEMENT_ID_EVENT, kPlacementId);
        coronaEvent.put(CoronaLuaEvent.ISERROR_KEY, true);
        coronaEvent.put(CoronaLuaEvent.RESPONSE_KEY, statusCode.getStatusCode() + " - " + statusCode.getMessage());
        // Dispatch the event
        dispatchLuaEvent(coronaEvent);
      }
    }

    @Override
    public void onAdDisplayed(InMobiInterstitial ad)
    {
      // Don't dispatch the event here, as it only fires *after* the ad has been
      // dismissed, which isn't very helpful
    }

    @Override
    public void onAdDismissed(InMobiInterstitial ad)
    {
      // Create the event
      Map<String, Object> coronaEvent = new HashMap<>();
      coronaEvent.put(CORONA_PHASE_EVENT, HIDDEN_EVENT);
      coronaEvent.put(CORONA_TYPE_EVENT, kAdType);
      coronaEvent.put(CORONA_PLACEMENT_ID_EVENT, kPlacementId);
      // Dispatch the event
      dispatchLuaEvent(coronaEvent);
    }

    @Override
    public void onAdInteraction(InMobiInterstitial ad, Map<Object, Object> params)
    {
      // NOP
    }

    @Override
    public void onUserLeftApplication(InMobiInterstitial ad)
    {
      // send Corona Lua event
      Map<String, Object> coronaEvent = new HashMap<>();
      coronaEvent.put(CORONA_PHASE_EVENT, CLICKED_EVENT);
      coronaEvent.put(CORONA_TYPE_EVENT, kAdType);
      coronaEvent.put(CORONA_PLACEMENT_ID_EVENT, kPlacementId);
      dispatchLuaEvent(coronaEvent);
    }


    @Override
    public void onAdRewardActionCompleted(InMobiInterstitial ad, Map<Object, Object> rewards)
    {

      // ignore event if no reward data exists
      if ((rewards == null) || (rewards.size() == 0)) {
        return;
      }

      // we need to convert the Hashmap to a Hashtable for Corona to recognize it
      Hashtable<Object, Object> eventData = new Hashtable<>();
      eventData.putAll(rewards);

      // send the Corona Lua event
      Map<String, Object> coronaEvent = new HashMap<>();
      coronaEvent.put(CORONA_PHASE_EVENT, REWARD_COMPLETED);
      coronaEvent.put(CORONA_TYPE_EVENT, kAdType);
      coronaEvent.put(CORONA_PLACEMENT_ID_EVENT, kPlacementId);
      coronaEvent.put(CORONA_DATA_EVENT, eventData);
      dispatchLuaEvent(coronaEvent);
    }
  }

  // Clear ads
  private int clearAds()
  {
    if (inMobiAds != null)
    {
      // Loop over the inMobiAds dict
      for(Iterator<Map.Entry<String, Object>> it = inMobiAds.entrySet().iterator(); it.hasNext();)
      {
        // Get the current entry
        Map.Entry<String, Object> entry = it.next();
        // Get the dictionary for this Ad
        Map<String, Object> adDict = (Map<String, Object>)inMobiAds.get(entry.getKey());
        // Get the Ad type
        String adUnitType = (String)adDict.get(AD_UNIT_TYPE_KEY);
        // Is this Ad a banner?
        boolean isBannerAd = adUnitType.equalsIgnoreCase(BANNER_AD_NAME);

        // If this Ad is a banner, don't remove it from the screen
        // NOTE: inMobi remove all Ad types from the screen on a suspend/resume, _except_ for banner Ads
        if (!isBannerAd)
        {
          // Remove this entry from the inMobiAds dictionary
          it.remove();
          // Remove the adDict
          adDict.clear();
          adDict = null;
        }
      }
    }

    return 0;
  }

  // Get the corona sdk version
  private static String getCoronaVersion(LuaState L)
  {
    L.getGlobal("system");
    L.getField(-1, "getInfo");
    L.pushString("build");
    L.call(1, 1);
    String buildString = L.toString(-1);
    L.pop(2);

    return buildString;
  }

  // Handle the beacon response
  public class PerkBeaconListener implements JavaFunction
  {
    // This method is executed when the Lua function is called
    @Override
    public int invoke(LuaState L)
    {
      //L.getField(-1, "response");
      //Log.i(CORONA_LOG_TAG, "Network listener: response: " + L.toString(-1));

      return 0;
    }
  }

  // Set the Corona attribution (so delivered Ads will show as coming from Corona)
  private static Map<String, String> coronaAttributionExtras(LuaState L)
  {
    // Get the Corona SDK version
    final String coronaSDKVersion = getCoronaVersion(L);
    // The Corona extras map
    Map<String, String> coronaExtras = null;

    // If the coronaSDKVersion isn't null
    if (coronaSDKVersion != null)
    {
      // Set the Corona atrribution (so delivered Ads will show as coming from Corona)
      coronaExtras = new HashMap<String, String>();
      coronaExtras.put("tp", "p_corona");
      coronaExtras.put("tp-ver", coronaSDKVersion);
    }

    return coronaExtras;
  }

  /**
   * <p>
   * Note that a new LuaLoader instance will not be created for every CoronaActivity instance.
   * That is, only one instance of this class will be created for the lifetime of the application process.
   * This gives a plugin the option to do operations in the background while the CoronaActivity is destroyed.
   */
  public LuaLoader()
  {
    // Set up this plugin to listen for Corona runtime events to be received by methods
    // onLoaded(), onStarted(), onSuspended(), onResumed(), and onExiting().
    CoronaEnvironment.addRuntimeListener(this);
  }

  /**
   * Called when this plugin is being loaded via the Lua require() function.
   * <p>
   * Note that this method will be called everytime a new CoronaActivity has been launched.
   * This means that you'll need to re-initialize this plugin here.
   * <p>
   * Warning! This method is not called on the main UI thread.
   * @param L Reference to the Lua state that the require() function was called from.
   * @return Returns the number of values that the require() function will return.
   *         <p>
   *         Expected to return 1, the library that the require() function is loading.
   */
  @Override
  public int invoke(LuaState L)
  {
    // Register this plugin into Lua with the following functions.
    NamedJavaFunction[] luaFunctions = new NamedJavaFunction[]
      {
        new init(),
        new setUserDetails(),
        new load(),
        new isLoaded(),
        new show(),
        new hide(),
      };
    String libName = L.toString(1);
    L.register(libName, luaFunctions);

    // Returning 1 indicates that the Lua require() function will return the above Lua library.
    return 1;
  }

  // [Lua] inMobi.init()
  private class init implements NamedJavaFunction
  {
    // Gets the name of the Lua function as it would appear in the Lua script
    @Override
    public String getName()
    {
      return "init";
    }

    // This method is executed when the Lua function is called
    @Override
    public int invoke(LuaState L)
    {
      // If the listener is null
      if (fListener == CoronaLua.REFNIL)
      {
        final String inMobiAccountId;
        String logLevel = null;
        inMobiAds = new HashMap<>();
        Boolean hasUserConsent = null;

        if (CoronaLua.isListener(L, 1, kProviderName))
        {
          fListener = CoronaLua.newRef(L, 1);
        }
        else
        {
          Log.i(CORONA_LOG_TAG, String.format("ERROR: inMobi.init() listener expected, got %s", L.typeName(1)));
          return 0;
        }

        if (L.type(2) == LuaType.TABLE)
        {
          L.getField(-1, "accountId");
          if (L.type(-1) == LuaType.STRING)
          {
            inMobiAccountId = L.toString(-1);
          }
          else
          {
            Log.i(CORONA_LOG_TAG, "ERROR: inMobi.init() options.accountId (string) expected, got " + L.typeName(-1));
            return 0;
          }
          L.pop(1);

          L.getField(-1, "logLevel");
          if (L.type(-1) == LuaType.STRING)
          {
            logLevel = L.toString(-1);
          }
          L.pop(1);

          L.getField(-1, "hasUserConsent");
          if (L.type(-1) == LuaType.BOOLEAN)
          {
            hasUserConsent = L.toBoolean(-1);
          }
          L.pop(2);
        }
        else
        {
          Log.i(CORONA_LOG_TAG, "ERROR: inMobi.init() options (table) expected, got " + L.typeName(2));
          return 0;
        }

        final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();
        final String kLogLevel = logLevel;
        final Boolean fHasUserConsent = hasUserConsent;

        if (coronaActivity != null) {
          coronaActivity.runOnUiThread(new Runnable() {
            @Override
            public void run() {
              // log plugin version to device console
              Log.i(CORONA_LOG_TAG, kName + ": " + kVersionNumber + " (SDK: " +InMobiSdk.getVersion() + ")");

              String gdpr = "1";
              if (fHasUserConsent == null) {
                gdpr = "0";
              }

              // initialize InMobi SDK
              JSONObject consentObject = new JSONObject();
              try {
                // Provide correct consent value to sdk which is obtained by User
                consentObject.put(InMobiSdk.IM_GDPR_CONSENT_AVAILABLE, fHasUserConsent);
                // Provide 0 if GDPR is not applicable and 1 if applicable
                consentObject.put("gdpr", gdpr);
              } catch (JSONException e) {
                e.printStackTrace();
              }
              InMobiSdk.init(coronaActivity, inMobiAccountId, consentObject);

              if (kLogLevel != null) {
                if (kLogLevel.equalsIgnoreCase("debug")) {
                  InMobiSdk.setLogLevel(LogLevel.DEBUG);
                }
                else if (kLogLevel.equalsIgnoreCase("error")) {
                  InMobiSdk.setLogLevel(LogLevel.ERROR);
                }
              }

              // send event to Corona
              Map<String, Object> coronaEvent = new HashMap<String, Object>();
              coronaEvent.put(CORONA_PHASE_EVENT, "init");
              dispatchLuaEvent(coronaEvent);
            }
          });
        }
      }

      return 0;
    }
  }

  // [Lua] inMobi.setUserDetails(options)
  private class setUserDetails implements NamedJavaFunction
  {
    // Gets the name of the Lua function as it would appear in the Lua script
    @Override
    public String getName()
    {
      return "setUserDetails";
    }

    // This method is executed when the Lua function is called
    @Override
    public int invoke(LuaState L)
    {
      // If the userDetails is a table
      if (L.type(1) == LuaType.TABLE)
      {
        // Get the gender field
        L.getField(-1, "gender");

        // If gender is a string
        if (L.type(-1) == LuaType.STRING)
        {
          // Get the user gender
          String gender = L.toString(-1);

          // Set the gender based on the passed type
          if (gender.equalsIgnoreCase("male"))
          {
            InMobiSdk.setGender(Gender.MALE);
          }
          else if (gender.equalsIgnoreCase("female"))
          {
            InMobiSdk.setGender(Gender.FEMALE);
          }
        }
        L.pop(1);

        // Get the postCode field
        L.getField(-1, "postCode");

        // If postCode is a string
        if (L.type(-1) == LuaType.STRING)
        {
          // Get the postCode
          String postCode = L.toString(-1);

          // If the postCode is less than 1 character
          if (postCode.length() == 0)
          {
            Log.i(CORONA_LOG_TAG, "ERROR: inMobi.setUserDetails(options) options.postCode (string) must not be empty. (eg. '24533')");
            return 0;
          }

          // Set the post code
          InMobiSdk.setPostalCode(postCode);
        }
        L.pop(1);

        // Get the phoneAreaCode field
        L.getField(-1, "phoneAreaCode");

        // If phoneAreaCode is a string
        if (L.type(-1) == LuaType.STRING)
        {
          // Get the phoneArea code
          String phoneAreaCode = L.toString(-1);

          // If the phoneAreaCode is less than 1 character
          if (phoneAreaCode.length() == 0)
          {
            Log.i(CORONA_LOG_TAG, "ERROR: inMobi.setUserDetails(options) options.phoneAreaCode (string) must not be empty. (eg. '353')");
            return 0;
          }

          // Set the phoneArea code
          InMobiSdk.setAreaCode(phoneAreaCode);
        }
        L.pop(1);

        // Get the language field
        L.getField(-1, "language");

        // If language is a string
        if (L.type(-1) == LuaType.STRING)
        {
          // Get the language
          String language = L.toString(-1);

          // If the language is less than 1 character
          if (language.length() == 0)
          {
            Log.i(CORONA_LOG_TAG, "ERROR: inMobi.setUserDetails(options) options.language (string) must not be empty. (eg. 'eng')");
            return 0;
          }

          // Set the language
          InMobiSdk.setLanguage(language);
        }
        L.pop(1);

        // Get the birthYear field
        L.getField(-1, "birthYear");

        // If birthYear is a number
        if (L.type(-1) == LuaType.NUMBER)
        {
          // Get the users birth year
          int birthYear = (int)L.toNumber(-1);

          // Get the length of the birthYear (must be 4 digits long)
          if (String.valueOf(birthYear).length() != 4)
          {
            Log.i(CORONA_LOG_TAG, "ERROR: inMobi.setUserDetails(options) options.birthYear (number) must be a number with at least 4 digits (eg. 1991)");
            return 0;
          }

          // Set the birth year
          InMobiSdk.setYearOfBirth(birthYear);
        }
        L.pop(1);

        // Get the age field
        L.getField(-1, "age");

        // If age is a number
        if (L.type(-1) == LuaType.NUMBER)
        {
          // Get the users age
          int age = (int)L.toNumber(-1);

          // If the users age is less than 1
          if (age < 1)
          {
            Log.i(CORONA_LOG_TAG, "ERROR: inMobi.setUserDetails(options) options.age (number) must be equal to, or greater than 1 (years old). (eg. 25)");
            return 0;
          }

          // Set the age
          InMobiSdk.setAge(age);
        }
        L.pop(1);

        // Get the age group field
        L.getField(-1, "ageGroup");

        // If ageGroup is a string
        if (L.type(-1) == LuaType.STRING)
        {
          // Get the users age group
          String ageGroup = L.toString(-1);
          // The InMobi SDK age group (default to below 18)
          AgeGroup imAgeGroup = AgeGroup.BELOW_18;

          // If the users age group is less than 1 character
          if (ageGroup.length() == 0)
          {
            Log.i(CORONA_LOG_TAG, "ERROR: inMobi.setUserDetails(options) options.ageGroup (string) must not be empty. (eg. '18AndUnder')");
            return 0;
          }

          // Set the correct age group based on the value from Lua
          if (ageGroup.equalsIgnoreCase("below18"))
          {
            imAgeGroup = AgeGroup.BELOW_18;
          }
          else if (ageGroup.equalsIgnoreCase("18to24"))
          {
            imAgeGroup = AgeGroup.BETWEEN_18_AND_24;
          }
          else if (ageGroup.equalsIgnoreCase("25to29"))
          {
            imAgeGroup = AgeGroup.BETWEEN_25_AND_29;
          }
          else if (ageGroup.equalsIgnoreCase("30to34"))
          {
            imAgeGroup = AgeGroup.BETWEEN_30_AND_34;
          }
          else if (ageGroup.equalsIgnoreCase("35to44"))
          {
            imAgeGroup = AgeGroup.BETWEEN_35_AND_44;
          }
          else if (ageGroup.equalsIgnoreCase("45to54"))
          {
            imAgeGroup = AgeGroup.BETWEEN_45_AND_54;
          }
          else if (ageGroup.equalsIgnoreCase("55to65"))
          {
            imAgeGroup = AgeGroup.BETWEEN_55_AND_65;
          }
          else if (ageGroup.equalsIgnoreCase("above65"))
          {
            imAgeGroup = AgeGroup.ABOVE_65;
          }

          // Set the age group
          InMobiSdk.setAgeGroup(imAgeGroup);
        }
        L.pop(1);

        // Get the users education field
        L.getField(-1, "education");

        // If education is a string
        if (L.type(-1) == LuaType.STRING)
        {
          // Get the users education
          String education = L.toString(-1);
          // The InMobi SDK education (default to high school or less)
          Education imEducation = Education.HIGH_SCHOOL_OR_LESS;

          // If the users education is less than 1 character
          if (education.length() == 0)
          {
            Log.i(CORONA_LOG_TAG, "ERROR: inMobi.setUserDetails(options) options.education (string) must not be empty. (eg. 'highSchoolOrLess')");
            return 0;
          }

          // Set the correct education based on the value from Lua
          if (education.equalsIgnoreCase("highSchoolOrLess"))
          {
            imEducation = Education.HIGH_SCHOOL_OR_LESS;
          }
          else if (education.equalsIgnoreCase("collegeOrGraduate"))
          {
            imEducation = Education.COLLEGE_OR_GRADUATE;
          }
          else if (education.equalsIgnoreCase("graduateOrAbove"))
          {
            imEducation = Education.POST_GRADUATE_OR_ABOVE;
          }

          // Set the education
          InMobiSdk.setEducation(imEducation);
        }
        L.pop(1);

        // Get the userInterests field
        L.getField(-1, "userInterests");

        // If userInterests is a table
        if (L.type(-1) == LuaType.TABLE)
        {
          // The valid user interests
          String validUserInterests[] = {"Business", "Tech", "Travel", "Shopping", "Entertainment", "Fashion", "Fitness", "Foodie", "Gamer", "Jobs", "Sports"};
          // The user interests string
          String userInterests = "";

          // Get each interest from the table
          for (int i = 0; i < L.length(2); i++)
          {
            // Get the current object
            L.rawGet(2, (i + 1));

            // If the current user interest is a string
            if (L.type(-1) == LuaType.STRING)
            {
              // Is the current user interest valid?
              boolean isCurrentInterestValid = false;
              // Get the current user interest
              String currentInterest = L.toString(-1);

              // Loop over the validUserInterests
              for (int j = 0; j < 11; j++)
              {
                // Ensure that the current user interest matches one of the valid user interest options
                if (currentInterest.equalsIgnoreCase(validUserInterests[j]))
                {
                  // Append the user interest
                  if (i == 0)
                  {
                    userInterests += currentInterest;
                  }
                  else
                  {
                    userInterests = userInterests + "," + currentInterest;
                  }

                  // This is a valid user interest
                  isCurrentInterestValid = true;
                  break;
                }
              }

              // If the current user interest isn't valid, then show an error
              if (!isCurrentInterestValid)
              {
                Log.i(CORONA_LOG_TAG, "ERROR: inMobi.setUserDetails(options) options.userInterests - found invalid user interest");
                return 0;
              }
            }

            // Set the user interests
            if (userInterests.length() > 1)
            {
              InMobiSdk.setInterests(userInterests);
            }
          }
        }
        L.pop(1);
      }
      else
      {
        Log.i(CORONA_LOG_TAG, "ERROR: inMobi.setUserDetails(options) options (table) expected, got " + L.typeName(1));
        return 0;
      }

      return 0;
    }
  }

  // [Lua] inMobi.load(adUnitType, placementId, [options])
  private class load implements NamedJavaFunction
  {
    @Override
    public String getName()
    {
      return "load";
    }

    @Override
    public int invoke(LuaState L)
    {
      // Ensure that .init() has been called first (fListener will not be null if init is called, as it's a required param)
      if (fListener == CoronaLua.REFNIL)
      {
        Log.i(CORONA_LOG_TAG, "ERROR: inMobi.load() you must call inMobi.init() before making any other inMobi.* Api calls");
        return 0;
      }

      final String adUnitType;
      final String placementId;
      int bannerWidth = 320;
      int bannerHeight = 50;
      boolean shouldBannerAutoRefresh = false;
      int bannerRefreshInterval = 60;

      // Get the Ad unit type
      if (L.type(1) == LuaType.STRING)
      {
        adUnitType = L.toString(1);
      }
      else
      {
        Log.i(CORONA_LOG_TAG, "ERROR: inMobi.load(adUnitType, placementId) adUnitType (string) expected, got " + L.typeName(1));
        return 0;
      }

      // Get the placement id
      if (L.type(2) == LuaType.STRING)
      {
        placementId = L.toString(2);
      }
      else
      {
        Log.i(CORONA_LOG_TAG, "ERROR: inMobi.load(adUnitType, placementId) placementId (string) expected, got " + L.typeName(2));
        return 0;
      }

      // Get the banner size (optional arg)
      if (L.type(3) == LuaType.TABLE)
      {
        L.getField(-1, "width");

        if (L.type(-1) == LuaType.NUMBER)
        {
          bannerWidth = (int)L.toNumber(-1);
        }
        L.pop(1);

        L.getField(-1, "height");

        if (L.type(-1) == LuaType.NUMBER)
        {
          bannerHeight = (int)L.toNumber(-1);
        }
        L.pop(1);

        L.getField(-1, "autoRefresh");

        if (L.type(-1) == LuaType.BOOLEAN)
        {
          shouldBannerAutoRefresh = L.toBoolean(-1);
        }
        L.pop(1);

        L.getField(-1, "refreshInterval");

        if (L.type(-1) == LuaType.NUMBER)
        {
          bannerRefreshInterval = (int)L.toNumber(-1);
        }
        L.pop(2);
      }

      /* Try to convert the placement id to a long (needed due to inMobi only accepting
				Long for their ad load calls). We do this here so we can catch the user using an
				incorrect alphanumeric placement id before we actually get to the loading call.
			*/
      try
      {
        Long pid = Long.parseLong(placementId);
      }
      catch (NumberFormatException e)
      {
        Log.i(CORONA_LOG_TAG, "WARNING: Invalid placementId '" + placementId + "'. Placement id's are numeric");
        return 0;
      }

      final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();
      final int kBannerWidth = bannerWidth;
      final int kBannerHeight = bannerHeight;
      final boolean kShouldBannerAutoRefresh = shouldBannerAutoRefresh;
      final int kBannerRefreshInterval = bannerRefreshInterval;
      final Map<String, String> attributionExtras = coronaAttributionExtras(L);

      if (coronaActivity != null) {
        Runnable runnableActivity = new Runnable() {
          public void run() {
            final Map<String, Object> adDict = new HashMap<>();
            final long kPlacementId = Long.parseLong(placementId);

            if (inMobiAds != null && !inMobiAds.containsKey(placementId)) {
              if (adUnitType.equalsIgnoreCase(BANNER_AD_NAME)) {
                final float scale = coronaActivity.getApplicationContext().getResources().getDisplayMetrics().density + 0.5f;

                InMobiBanner bannerAd = new InMobiBanner(coronaActivity, kPlacementId);
                bannerAd.setListener(new InMobiBannerAdListenerClass(placementId, BANNER_AD_NAME));
                bannerAd.setEnableAutoRefresh(kShouldBannerAutoRefresh);
                bannerAd.setRefreshInterval(kBannerRefreshInterval);

                LayoutParams layoutParams = new LayoutParams(
                  (int)(kBannerWidth * scale),
                  (int)(kBannerHeight * scale)
                );

                // put it off screen
                layoutParams.topMargin = 10000;

                bannerAd.setLayoutParams(layoutParams);
                coronaActivity.getOverlayView().addView(bannerAd);

                if (attributionExtras != null) {
                  bannerAd.setExtras(attributionExtras);
                }

                bannerAd.load();
                bannerAd.setVisibility(View.INVISIBLE);

                adDict.put(BANNER_LAYOUT, layoutParams);
                adDict.put(BANNER_WIDTH_KEY, kBannerWidth);
                adDict.put(BANNER_HEIGHT_KEY, kBannerHeight);
                adDict.put(AD_VIEW_KEY, bannerAd);

                CoronaBeacon.sendDeviceDataToBeacon(fRuntimeTaskDispatcher, kName, kVersionNumber, CoronaBeacon.REQUEST, placementId, new PerkBeaconListener());
              }
              else if (adUnitType.equalsIgnoreCase(INTERSTITIAL_AD_NAME)) {
                InMobiInterstitial interstitialAd = new InMobiInterstitial(coronaActivity, kPlacementId, new InMobiInterstitialAdListenerClass(placementId, INTERSTITIAL_AD_NAME));
                if (attributionExtras != null) {
                  interstitialAd.setExtras(attributionExtras);
                }

                interstitialAd.load();
                adDict.put(AD_VIEW_KEY, interstitialAd);
                CoronaBeacon.sendDeviceDataToBeacon(fRuntimeTaskDispatcher, kName, kVersionNumber, CoronaBeacon.REQUEST, placementId, new PerkBeaconListener());
              }
              else {
                Log.i(CORONA_LOG_TAG, "ERROR: Unsupported Ad unit type");
              }

              // Only add this Ads properties to the adDict/inMobi dict if it was created successfully
              if (adDict.containsKey(AD_VIEW_KEY)) {
                adDict.put(AD_UNIT_TYPE_KEY, adUnitType);
                adDict.put(HAS_LOADED_KEY, false);
                inMobiAds.put(placementId, adDict);
              }
            }
          }
        };

        coronaActivity.runOnUiThread(runnableActivity);
      }

      return 0;
    }
  }

  // [Lua] inMobi.isLoaded(placementId)
  private class isLoaded implements NamedJavaFunction
  {
    // Gets the name of the Lua function as it would appear in the Lua script
    @Override
    public String getName()
    {
      return "isLoaded";
    }

    // This method is executed when the Lua function is called
    @Override
    public int invoke(LuaState L)
    {
      // The Ads placement id
      final String placementId;
      // By default, the Ad has not loaded yet
      boolean hasLoaded = false;

      // Ensure that .init() has been called first (fListener will not be null if init is called, as it's a required param)
      if (fListener == CoronaLua.REFNIL)
      {
        Log.i(CORONA_LOG_TAG, "ERROR: inMobi.isLoaded(placementId) you must call inMobi.init() before making any other inMobi.* Api calls");
        return 0;
      }

      // Get the placement id
      if (L.type(1) == LuaType.STRING)
      {
        placementId = L.toString(1);
      }
      else
      {
        Log.i(CORONA_LOG_TAG, "ERROR: inMobi.isLoaded(placementId) placementId (string) expected, got " + L.typeName(1));
        return 0;
      }

      // Ensure the Ad exists in the inMobiAds dict
      if (inMobiAds.containsKey(placementId))
      {
        // Get the adDict for this Ad
        Map<String, Object> adDict = (Map<String, Object>)inMobiAds.get(placementId);
        // Check if the Ad has loaded
        hasLoaded = Boolean.TRUE.equals(adDict.get(HAS_LOADED_KEY));
      }

      // Push the result
      L.pushBoolean(hasLoaded);

      return 1;
    }
  }

  // [Lua] inMobi.show(placementId)
  private class show implements NamedJavaFunction
  {
    // Gets the name of the Lua function as it would appear in the Lua script
    @Override
    public String getName()
    {
      return "show";
    }

    // This method is executed when the Lua function is called
    @Override
    public int invoke(LuaState L)
    {
      // The Ads placement id
      final String placementId;
      String bannerAlignY = "top";

      // Ensure that .init() has been called first (fListener will not be null if init is called, as it's a required param)
      if (fListener == CoronaLua.REFNIL)
      {
        Log.i(CORONA_LOG_TAG, "ERROR: inMobi.show(placementId, options) you must call inMobi.init() before making any other inMobi.* Api calls");
        return 0;
      }

      // Get the placement id
      if (L.type(1) == LuaType.STRING)
      {
        placementId = L.toString(1);
      }
      else
      {
        Log.i(CORONA_LOG_TAG, "ERROR: inMobi.show(placementId, options) placementId (string) expected, got " + L.typeName(1));
        return 0;
      }

      // Get the options table (if it exists)
      if (L.type(2) == LuaType.TABLE)
      {
        // Get the yAlign key
        L.getField(-1, "yAlign");

        // Ensure that yAlign is a string
        if (L.type(-1) == LuaType.STRING)
        {
          bannerAlignY = L.toString(-1);
        }
        else
        {
          Log.i(CORONA_LOG_TAG, "WARNING: inMobi.show(placementId, options) options.yAlign (string) expected, got " + L.typeName(-1));
        }
        // Pop the yAlign key and options table
        L.pop(2);
      }

      // Get the corona activity
      final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();
      // Set the banner alignment
      final String kBannerAlignY = bannerAlignY;

      // If the corona activity isn't null
      if (coronaActivity != null)
      {
        // Create a new runnable object to invoke our activity
        Runnable runnableActivity = new Runnable()
        {
          public void run()
          {
            // Ensure the Ad exists in the inMobi dict
            if (inMobiAds.containsKey(placementId))
            {
              // Get the adDict for this ad
              Map<String, Object> adDict = (Map<String, Object>)inMobiAds.get(placementId);
              // Get the adUnitType
              String adUnitType = (String)adDict.get(AD_UNIT_TYPE_KEY);
              // Check if the Ad has loaded
              boolean hasLoaded = Boolean.TRUE.equals(adDict.get(HAS_LOADED_KEY));

              // If the Ad has loaded
              if (hasLoaded)
              {
                // Show a banner Ad
                if (adUnitType.equalsIgnoreCase(BANNER_AD_NAME))
                {
                  // Send the device data to the beacon endpoint
                  CoronaBeacon.sendDeviceDataToBeacon(fRuntimeTaskDispatcher, kName, kVersionNumber, CoronaBeacon.IMPRESSION, placementId, new PerkBeaconListener());
                  LayoutParams layoutParams = (LayoutParams)adDict.get(BANNER_LAYOUT);
                  layoutParams.topMargin = 0;
                  String chosenBannerAlignY = "top";
                  boolean isValidAlignment = false;
                  String bannerAlignOptions[] = {"top", "center", "bottom"};

                  // Ensure the chosen alignment is valid
                  for (String alignment: bannerAlignOptions)
                  {
                    // If the chosen alignment matches one of the valid alignments
                    if (kBannerAlignY.equalsIgnoreCase(alignment))
                    {
                      chosenBannerAlignY = alignment;
                      isValidAlignment = true;
                      break;
                    }
                  }

                  // Set the banner alignment
                  if (!isValidAlignment)
                  {
                    chosenBannerAlignY = "top";
                    Log.i(CORONA_LOG_TAG, "WARNING: Invalid banner alignment specified. Using the default alignment 'top'");
                  }

                  // Get the banner Ad
                  InMobiBanner bannerAd = (InMobiBanner)adDict.get(AD_VIEW_KEY);

                  // Set the banners vertical aligment
                  if (chosenBannerAlignY.equalsIgnoreCase("top"))
                  {
                    layoutParams.gravity = Gravity.CENTER_HORIZONTAL | Gravity.TOP;
                  }
                  else if (chosenBannerAlignY.equalsIgnoreCase("center"))
                  {
                    layoutParams.gravity = Gravity.CENTER_HORIZONTAL | Gravity.CENTER;
                  }
                  else if (chosenBannerAlignY.equalsIgnoreCase("bottom"))
                  {
                    layoutParams.gravity = Gravity.CENTER_HORIZONTAL | Gravity.BOTTOM;
                  }

                  // Show the banner Ad
                  bannerAd.setVisibility(View.VISIBLE);

                  // Create the displayed event
                  Map<String, Object> coronaEvent = new HashMap<String, Object>();
                  coronaEvent.put(CORONA_PHASE_EVENT, DISPLAYED_EVENT);
                  coronaEvent.put(CORONA_TYPE_EVENT, adUnitType);
                  coronaEvent.put(CORONA_PLACEMENT_ID_EVENT, placementId);
                  dispatchLuaEvent(coronaEvent);
                }
                else if (adUnitType.equalsIgnoreCase(INTERSTITIAL_AD_NAME))
                {
                  // Get the interstitial Ad
                  InMobiInterstitial interstitialAd = (InMobiInterstitial)adDict.get(AD_VIEW_KEY);
                  interstitialAd.show();

                  // Send Corona Lua event
                  Map<String, Object> coronaEvent = new HashMap<String, Object>();
                  coronaEvent.put(CORONA_PHASE_EVENT, DISPLAYED_EVENT);
                  coronaEvent.put(CORONA_TYPE_EVENT, adUnitType);
                  coronaEvent.put(CORONA_PLACEMENT_ID_EVENT, placementId);
                  dispatchLuaEvent(coronaEvent);

                  CoronaBeacon.sendDeviceDataToBeacon(fRuntimeTaskDispatcher, kName, kVersionNumber, CoronaBeacon.IMPRESSION, placementId, new PerkBeaconListener());
                }
              }
              else
              {
                Log.i(CORONA_LOG_TAG, "WARNING: inMobi.show(placementId, options) placementId '" + placementId + "' has not loaded yet");
              }
            }
            else
            {
              Log.i(CORONA_LOG_TAG, "WARNING: inMobi.show(placementId, options) placementId '" + placementId + "' has not loaded yet");
            }
          }
        };

        // Run the activity on the uiThread
        coronaActivity.runOnUiThread(runnableActivity);
      }

      return 0;
    }
  }

  // [Lua] inMobi.hide(placementId)
  private class hide implements NamedJavaFunction
  {
    // Gets the name of the Lua function as it would appear in the Lua script
    @Override
    public String getName()
    {
      return "hide";
    }

    // This method is executed when the Lua function is called
    @Override
    public int invoke(LuaState L)
    {
      // The Ads placement id
      final String placementId;

      // Ensure that .init() has been called first (fListener will not be null if init is called, as it's a required param)
      if (fListener == CoronaLua.REFNIL)
      {
        Log.i(CORONA_LOG_TAG, "ERROR: inMobi.hide(placementId) you must call inMobi.init() before making any other inMobi.* Api calls");
        return 0;
      }

      // Get the placement id
      if (L.type(1) == LuaType.STRING)
      {
        placementId = L.toString(1);
      }
      else
      {
        Log.i(CORONA_LOG_TAG, "ERROR: inMobi.hide(placementId) placementId (string) expected, got " + L.typeName(1));
        return 0;
      }

      // Get the corona activity
      final CoronaActivity coronaActivity = CoronaEnvironment.getCoronaActivity();

      // If the corona activity isn't null
      if (coronaActivity != null)
      {
        // Create a new runnable object to invoke our activity
        Runnable runnableActivity = new Runnable()
        {
          public void run()
          {
            // Ensure the Ad exists in the inMobiAds dict
            if (inMobiAds.containsKey(placementId))
            {
              // Get the adDict for this Ad
              Map<String, Object> adDict = (Map<String, Object>)inMobiAds.get(placementId);
              // Get the adUnitType
              final String adUnitType = (String)adDict.get(AD_UNIT_TYPE_KEY);
              // If the adUnitType is a banner
              if (adUnitType.equalsIgnoreCase(BANNER_AD_NAME))
              {
                // Get the banner Ad
                InMobiBanner bannerAd = (InMobiBanner)adDict.get(AD_VIEW_KEY);
                // Hide the banner Ad
                bannerAd.setVisibility(View.GONE);
                // Remove the banner Ad from the view
                coronaActivity.getOverlayView().removeView(bannerAd);
                // Remove the banner ad from the inMobiAds dict
                inMobiAds.remove(placementId);
                // Null the banner Ad
                bannerAd = null;
                // Remove the adDict
                adDict.clear();
                adDict = null;
              }
              else
              {
                Log.i(CORONA_LOG_TAG, "WARNING: inMobi.hide(placementId) placementId '" + placementId +"' is not a banner");
              }
            }
            else
            {
              Log.i(CORONA_LOG_TAG, "WARNING: inMobi.hide(placementId) placementId '" + placementId + "' has not loaded");
            }
          }
        };

        // Run the activity on the uiThread
        coronaActivity.runOnUiThread(runnableActivity);
      }

      return 0;
    }
  }

  /**
   * Called after the Corona runtime has been created and just before executing the "main.lua" file.
   * <p>
   * Warning! This method is not called on the main thread.
   * @param runtime Reference to the CoronaRuntime object that has just been loaded/initialized.
   *                Provides a LuaState object that allows the application to extend the Lua API.
   */
  @Override
  public void onLoaded(CoronaRuntime runtime)
  {
    // Note that this method will not be called the first time a Corona activity has been launched.
    // This is because this listener cannot be added to the CoronaEnvironment until after
    // this plugin has been required-in by Lua, which occurs after the onLoaded() event.
    // However, this method will be called when a 2nd Corona activity has been created.
    if (fRuntimeTaskDispatcher == null)
    {
      fRuntimeTaskDispatcher = new CoronaRuntimeTaskDispatcher(runtime);
    }
  }

  /**
   * Called just after the Corona runtime has executed the "main.lua" file.
   * <p>
   * Warning! This method is not called on the main thread.
   * @param runtime Reference to the CoronaRuntime object that has just been started.
   */
  @Override
  public void onStarted(CoronaRuntime runtime)
  {
  }

  /**
   * Called just after the Corona runtime has been suspended which pauses all rendering, audio, timers,
   * and other Corona related operations. This can happen when another Android activity (ie: window) has
   * been displayed, when the screen has been powered off, or when the screen lock is shown.
   * <p>
   * Warning! This method is not called on the main thread.
   * @param runtime Reference to the CoronaRuntime object that has just been suspended.
   */
  @Override
  public void onSuspended(CoronaRuntime runtime)
  {
  }

  /**
   * Called just after the Corona runtime has been resumed after a suspend.
   * <p>
   * Warning! This method is not called on the main thread.
   * @param runtime Reference to the CoronaRuntime object that has just been resumed.
   */
  @Override
  public void onResumed(CoronaRuntime runtime)
  {
    // Clear leftover ads
    clearAds();
  }

  /**
   * Called just before the Corona runtime terminates.
   * <p>
   * This happens when the Corona activity is being destroyed which happens when the user presses the Back button
   * on the activity, when the native.requestExit() method is called in Lua, or when the activity's finish()
   * method is called. This does not mean that the application is exiting.
   * <p>
   * Warning! This method is not called on the main thread.
   * @param runtime Reference to the CoronaRuntime object that is being terminated.
   */
  @Override
  public void onExiting(CoronaRuntime runtime)
  {
    // Remove the Lua listener reference.
    if (fListener != CoronaLua.REFNIL) {
      CoronaLua.deleteRef(runtime.getLuaState(), fListener);
      fListener = CoronaLua.REFNIL;
    }

    // Clear the inMobiAds dict
    if (inMobiAds != null) {
      inMobiAds.clear();
      inMobiAds = null;
    }
    // Null the task dispatcher
    fRuntimeTaskDispatcher = null;
  }
}
