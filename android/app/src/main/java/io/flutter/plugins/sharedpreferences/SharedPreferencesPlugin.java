package io.flutter.plugins.sharedpreferences;

/**
 * Compatibility shim for Flutter's generated registrant.
 *
 * The current plugin package exposes a Kotlin implementation that is not
 * visible to javac in this project setup, so we route registration through the
 * public Java legacy implementation instead.
 */
public class SharedPreferencesPlugin extends LegacySharedPreferencesPlugin {}
