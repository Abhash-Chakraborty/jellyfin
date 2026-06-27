using System;
using MediaBrowser.Model.Plugins;

namespace Jellyfin.Plugin.AbhashThemes.Configuration;

/// <summary>
/// Configuration for the Abhash Themes plugin.
/// </summary>
public class PluginConfiguration : BasePluginConfiguration
{
    /// <summary>
    /// Initializes a new instance of the <see cref="PluginConfiguration"/> class.
    /// </summary>
    public PluginConfiguration()
    {
        Enabled = true;
        SelectedThemeKey = "none";
        CustomCssUrl = string.Empty;
        CustomCss = string.Empty;
        CustomJs = string.Empty;
        AllowRemoteJs = false;
    }

    /// <summary>
    /// Gets or sets a value indicating whether theme injection is enabled.
    /// When false, the injected loader returns an empty script and no theming is applied.
    /// </summary>
    public bool Enabled { get; set; }

    /// <summary>
    /// Gets or sets the key of the selected curated theme.
    /// Use "none" for no curated theme or "custom" to rely solely on
    /// <see cref="CustomCssUrl"/> / <see cref="CustomCss"/>.
    /// </summary>
    public string SelectedThemeKey { get; set; }

    /// <summary>
    /// Gets or sets an additional custom CSS URL (for example a GitHub raw URL).
    /// Fetched server-side and injected after the curated theme.
    /// </summary>
    public string CustomCssUrl { get; set; }

    /// <summary>
    /// Gets or sets inline custom CSS, appended after the curated theme and the custom URL.
    /// </summary>
    public string CustomCss { get; set; }

    /// <summary>
    /// Gets or sets inline custom JavaScript. Only injected when <see cref="AllowRemoteJs"/> is true.
    /// </summary>
    public string CustomJs { get; set; }

    /// <summary>
    /// Gets or sets a value indicating whether custom JavaScript injection is allowed.
    /// Disabled by default because it executes arbitrary code in every client browser.
    /// </summary>
    public bool AllowRemoteJs { get; set; }
}
