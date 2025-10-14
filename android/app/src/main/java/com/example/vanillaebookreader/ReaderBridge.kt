package com.example.vanillaebookreader

import androidx.activity.ComponentActivity

object ReaderBridge {
    init {
        System.loadLibrary("ebook_reader")
    }

    @JvmStatic
    external fun launch(activity: ComponentActivity)
}
