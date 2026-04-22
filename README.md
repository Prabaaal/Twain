# HillsMeetSea — Private Chat App

A private chat + video call app for two people across the world.
Built with Flutter Web + Supabase + WebRTC. Hosted on Vercel. **Total cost: $0.**

---

## Stack
- **Frontend**: Flutter Web (PWA)
- **Backend**: Supabase (Singapore region)
- **Calls**: WebRTC via `flutter_webrtc` + Cloudflare STUN
- **Hosting**: Vercel (free)

---

## Setup (step by step)

### 1. Create a Supabase project
1. Go to [supabase.com](https://supabase.com) → New project
2. **Region: Southeast Asia (Singapore)**
3. Copy your **Project URL** and **anon public key**

### 2. Run the database schema
1. In Supabase dashboard → SQL Editor
2. Paste the contents of `supabase_schema.sql` and run it
3. This creates: `profiles`, `messages`, `signals` tables + RLS + storage bucket

### 3. Configure the app
Open `lib/main.dart` and replace:
```dart
const String supabaseUrl = 'https://YOUR_PROJECT.supabase.co';
const String supabaseAnonKey = 'YOUR_ANON_KEY';
```

### 4. (Optional but recommended) Add TURN server for reliable calls
Sign up free at [metered.ca](https://metered.ca) → get TURN credentials.
Add them to `lib/services/call_service.dart` in the `_iceServers` map.
This makes calls work even on strict Chinese mobile networks.

### 5. Install Flutter
```bash
# Follow https://flutter.dev/docs/get-started/install
flutter channel stable
flutter upgrade
```

### 6. Run locally
```bash
cd bondapp
flutter pub get
flutter run -d chrome
```

### 7. Deploy to Vercel
```bash
# Install Vercel CLI
npm i -g vercel

# Build and deploy
flutter build web --release --web-renderer canvaskit
vercel --prod
```
Your app will be live at `https://bondapp.vercel.app` (or your custom domain).

---

## How to install as PWA

### On iPhone:
1. Open the Vercel URL in **Safari** (must be Safari, not Chrome)
2. Tap the **Share** button (box with arrow)
3. Tap **"Add to Home Screen"**
4. Tap **Add**
5. The app icon appears on the home screen — tap to open fullscreen

### On Android:
1. Open the URL in **Chrome**
2. Tap the three-dot menu
3. Tap **"Add to Home screen"** or **"Install app"**
4. Done

---

## How it works

```
You   ←── Supabase Realtime (WebSocket) ──→  Other user 
                        ↑
                  Singapore AWS
                  

For calls:
You  ←── WebRTC P2P (via Cloudflare STUN) ──→  Other user
         (falls back to TURN relay if P2P fails)
```

- Messages are stored in Postgres and streamed via WebSocket
- Photos go to Supabase Storage (S3-compatible)
- WebRTC handles audio/video directly between devices
- Push notifications use Web Push API (works on iOS 16.4+)

---

## Folder structure
```
lib/
  main.dart              ← App entry, Supabase init, theme
  models/
    message.dart         ← Message + Profile data models
  services/
    chat_service.dart    ← Supabase realtime, send/fetch messages
    call_service.dart    ← WebRTC offer/answer/ICE signaling
  screens/
    auth_screen.dart     ← Login / signup
    chat_screen.dart     ← Main chat UI
    call_screen.dart     ← Voice / video call UI
  widgets/
    glass_container.dart ← Reusable glassmorphic card
    message_bubble.dart  ← Chat bubble (text + image)
web/
  index.html             ← PWA shell + notification permission
  manifest.json          ← PWA metadata
vercel.json              ← Vercel deploy config
supabase_schema.sql      ← Database schema (run once)
```
## Message Privacy
Since this is a "private chat app for two", the easiest way to secure it completely is to disable new signups in your Supabase dashboard once both you and your partner have created your accounts.

To do this:

Go to your Supabase Dashboard -> Authentication -> Providers -> Email.
Turn off 
**"Enable Email Signup" (ONLY AFTER BOTH OF YOU HAVE SIGNED UP ALREADY)**
or Better just do,
**Disable, "Allow new users to sign up"**
If this is disabled, new users will not be able to sign up to your application.
Once you do that, nobody else can create an account. And since your RLS policies require a user to be logged in (authenticated) to read or write data, your database becomes 100% locked down to just the two of you!