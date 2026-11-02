# ModESP Streamer app: privacy policy

The ModESP Streamer app is the remote for a ModESP Streamer network player. It is made by the
author of [ModESP_Streamer](https://github.com/Zapadenec1982/ModESP_Streamer).

**What leaves the phone.** The app talks only to ModESP Streamer devices on your local network.
It reads a streamer's state and sends the streamer your commands (volume, source, station, sound) over HTTP
and WebSocket. Nothing is sent to the author: the app has no server, no account, no analytics, no
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
phone's encrypted storage and is sent only to that streamer. Covers and station lists come from your streamer and
are held only while the app runs.

**Links.** The streamer's own settings open in your browser, at your streamer's address on your network.

**Permissions.** Network access, to reach your streamer and the catalogue, and Wi-Fi multicast,
to find streamers on your network. The app does not use the microphone, the camera, location, contacts or your files.

**Removing.** «Forget» removes a streamer and its login from the app. Uninstalling the app removes
everything it kept.

**Children.** The app is not directed to children.

**Changes.** When the app's handling of data changes, this page changes with it.

**Contact.** The developer address on the app's Google Play page.
