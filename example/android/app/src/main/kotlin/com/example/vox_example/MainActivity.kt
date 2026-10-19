package com.example.vox_example

import com.learntoflutter.flutter_embed_unity_android.unity.FakeUnityPlayerActivity

// Extends FakeUnityPlayerActivity rather than FlutterActivity because VoxUnity
// uses AR Foundation. Unity's XR code reaches into the host activity expecting
// a UnityPlayerActivity; without this the app crashes when the AR scene starts.
// FakeUnityPlayerActivity extends FlutterActivity, so nothing else changes.
class MainActivity : FakeUnityPlayerActivity()
