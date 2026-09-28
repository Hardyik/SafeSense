# SafeSense 🚨

SafeSense is a disaster-safety application that helps people report dangerous situations and understand hazards using AI.

Users can submit an image of a dangerous area, and SafeSense uses AI-based detection to identify hazards such as **floods, general hazards, and fire/building-related hazards**. The application can also use location data to support safer route and emergency-related features.

## 🌟 Features

* 📷 **Report Hazards** – Upload or capture an image of a dangerous situation.
* 🤖 **AI Detection** – Detect possible hazards from uploaded images.
* 🌊 **Flood Detection** – Identify flood-related situations.
* 🔥 **Fire & Building Hazard Detection** – Detect fire/building-related hazards.
* 📍 **Location Support** – Use the device's location for safety-related features.
* 🗺️ **Map Support** – Display locations and safety information on a map.
* 🔐 **User Authentication** – Secure user login using JWT authentication.
* 🗄️ **Database Support** – Store users and application data using MySQL.

## 🛠️ Technologies Used

### Frontend

* Flutter
* Dart
* HTTP
* Geolocator
* Flutter Map
* Image Picker

### Backend

* Python
* Flask
* Flask-CORS
* MySQL
* JWT
* Bcrypt
* Ultralytics YOLO
* OpenCV

## 📁 Project Structure

```text
SafeSense/
│
├── Backend/
│   ├── ai_model/
│   │   ├── flood_best.pt
│   │   ├── hazard_best.pt
│   │   └── hazard_fire_building_best.pt
│   │
│   ├── app.py
│   ├── requirements.txt
│   ├── schema.sql
│   └── test_predict.py
│
├── Frontend/
│   ├── android/
│   ├── ios/
│   ├── lib/
│   ├── pubspec.yaml
│   └── ...
│
└── README.md
```

## ⚙️ How It Works

The basic flow of SafeSense is:

```text
User
  ↓
Flutter App
  ↓
Upload Image / Send Request
  ↓
Flask Backend
  ↓
AI Model
  ↓
Hazard Detection
  ↓
Result
  ↓
Displayed in the App
```

## 🚀 Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/Hardyik/SafeSense.git
cd SafeSense
```

---

## 📱 Setup Frontend

Make sure Flutter is installed on your system.

Go to the frontend folder:

```bash
cd Frontend
```

Install dependencies:

```bash
flutter pub get
```

Check that Flutter is configured correctly:

```bash
flutter doctor
```

Run the application:

```bash
flutter run
```

You can run it on an Android emulator, physical Android device, or another Flutter-supported platform.

### Point the app at your backend

The backend address defaults to `http://10.0.2.2:5000` (Android emulator →
your PC). For a **physical device** on the same WiFi, pass your PC's LAN IP:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:5000
```

(`ipconfig` / `ifconfig` to find it. Set it once in
`lib/config/app_config.dart` if you don't want to pass the flag every run.)

## 📱 Building the release APK (phone over same WiFi)

The manifest already allows plain-HTTP LAN traffic
(`android:usesCleartextTraffic="true"`), so the release build can talk to
your local Flask backend directly.

1. **Find your PC's WiFi IP** (Windows):

   ```bat
   ipconfig   →  look for "Wireless LAN adapter Wi-Fi" → IPv4 Address, e.g. 192.168.1.20
   ```

2. **Allow Flask through Windows Firewall** (first run usually prompts —
   tick "Private networks"; if you missed the prompt):

   ```bat
   netsh advfirewall firewall add rule name="SafeSense Flask 5000" dir=in action=allow protocol=TCP localport=5000
   ```

3. **Build the APK with your PC's IP baked in:**

   ```bash
   cd Frontend
   flutter build apk --release \
     --dart-define=API_BASE_URL=http://192.168.1.20:5000
   ```

   The APK lands at `build/app/outputs/flutter-apk/app-release.apk`.
   Install it on the phone (both devices on the **same WiFi**), log in,
   and it hits your PC's MySQL-backed Flask server directly.

   > Phone and PC must be on the same WiFi network. If the phone is on
   > mobile data or a different network, it cannot reach `192.168.x.x` —
   > that's how LAN addressing works, not an app bug.

4. **Requires the Android SDK.** Install Android Studio (or command-line
   tools + `sdkmanager "platform-tools" "platforms;android-35"
   "build-tools;34.0.0"`) if `flutter doctor` shows the Android toolchain
   as missing.

---

## 🖥️ Setup Backend

Open another terminal and go to the backend folder:

```bash
cd Backend
```

Create a virtual environment:

### Windows

```bash
python -m venv venv
venv\Scripts\activate
```

### macOS / Linux

```bash
python3 -m venv venv
source venv/bin/activate
```

Install the required Python packages:

```bash
pip install -r requirements.txt
```

## 🔐 Environment Variables

Create a `.env` file inside the `Backend` folder.

Example:

```env
DB_HOST=localhost
DB_USER=root
DB_PASSWORD=your_password
DB_NAME=safesense

JWT_SECRET=your_secret_key
JWT_EXPIRY_HOURS=24

# Optional — seeds the first admin at startup so you can promote
# others from the app's Admin Dashboard.
ADMIN_EMAIL=admin@example.com
ADMIN_PASSWORD=change-me
```

> Do not upload your `.env` file or database password to GitHub.

## 🗄️ Database Setup

Make sure MySQL is installed and running.

Create the database:

```sql
CREATE DATABASE safesense;
```

Then use the provided SQL schema:

```text
Backend/schema.sql
```

Import the schema into your MySQL database.

**Already have an older database?** Run the migration instead of re-importing:

```bash
mysql -u root -p safesense < Backend/migrations/001_add_new_tables.sql
```

It adds the new tables the app now uses (emergency contacts, location
shares, emergency alerts, risk zones) and widens `uploaded_image` for
locally-stored photos.

## 🏗️ Fully Local Architecture

This build is **100% local — no Firebase, no Cloudinary, no Cloudflare**:

| Concern | Old (Firebase era) | Now |
|---|---|---|
| Auth | Firebase Auth | Flask JWT + `user` table |
| Reports/shelters | Firestore | MySQL via `/api/*` |
| Report photos | Cloudinary | `Backend/uploads/` served at `/uploads/<file>` |
| Push alerts | FCM + Cloudflare Worker | in-app poller (`/api/alerts`) |
| Admin actions | Firestore rules + Worker | `@require_admin` routes |

Report photos start as `pending` and appear on the public map only after
an admin verifies them in the Admin Dashboard (Reports tab).

## ▶️ Start the Backend

From the `Backend` folder:

```bash
python app.py
```

The Flask server will start and the Flutter application can communicate with it through the API.

## 🤖 AI Models

SafeSense uses trained YOLO models for hazard detection.

The repository currently contains:

```text
Backend/ai_model/
├── flood_best.pt
├── hazard_best.pt
└── hazard_fire_building_best.pt
```

These models are loaded by the Flask backend and used to analyze uploaded images.

## 🔑 Authentication

SafeSense uses:

* **JWT** for user authentication
* **Bcrypt** for password hashing

Protected API requests require a valid authentication token.

## 📸 Example Use Case

Imagine a user finds a flooded road.

1. The user opens SafeSense.
2. The user captures or uploads a photo.
3. The image is sent to the backend.
4. The AI model analyzes the image.
5. SafeSense identifies the possible hazard.
6. The result is returned to the mobile application.
7. The user can use the available safety and location features.

## 🎯 Goal

The main goal of SafeSense is to use **mobile technology, location data, and AI-based image analysis** to make disaster reporting and safety information easier to access.

## 🔮 Future Improvements

Possible future improvements include:

* Real-time disaster alerts
* More hazard detection models
* Live emergency reporting
* Improved route safety analysis
* Emergency contact integration
* Push notifications
* Better disaster-area mapping
* Support for more types of natural and man-made hazards

## 👨‍💻 Project

**SafeSense**
AI-powered disaster and hazard safety application.

Repository:
https://github.com/Hardyik/SafeSense
