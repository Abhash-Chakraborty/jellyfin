using System;
using System.Collections.Generic;
using Jellyfin.Plugin.AbhashThemes.Configuration;
using MediaBrowser.Common.Configuration;
using MediaBrowser.Common.Plugins;
using MediaBrowser.Model.Plugins;
using MediaBrowser.Model.Serialization;

namespace Jellyfin.Plugin.AbhashThemes;

/// <summary>
/// The Abhash Themes plugin. Injects administrator-selected CSS (and optional JS)
/// into the served web client without modifying the bundled web source.
/// </summary>
public class Plugin : BasePlugin<PluginConfiguration>, IHasWebPages
{
    /// <summary>
    /// Initializes a new instance of the <see cref="Plugin"/> class.
    /// </summary>
    /// <param name="applicationPaths">Instance of the <see cref="IApplicationPaths"/> interface.</param>
    /// <param name="xmlSerializer">Instance of the <see cref="IXmlSerializer"/> interface.</param>
    public Plugin(IApplicationPaths applicationPaths, IXmlSerializer xmlSerializer)
        : base(applicationPaths, xmlSerializer)
    {
        Instance = this;
    }

    /// <summary>
    /// Gets the current plugin instance.
    /// </summary>
    public static Plugin? Instance { get; private set; }

    /// <inheritdoc />
    public override Guid Id => new("7f3c2d18-4b6a-4d2e-9c1f-2a5e8b0d4c11");

    /// <inheritdoc />
    public override string Name => "Abhash Themes";

    /// <inheritdoc />
    public override string Description => "Inject selectable CSS themes and optional JavaScript into the web client. Updatable from the dashboard, no rebuild required.";

    /// <inheritdoc />
    public IEnumerable<PluginPageInfo> GetPages()
    {
        yield return new PluginPageInfo
        {
            Name = Name,
            EmbeddedResourcePath = GetType().Namespace + ".Configuration.config.html"
        };
    }
}
