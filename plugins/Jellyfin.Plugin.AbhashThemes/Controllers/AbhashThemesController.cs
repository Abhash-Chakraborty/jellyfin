using System;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Jellyfin.Plugin.AbhashThemes.Configuration;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.AbhashThemes.Controllers;

/// <summary>
/// Serves the theme loader injected into the web client.
/// </summary>
[ApiController]
[AllowAnonymous]
[Route("AbhashThemes")]
public class AbhashThemesController : ControllerBase
{
    private static readonly TimeSpan _remoteCacheDuration = TimeSpan.FromMinutes(10);
    private static readonly JsonSerializerOptions _jsonOptions = new(JsonSerializerDefaults.Web);

    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IMemoryCache _memoryCache;
    private readonly ILogger<AbhashThemesController> _logger;

    /// <summary>
    /// Initializes a new instance of the <see cref="AbhashThemesController"/> class.
    /// </summary>
    /// <param name="httpClientFactory">Instance of the <see cref="IHttpClientFactory"/> interface.</param>
    /// <param name="memoryCache">Instance of the <see cref="IMemoryCache"/> interface.</param>
    /// <param name="logger">Instance of the <see cref="ILogger{TCategoryName}"/> interface.</param>
    public AbhashThemesController(
        IHttpClientFactory httpClientFactory,
        IMemoryCache memoryCache,
        ILogger<AbhashThemesController> logger)
    {
        _httpClientFactory = httpClientFactory;
        _memoryCache = memoryCache;
        _logger = logger;
    }

    /// <summary>
    /// Gets the JavaScript bootstrap that applies the configured theme to the web client.
    /// </summary>
    /// <param name="cancellationToken">The cancellation token.</param>
    /// <returns>A JavaScript document that injects the resolved CSS (and optional JS).</returns>
    [HttpGet("inject.js")]
    [Produces("application/javascript")]
    public async Task<IActionResult> GetInjectScript(CancellationToken cancellationToken)
    {
        var config = Plugin.Instance?.Configuration;

        // No plugin / disabled: return a harmless no-op so the <script> tag never errors.
        if (config is null || !config.Enabled)
        {
            return Content("/* Abhash Themes disabled */", "application/javascript", Encoding.UTF8);
        }

        var css = await ResolveCssAsync(config, cancellationToken).ConfigureAwait(false);
        var allowJs = config.AllowRemoteJs && !string.IsNullOrWhiteSpace(config.CustomJs);

        var script = BuildScript(css, allowJs ? config.CustomJs : null);
        return Content(script, "application/javascript", Encoding.UTF8);
    }

    /// <summary>
    /// Gets the resolved CSS as a stylesheet, for debugging.
    /// </summary>
    /// <param name="cancellationToken">The cancellation token.</param>
    /// <returns>The resolved CSS.</returns>
    [HttpGet("theme.css")]
    [Produces("text/css")]
    public async Task<IActionResult> GetThemeCss(CancellationToken cancellationToken)
    {
        var config = Plugin.Instance?.Configuration;
        if (config is null || !config.Enabled)
        {
            return Content(string.Empty, "text/css", Encoding.UTF8);
        }

        var css = await ResolveCssAsync(config, cancellationToken).ConfigureAwait(false);
        return Content(css, "text/css", Encoding.UTF8);
    }

    private static string BuildScript(string css, string? js)
    {
        // JSON-encode the payloads so they are safely embedded as JS string literals.
        var cssLiteral = JsonSerializer.Serialize(css, _jsonOptions);

        var sb = new StringBuilder();
        sb.Append("(function(){try{");
        sb.Append("var id='abhash-theme';");
        sb.Append("var prev=document.getElementById(id);if(prev){prev.remove();}");
        sb.Append("var s=document.createElement('style');s.id=id;s.type='text/css';");
        sb.Append("s.appendChild(document.createTextNode(").Append(cssLiteral).Append("));");
        sb.Append("document.head.appendChild(s);");

        if (!string.IsNullOrWhiteSpace(js))
        {
            var jsLiteral = JsonSerializer.Serialize(js, _jsonOptions);
            sb.Append("try{(0,eval)(").Append(jsLiteral).Append(");}catch(e){console.error('Abhash Themes custom JS error',e);}");
        }

        sb.Append("}catch(e){console.error('Abhash Themes injection error',e);}})();");
        return sb.ToString();
    }

    private async Task<string> ResolveCssAsync(PluginConfiguration config, CancellationToken cancellationToken)
    {
        var sb = new StringBuilder();

        // 1. Curated theme stylesheet (if a curated key is selected).
        var curatedUrl = CuratedThemes.GetUrl(config.SelectedThemeKey);
        if (!string.IsNullOrWhiteSpace(curatedUrl))
        {
            var curatedCss = await FetchRemoteCssAsync(curatedUrl, cancellationToken).ConfigureAwait(false);
            if (!string.IsNullOrEmpty(curatedCss))
            {
                sb.Append("/* curated: ").Append(config.SelectedThemeKey).Append(" */\n");
                sb.Append(curatedCss).Append('\n');
            }
        }

        // 2. Custom CSS URL.
        if (!string.IsNullOrWhiteSpace(config.CustomCssUrl))
        {
            var customUrlCss = await FetchRemoteCssAsync(config.CustomCssUrl, cancellationToken).ConfigureAwait(false);
            if (!string.IsNullOrEmpty(customUrlCss))
            {
                sb.Append("/* custom url */\n").Append(customUrlCss).Append('\n');
            }
        }

        // 3. Inline custom CSS (always last so it wins).
        if (!string.IsNullOrWhiteSpace(config.CustomCss))
        {
            sb.Append("/* custom inline */\n").Append(config.CustomCss).Append('\n');
        }

        return sb.ToString();
    }

    private async Task<string> FetchRemoteCssAsync(string url, CancellationToken cancellationToken)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)
            || (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps))
        {
            _logger.LogWarning("Ignoring invalid theme URL: {Url}", url);
            return string.Empty;
        }

        var cacheKey = "abhash-theme-css:" + url;
        if (_memoryCache.TryGetValue(cacheKey, out string? cached) && cached is not null)
        {
            return cached;
        }

        try
        {
            var client = _httpClientFactory.CreateClient();
            client.Timeout = TimeSpan.FromSeconds(15);
            var css = await client.GetStringAsync(uri, cancellationToken).ConfigureAwait(false);
            _memoryCache.Set(cacheKey, css, _remoteCacheDuration);
            return css;
        }
        catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException or InvalidOperationException)
        {
            _logger.LogError(ex, "Failed to fetch theme CSS from {Url}", url);
            return string.Empty;
        }
    }
}
