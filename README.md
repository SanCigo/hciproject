# Simon Says VR

Simon Says VR is a game where the player has to repeat a sequence of gestures and words said by an avatar.

## Acknowledgements

The gesture recognition algorithm used in this project, together with the way we store pre-recorded gestures, is based on the [VR-gesture-recognition-godot](https://github.com/SYBIOTE/VR-gesture-recognition-godot) repository.

## Configuration

To use the required Groq Speech-to-TextAPIs, you need to set up a `secret.cfg` file in the root directory of the project:

```ini
[api_keys]
groq_stt="YOUR_API_KEY_HERE"
```


## Building for Android (Godot 4)

To build the project for Android devices (like the Meta Quest):

1. **Install Android Build Templates:** Go to `Project > Install Android Build Template`.
2. **Configure Editor Settings:** In `Editor > Editor Settings > Export > Android`, ensure your Android SDK path and debug keystore are configured.
3. **Export Project:** Go to `Project > Export...`, click `Add...` and select `Android`. Make sure to give the app `Record Audio` and `Internet` permissions in the Export tab.
4. **Deploy:** Connect your headset via USB and use the "Remote Debug" (Android icon) in the top right to deploy directly, or click "Export Project" to generate an `.apk` file.
