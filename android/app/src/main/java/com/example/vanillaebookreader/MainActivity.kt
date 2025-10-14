package com.example.vanillaebookreader

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        ReaderBridge.launch(this)

        setContent {
            MaterialTheme {
                Surface {
                    Text("Launching Vanilla Ebook Reader (Rust UI renders in native window)")
                }
            }
        }
    }
}
