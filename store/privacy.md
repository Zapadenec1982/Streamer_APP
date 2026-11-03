# ModESP Streamer app: privacy policy

The ModESP Streamer app is the remote for a ModESP Streamer network player. It is made by the
author of [ModESP_Streamer](https://github.com/Zapadenec1982/ModESP_Streamer).

**What leaves the phone.** The app talks only to ModESP Streamer devices on your local network.
It reads a streamer's state and sends the streamer your commands and settings (volume, source, station,
sound, speakers, and the streamer's own screen, clock, Wi-Fi and Bluetooth) over HTTP and WebSocket.
A Wi-Fi password you type goes to the streamer, for it to join that network. Nothing is sent to the
author: the app has no server, no account, no analytics, no
advertising and no crash reporting.

**The station catalogue.** The catalogue and the stations' logos come from
[Radio Browser](https://www.radio-browser.info), a public catalogue of internet radio, which the
app asks directly from the phone, as a web browser would: a search sends the words searched for,
and a logo is fetched from the address Radio Browser gives for it — usually the station's own site.
Radio Browser and those sites see the phone's internet address, as with any visit. The app sends
them nothing else, and asks them only when the catalogue or a list with logos is open.

**Finding streamers.** The app looks for streamers on your Wi-Fi with mDNS (Bonjour). This stays on your
local network.

**What the app keeps on the phone.** The streamers you added (their names and addresses), which one is
chosen, and the app's language. If a streamer asks for its login, the login is kept in the
phone's encrypted storage and is sent only to that streamer; a login you change in the app is kept
the same way. Covers and station lists come from your streamer and
are held only while the app runs.

**Files.** A file goes in or out only when you choose it in the phone's own file picker: a firmware
image or a backup you pick is sent to your streamer, and a station list or equalizer filters you pick
are read into it; a backup, a station list or filters you save are written where you choose. The app
reads no other file and needs no storage permission.

**Permissions.** Network access, to reach your streamer and the catalogue, and Wi-Fi multicast,
to find streamers on your network. The app does not use the microphone, the camera, location or contacts.

**Removing.** «Forget» removes a streamer and its login from the app. Uninstalling the app removes
everything it kept.

**Children.** The app is not directed to children.

**Changes.** When the app's handling of data changes, this page changes with it.

**Contact.** The developer address on the app's Google Play page.
