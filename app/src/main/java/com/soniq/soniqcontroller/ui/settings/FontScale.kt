package com.soniq.soniqcontroller.ui.settings
import com.soniq.soniqcontroller.R
import  androidx.annotation.StringRes
enum class FontScale(
    val scale: Float,
    @StringRes val labelRes: Int
) {
    SMALL(0.85f, R.string.font_scale_small),
    NORMAL(1.0f, R.string.font_scale_normal),
    LARGE(1.2f, R.string.font_scale_large),
    EXTRA_LARGE(1.5f, R.string.font_scale_extra_large)
}
