# RunTrack pilot: registration and watch setup

Open [RunTrack](https://run-track-app.vercel.app) on your phone or computer. Register with your own email address and a password, open the verification email, then sign in. Check spam if the email is missing. Enter the club code supplied by the organiser to join as an athlete. Shane’s founding administrator account is already registered; new runners do not need an administrator account.

You can use the club, sessions and RSVPs immediately. Choose **Skip for now, use the club** in running-data setup if you do not want Google workout imports. RunTrack registration uses email and password; a Google login is only needed for optional workout sharing. Adding RunTrack to your home screen still uses the website. The watch and health apps below must be set up separately on your phone.

## Android and Garmin

The route is **Garmin watch → Garmin Connect → Health Connect → Google Health → RunTrack**.

1. Update Garmin Connect and sync a real recorded run from your watch. Confirm it appears in Garmin Connect.
2. Garmin’s Health Connect sharing requires **Android 14 or later**. Search your phone settings for Health Connect. In its app permissions, allow Garmin Connect to write supported fitness data. Garmin sends data after a successful device sync and does not read it back. Installing Health Connect on an older Android phone does not add this Garmin feature. [Garmin’s sharing guide](https://support.garmin.com/en-GB/?faq=JToBEy0jfe6pIygark2Ui5).
3. Install Google Health from the Play Store and finish its profile setup with an adult Google Account. In Google Health, open **Connections → Partner apps**, then set up **Sync your favorite health apps**. Choose the fitness data you want to share and permit reading exercise and distance from Health Connect. Heart rate is optional; medical records are unnecessary. Review the optional history and background permissions.
4. In Google Health’s Health Connect settings, check for a recent sync time or request a manual sync. **Find your running workout in Google Health before connecting RunTrack.** See [Google’s Health Connect instructions](https://support.google.com/googlehealth/answer/14506680?hl=en).
5. Return to RunTrack, choose Android and Garmin, then follow the wizard. Only tick the explicit health-data consent when you want RunTrack to import and store running workouts. Tap **Connect Google Health** and choose the same Google Account used in the Google Health app. This address may differ from your RunTrack email.
6. After returning, check the actual connection status and choose **Sync and check workouts**. If more history remains, continue syncing. A linked account may contain no available runs.

## iPhone

Use **watch companion app → Apple Health → Google Health → RunTrack**. For Garmin, enable Connect’s workout/distance sharing in Apple Health’s profile app permissions, and keep Garmin Connect open during the watch sync. [Garmin’s Apple Health instructions](https://support.garmin.com/en-GB/?faq=lK5FPB9iPF5PXFkIpFlFPA).

In Google Health, open its connections, choose Apple Health under apps and services, and complete the permissions. Check your run is visible before returning to RunTrack. [Google’s Apple Health instructions](https://support.google.com/googlehealth/answer/17037331?hl=en). Fitbit and Pixel Watch workouts can sync straight into Google Health without this extra bridge.

## Pilot access and missing data

Google connections are currently in testing and require an approved Google Account. If Google blocks access, contact **hello@tswebdev.co.uk** with the Google Account address you want to use. Runners can register and use the club while waiting. Testing permission can expire after seven days; reconnect when prompted. [Google’s testing token rules](https://developers.google.com/identity/protocols/oauth2/).

If a run is missing, trace the route backwards from Google Health to the phone’s health app and then the watch app. Check each app’s permissions and sync the watch again. Historical imports and heart-rate detail depend on every app in the route. Garmin summaries do not include detailed lap splits or routes through this connection; do not expect a complete Garmin history. [Google’s device-sharing limits](https://support.google.com/googlehealth/answer/14236613?hl=en).

Setup progress checkboxes do not connect an account or grant RunTrack health-data permission. Imported runs are private until you explicitly choose sharing. Disconnecting stops future imports; previously imported runs remain in your account. You can export your data or delete the account from RunTrack settings.
