using System.Globalization;

namespace Hanasu.Core.Update;

/// <summary>
/// アプリの版（"1.6.0"・"v1.6.0"・"1.6"）。数字の部分ごとに比べる（1.10.0 は 1.9.0 より新しい）。
/// 足りない部分は 0 とみなす（1.6 と 1.6.0 は同じ）。
/// </summary>
// 設計判断: DEC-REL-020
public sealed class AppVersion : IComparable<AppVersion>, IEquatable<AppVersion>
{
    private readonly int[] parts;

    private AppVersion(int[] parts) => this.parts = parts;

    public int Major => parts[0];

    /// <summary>"1.6.0" の形（部分は 3 つにそろえる。4 つ目があれば付ける）</summary>
    public override string ToString() => string.Join('.', parts);

    /// <summary>読めなければ null（数字と . 以外・空の部分・5 つ以上の部分・大きすぎる数）</summary>
    public static AppVersion? Parse(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        text = text.Trim();
        if (text.Length > 1 && (text[0] == 'v' || text[0] == 'V')) text = text[1..];
        var pieces = text.Split('.');
        if (pieces.Length is < 1 or > 4) return null;
        var numbers = new List<int>();
        foreach (var piece in pieces)
        {
            if (piece.Length == 0 || piece.Length > 6) return null;
            if (!int.TryParse(piece, NumberStyles.None, CultureInfo.InvariantCulture, out var n)) return null;
            numbers.Add(n);
        }
        while (numbers.Count < 3) numbers.Add(0);
        return new AppVersion([.. numbers]);
    }

    public static AppVersion FromVersion(Version version) =>
        new([version.Major, Math.Max(0, version.Minor), Math.Max(0, version.Build)]);

    public int CompareTo(AppVersion? other)
    {
        if (other is null) return 1;
        var length = Math.Max(parts.Length, other.parts.Length);
        for (var i = 0; i < length; i++)
        {
            var a = i < parts.Length ? parts[i] : 0;
            var b = i < other.parts.Length ? other.parts[i] : 0;
            if (a != b) return a.CompareTo(b);
        }
        return 0;
    }

    public bool Equals(AppVersion? other) => other is not null && CompareTo(other) == 0;
    public override bool Equals(object? obj) => obj is AppVersion other && Equals(other);
    public override int GetHashCode()
    {
        // 末尾の 0 を除いて、同じとみなす版が同じ値になるようにする
        var last = parts.Length;
        while (last > 3 && parts[last - 1] == 0) last--;
        var hash = new HashCode();
        for (var i = 0; i < last; i++) hash.Add(parts[i]);
        return hash.ToHashCode();
    }

    public static bool operator >(AppVersion a, AppVersion b) => a.CompareTo(b) > 0;
    public static bool operator <(AppVersion a, AppVersion b) => a.CompareTo(b) < 0;
    public static bool operator >=(AppVersion a, AppVersion b) => a.CompareTo(b) >= 0;
    public static bool operator <=(AppVersion a, AppVersion b) => a.CompareTo(b) <= 0;
}
