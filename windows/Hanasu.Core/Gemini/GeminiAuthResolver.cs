using Hanasu.Core.Settings;

namespace Hanasu.Core.Gemini;

/// <summary>設定から Gemini の認証方法を決める。音声入力・会議の記録・設定画面の「試す」で共通に使う。</summary>
public static class GeminiAuthResolver
{
    /// <summary>必要な情報が揃っていなければ null。サービスアカウントの JSON が読めなければ例外</summary>
    public static GeminiAuth? Resolve(AppSettings settings, ISecretProtector protector)
    {
        switch (settings.AuthMode)
        {
            case GeminiAuthMode.ApiKey:
                if (settings.ProtectedApiKey.Length == 0) return null;
                var key = protector.Unprotect(settings.ProtectedApiKey);
                return string.IsNullOrWhiteSpace(key) ? null : new GeminiAuth.ApiKey(key);
            case GeminiAuthMode.ServiceAccount:
                var path = settings.ServiceAccountPath.Trim();
                if (path.Length == 0) return null;
                return new GeminiAuth.ServiceAccount(ServiceAccountCredentials.Load(path), settings.VertexLocation);
            default:
                return null;
        }
    }
}
