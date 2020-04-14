local metadata =
{
    plugin =
    {
        format = 'jar',
        manifest =
        {
            permissions = {},
            usesPermissions =
            {
                "android.permission.INTERNET",
                "android.permission.ACCESS_NETWORK_STATE",
            },
            usesFeatures =
            {
            },
            applicationChildElements =
            {
                [[
                <activity android:name="com.inmobi.rendering.InMobiAdActivity"
                android:configChanges="keyboardHidden|orientation|keyboard|smallestScreenSize|screenSize"
                android:theme="@android:style/Theme.Translucent.NoTitleBar"
                android:hardwareAccelerated="true" />

                <service android:name="com.inmobi.signals.activityrecognition.ActivityRecognitionManager" android:enabled="true" />

                <receiver
                android:name="com.inmobi.commons.core.utilities.uid.ImIdShareBroadCastReceiver"
                android:enabled="true"
                android:exported="true" >
                <intent-filter>
                <action android:name="com.inmobi.share.id" />
                </intent-filter>
                </receiver>
                ]]
            }
        }
    },

    coronaManifest = {
        dependencies = {
          ["shared.google.play.services.ads.identifier"] = "com.coronalabs",
          ["shared.android.support.v7.recyclerview"] = "com.coronalabs",
          ["shared.android.support.v7.appcompat"] = "com.coronalabs"
        }
    }
}

return metadata
