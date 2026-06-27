using System.Collections.Generic;
using System.Linq;

namespace Jellyfin.Plugin.AbhashThemes;

/// <summary>
/// A curated community theme entry (display name plus a stylesheet URL).
/// </summary>
public sealed class CuratedTheme
{
    /// <summary>
    /// Initializes a new instance of the <see cref="CuratedTheme"/> class.
    /// </summary>
    /// <param name="key">Stable lookup key, stored in configuration.</param>
    /// <param name="displayName">Human-readable name shown in the dashboard.</param>
    /// <param name="url">Absolute URL to the theme stylesheet (CSS).</param>
    public CuratedTheme(string key, string displayName, string url)
    {
        Key = key;
        DisplayName = displayName;
        Url = url;
    }

    /// <summary>
    /// Gets the stable lookup key.
    /// </summary>
    public string Key { get; }

    /// <summary>
    /// Gets the human-readable name.
    /// </summary>
    public string DisplayName { get; }

    /// <summary>
    /// Gets the absolute stylesheet URL.
    /// </summary>
    public string Url { get; }
}

/// <summary>
/// Built-in list of well-known community CSS themes.
/// </summary>
/// <remarks>
/// These are convenience starting points sourced from popular community theme
/// repositories and served through the jsDelivr CDN for stable raw delivery.
/// They are not maintained by this fork; an administrator can always paste any
/// other raw stylesheet URL into the plugin's "Custom CSS URL" field instead.
/// </remarks>
public static class CuratedThemes
{
    /// <summary>
    /// The configuration key used when no curated theme is selected.
    /// </summary>
    public const string NoneKey = "none";

    /// <summary>
    /// The configuration key used when only custom CSS/URL should apply.
    /// </summary>
    public const string CustomKey = "custom";

    private static readonly IReadOnlyList<CuratedTheme> _themes = new List<CuratedTheme>
    {
        new CuratedTheme(
            "monochromic",
            "Monochromic (CTalvio)",
            "https://cdn.jsdelivr.net/gh/CTalvio/Ultrachromic@main/presets/monochromic_preset.css"),
        new CuratedTheme(
            "kaleidochromic",
            "Kaleidochromic (CTalvio)",
            "https://cdn.jsdelivr.net/gh/CTalvio/Ultrachromic@main/presets/kaleidochromic_preset.css"),
        new CuratedTheme(
            "novachromic",
            "Novachromic (CTalvio)",
            "https://cdn.jsdelivr.net/gh/CTalvio/Ultrachromic@main/presets/novachromic_preset.css"),
        new CuratedTheme(
            "monochromic-classic",
            "Monochromic Classic (CTalvio)",
            "https://cdn.jsdelivr.net/gh/CTalvio/Monochromic@master/default_style.css"),
    };

    /// <summary>
    /// Gets the curated themes.
    /// </summary>
    public static IReadOnlyList<CuratedTheme> All => _themes;

    /// <summary>
    /// Resolves the stylesheet URL for a curated theme key.
    /// </summary>
    /// <param name="key">The configured theme key.</param>
    /// <returns>The stylesheet URL, or <see langword="null"/> when the key is not a curated theme.</returns>
    public static string? GetUrl(string? key)
    {
        if (string.IsNullOrWhiteSpace(key))
        {
            return null;
        }

        return _themes.FirstOrDefault(t => string.Equals(t.Key, key, System.StringComparison.OrdinalIgnoreCase))?.Url;
    }
}
