# Flutter Development Environment Setup

## Prerequisites

### 1. Install Flutter SDK
```bash
# Download Flutter
cd ~
git clone https://github.com/flutter/flutter.git -b stable

# Add Flutter to PATH (add these lines to ~/.bashrc or ~/.zshrc)
export PATH="$PATH:$HOME/flutter/bin"

# Reload shell configuration
source ~/.bashrc  # or source ~/.zshrc

# Verify installation
flutter doctor
```

### 2. Install Required Dependencies (Linux)
```bash
# Install essential tools
sudo apt-get update
sudo apt-get install curl git unzip xz-utils zip libglu1-mesa

# Install Android toolchain dependencies
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev
```

### 3. Install Android Studio (Recommended) or Android SDK
```bash
# Download from: https://developer.android.com/studio
# Or use snap:
sudo snap install android-studio --classic

# After installation, open Android Studio and:
# - Install Android SDK (API 33 or higher recommended)
# - Install Android SDK Command-line Tools
# - Install Android SDK Build-Tools
# - Accept Android licenses
flutter doctor --android-licenses
```

### 4. VS Code Setup (if using VS Code)
```bash
# Install Flutter extension
# In VS Code: Ctrl+Shift+X, search "Flutter" and install
# This also installs the Dart extension automatically
```

## Project Setup

### 1. Install Project Dependencies
```bash
cd /home/entropy/Code/preconnect

# Get Flutter packages
flutter pub get

# For iOS (if on macOS)
cd ios && pod install && cd ..
```

### 2. Check Your Setup
```bash
# Run Flutter doctor to see what's missing
flutter doctor -v

# List available devices (emulators, connected phones)
flutter devices
```

### 3. Run the App

#### Option A: Using an Android Emulator
```bash
# Create an emulator (if you haven't)
# Open Android Studio > Tools > Device Manager > Create Device

# Start the emulator, then:
flutter run
```

#### Option B: Using a Physical Device
```bash
# Enable USB Debugging on your Android device
# Connect via USB
# Allow USB debugging when prompted

# Verify device is connected
flutter devices

# Run the app
flutter run
```

#### Option C: Using VS Code
1. Open the project in VS Code
2. Press `F5` or click "Run and Debug"
3. Select "Dart & Flutter" when prompted
4. Choose your device from the device selector

### 4. Hot Reload (Flutter's Best Feature!)
While the app is running:
- Press `r` in the terminal for hot reload (keeps app state)
- Press `R` for hot restart (resets app state)
- Press `q` to quit

## Configuration

### Environment Variables
This app uses environment variables. Check if there's a `.env` file needed:
```bash
# The app has load_env.sh in ios/Flutter/
# You may need to create environment configuration files
```

### Key Properties (Android)
For Android builds, you'll need signing keys:
```bash
# Copy the example file
cp android/key.properties.example android/key.properties
# Edit android/key.properties with your signing key info
```

## Common Commands

```bash
# Get dependencies
flutter pub get

# Run the app
flutter run

# Build for Android
flutter build apk
flutter build appbundle

# Clean build cache (if you have issues)
flutter clean
flutter pub get

# Check for updates
flutter upgrade

# Analyze code
flutter analyze

# Run tests
flutter test
```

## Quick Dart/Flutter Tips for Kotlin Developers

### Similarities with Kotlin:
- **Null safety**: Dart has `?` for nullable types, just like Kotlin
- **Data classes**: Dart has similar features (though more manual)
- **Lambda expressions**: Similar syntax `() => expression`
- **Collections**: `List`, `Map`, `Set` with similar methods
- **Async/await**: Same keywords and concepts
- **Extension methods**: Dart supports these too

### Key Differences:
- **Widget-based UI**: Everything is a widget (like Compose, but more mature)
- **`const` constructors**: For compile-time constants
- **`final` vs `const`**: `final` is runtime constant, `const` is compile-time
- **No `val`**: Use `final` for immutable variables
- **`var` with type inference**: Like Kotlin's `val` with inference

### Example Comparison:
```kotlin
// Kotlin
val name: String? = null
data class User(val name: String, val age: Int)
```

```dart
// Dart
String? name = null;
class User {
  final String name;
  final int age;
  User({required this.name, required this.age});
}
```

## Troubleshooting

### Issue: "Flutter doctor" shows problems
```bash
# Run with verbose output to see details
flutter doctor -v

# Accept Android licenses
flutter doctor --android-licenses
```

### Issue: "Pub get" fails
```bash
# Clean and retry
flutter clean
flutter pub get
```

### Issue: Build fails on Android
```bash
# Clean Android build
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
```

### Issue: "No devices found"
```bash
# Check connected devices
adb devices

# Restart adb
adb kill-server
adb start-server
```

## Next Steps

1. **Explore the codebase**:
   - `lib/main.dart` - Entry point
   - `lib/pages/` - UI screens
   - `lib/model/` - Data models
   - `android/` - Native Android code (Kotlin!) you'll be familiar with

2. **Learn Flutter basics**:
   - Official tutorial: https://docs.flutter.dev/get-started/codelab
   - Widget catalog: https://docs.flutter.dev/ui/widgets
   - For Kotlin devs: https://docs.flutter.dev/get-started/flutter-for/android-devs

3. **Debug the app**:
   - Use Flutter DevTools for debugging
   - Set breakpoints in VS Code
   - Use `print()` statements (or `debugPrint()`)

4. **Start making changes**:
   - Try modifying a UI element in `lib/pages/`
   - Use hot reload to see changes instantly!

## Project-Specific Notes

This appears to be a **BRACU (BRAC University) student app** with features like:
- Class schedules
- Exam schedules  
- Attendance tracking
- Notifications and alarms
- QR code scanning
- Friend schedule sharing

The native Android code in `android/` is written in Kotlin, so you can leverage your existing knowledge there!
