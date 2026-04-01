package com.ifachang.paimingpian

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.ifachang.paimingpian.ui.theme.PaiMingPianTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            PaiMingPianTheme {
                PaiMingPianApp()
            }
        }
    }
}
