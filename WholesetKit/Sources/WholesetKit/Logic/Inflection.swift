// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Resolves a localized string with automatic grammar agreement and returns it as plain text.
///
/// `String(localized:)` does not apply inflection, so a value such as
/// `"^[\(count) exercise](inflect: true)"` comes back with the raw markdown markup. Use this
/// wherever such a value must be a `String` (accessibility labels and values, joined
/// subtitles, `Text(verbatim:)`). A `Text("^[…](inflect: true)")` literal already inflects and
/// does not need it.
///
/// - Parameters:
///   - value: The localization key and default value, including any `^[…](inflect: true)` runs.
///   - bundle: The bundle holding the string catalog. `nil` uses the main bundle, which is
///     where an app's own strings live even when this helper is called from the app.
///   - locale: The locale to localize and inflect for. `nil` uses the current locale.
/// - Returns: The localized, inflected text, e.g. "1 exercise" or "5 exercises" in English.
public func inflectedString(
    _ value: String.LocalizationValue,
    bundle: Bundle? = nil,
    locale: Locale? = nil
) -> String {
    String(AttributedString(localized: value, bundle: bundle, locale: locale).inflected().characters)
}
