using System.Globalization;
using System.Text.RegularExpressions;
using Hanasu.Core.Ai;
using Hanasu.Core.Meetings;

namespace Hanasu.Core.Meetings
{
    public sealed partial class Meeting
    {
        // 要件: REQ-MTG-121, REQ-MTG-126
        // 設計判断: DEC-MTG-121
        /// <summary>議事録に使う発言だけを残した写し（hanasu コマンドで、除いた発言を外に出さないため）</summary>
        public Meeting WithUsedUtterancesOnly()
        {
            var copy = (Meeting)MemberwiseClone();
            copy.Utterances = UsedUtterances.ToList();
            return copy;
        }

        /// <summary>コマンドで指定しやすい ID（フォルダ名の空白を _ にしたもの。例: 2026-11-02_1312）</summary>
        public string Slug => SlugOf(Id);

        // 設計判断: DEC-MTG-120
        public static string SlugOf(string reference) => reference.Replace(' ', '_');
    }
}

namespace Hanasu.Core.Command
{
    // 過去の会議への質問。Mac 版 MeetingAsk.swift の移植（集め方・件数と文字数の上限・期間・同じプロンプト ask.*）。
    // 決まりを変えるときは Mac 版も両方を直す。質問から検索語を取り出す分け方だけは違う（Mac は NLTokenizer、Windows は文字の種類の切れ目。DEC-MTG-154）

    /// <summary>AI に渡した会議 1 件（プロンプトでは M1, M2, …）</summary>
    public sealed record AskSource(int Number, Meeting Meeting, bool Matched);

    /// <summary>期間（Swift の DateInterval と同じく、終わりを含む）</summary>
    public readonly record struct AskInterval(DateTimeOffset Start, DateTimeOffset End)
    {
        public bool Contains(DateTimeOffset date) => Start <= date && date <= End;
    }

    public sealed record AskContext(IReadOnlyList<AskSource> Sources, IReadOnlyList<string> Keywords, AskInterval? Period, string Prompt);

    public sealed record AskAnswer(string Text, IReadOnlyList<AskSource> Sources, IReadOnlyList<AskSource> Cited, IReadOnlyList<string> Keywords);

    // 要件: REQ-MTG-016, REQ-MTG-126
    // 設計判断: DEC-MTG-052, DEC-MTG-053, DEC-MTG-054, DEC-MTG-124
    public static partial class MeetingAsk
    {
        public sealed record Options
        {
            /// <summary>AI に渡す会議の上限</summary>
            public int MaxMeetings { get; init; } = 8;
            /// <summary>AI に渡す本文の合計の上限（書記素の数）</summary>
            public int MaxCharacters { get; init; } = 150_000;
            /// <summary>議事録がない会議で、文字起こしを渡す上限</summary>
            public int MaxTranscriptCharacters { get; init; } = 40_000;
            /// <summary>はっきり指定した期間（--since / --until）。あれば質問文の期間の語より優先し、期間の外の会議は使わない</summary>
            public AskInterval? Period { get; init; }
        }

        // 要件: REQ-COM-061
        public static string Instruction => Prompts.Text("ask.system");

        /// <summary>
        /// 質問に関係しそうな会議を集め、AI に渡す本文を作る。
        /// 1. 質問の語でヒットした会議（ヒットした語の種類が多い順、同じなら新しい順） 2. 足りなければ直近の会議
        /// </summary>
        public static AskContext GatherContext(string question, IReadOnlyList<Meeting> meetings, Options options,
            DateTimeOffset now, TimeZoneInfo zone)
        {
            var keywords = Keywords(question);
            var pool = meetings.Where(m => m.Status is MeetingStatus.Done or MeetingStatus.Failed)
                .Where(m => m.Utterances.Count > 0 || m.Minutes is not null).ToList();
            AskInterval? period;
            if (options.Period is { } explicitPeriod)
            {
                // はっきり指定した期間は、会議がなくても広げない
                period = explicitPeriod;
                pool = pool.Where(m => explicitPeriod.Contains(m.StartedAt)).ToList();
            }
            else
            {
                period = PeriodIn(question, now, zone);
                if (period is { } derived)
                {
                    var inPeriod = pool.Where(m => derived.Contains(m.StartedAt)).ToList();
                    if (inPeriod.Count > 0) pool = inPeriod;
                }
            }
            var poolIds = pool.Select(m => m.Id).ToHashSet(StringComparer.Ordinal);

            // 語ごとに検索し、会議ごとに「ヒットした語の数」と「ヒットした発言」を集める
            var score = new Dictionary<string, double>(StringComparer.Ordinal);
            var hitBlocks = new Dictionary<string, HashSet<string>>(StringComparer.Ordinal);
            foreach (var keyword in keywords)
            {
                foreach (var result in MeetingSearch.Scan(meetings, keyword, hitsPerMeeting: 50).Where(r => poolIds.Contains(r.Meeting.Id)))
                {
                    var id = result.Meeting.Id;
                    // 長い語（複合語）ほど重く、ヒット数は少しだけ効かせる
                    score[id] = score.GetValueOrDefault(id) + TextElements.Count(keyword) + Math.Min(result.TotalHits, 10) * 0.1;
                    foreach (var hit in result.Hits.Where(h => h.Kind == SearchHitKind.Transcript))
                    {
                        if (!hitBlocks.TryGetValue(id, out var set)) hitBlocks[id] = set = new HashSet<string>(StringComparer.Ordinal);
                        set.Add(hit.BlockId);
                    }
                }
            }
            var matched = pool.Where(m => score.ContainsKey(m.Id))
                .OrderByDescending(m => score[m.Id]).ThenByDescending(m => m.StartedAt).ToList();
            var recent = pool.Where(m => !score.ContainsKey(m.Id)).OrderByDescending(m => m.StartedAt).ToList();

            var sources = new List<AskSource>();
            var sections = new List<string>();
            var used = 0;
            // 要件: REQ-COM-061（日付の曜日はプロンプトの言語で書く）
            var language = PromptLanguage.Current;
            foreach (var meeting in matched.Concat(recent))
            {
                if (sources.Count >= options.MaxMeetings) break;
                var number = sources.Count + 1;
                var body = Material(meeting, hitBlocks.GetValueOrDefault(meeting.Id) ?? new HashSet<string>(), options);
                var length = TextElements.Count(body);
                if (sources.Count > 0 && used + length > options.MaxCharacters) continue;
                used += length;
                sources.Add(new AskSource(number, meeting, score.ContainsKey(meeting.Id)));
                sections.Add($"<meeting id=\"M{number}\" date=\"{FormatDate(meeting.StartedAt, language, zone)}\" length=\"{Meeting.Clock(meeting.Duration)}\" title=\"{meeting.Title.Replace('"', '\'')}\">\n{body}\n</meeting>");
            }
            var prompt = Prompts.Text("ask.today", ("date", FormatDate(now, language, zone))) + "\n\n"
                + string.Join("\n\n", sections) + "\n\n<question>\n" + question + "\n</question>";
            return new AskContext(sources, keywords, period, prompt);
        }

        /// <summary>プロンプトに書く日時（"2026/11/03 (火) 14:30"。曜日はプロンプトの言語で、その時差で）</summary>
        public static string FormatDate(DateTimeOffset date, PromptLanguage language, TimeZoneInfo zone) =>
            language.FormatDate(TimeZoneInfo.ConvertTime(date, zone).DateTime, "yyyy/MM/dd (E) HH:mm");

        // 設計判断: DEC-MTG-053, DEC-COM-054
        /// <summary>
        /// 会議 1 件分の資料。議事録があれば議事録と、検索でヒットした発言の前後を渡す。
        /// 議事録がなければ文字起こしを渡す（長すぎるときはヒットした発言の前後か、冒頭だけ）
        /// </summary>
        public static string Material(Meeting meeting, IReadOnlySet<string> hitBlocks, Options options)
        {
            // 設計判断: DEC-MTG-091
            var blocks = meeting.BlocksForMinutes();
            var language = PromptLanguage.Current;
            string Line(Utterance b) => $"[{Meeting.Clock(b.Start)}] {meeting.PromptName(b.Speaker, language)}: {b.Text}";
            string Excerpts(int limit)
            {
                var indices = new SortedSet<int>();
                for (var i = 0; i < blocks.Count; i++)
                {
                    if (!hitBlocks.Contains(blocks[i].Id)) continue;
                    for (var j = Math.Max(0, i - 2); j <= Math.Min(blocks.Count - 1, i + 2); j++) indices.Add(j);
                }
                var lines = new List<string>();
                var count = 0;
                var previous = -2;
                foreach (var i in indices)
                {
                    if (i != previous + 1 && lines.Count > 0) lines.Add("…");
                    var text = Line(blocks[i]);
                    var length = TextElements.Count(text);
                    if (count + length > limit) break;
                    lines.Add(text);
                    count += length;
                    previous = i;
                }
                return PromptText.NeutralizeDelimiters(string.Join("\n", lines));
            }

            var minutes = meeting.Minutes?.Trim();
            if (!string.IsNullOrEmpty(minutes))
            {
                var safeMinutes = PromptText.NeutralizeDelimiters(minutes);
                if (hitBlocks.Count == 0) return $"<minutes>\n{safeMinutes}\n</minutes>";
                return $"<minutes>\n{safeMinutes}\n</minutes>\n<transcript_excerpts>\n{Excerpts(6_000)}\n</transcript_excerpts>";
            }
            var transcript = PromptText.NeutralizeDelimiters(string.Join("\n", blocks.Select(Line)));
            if (TextElements.Count(transcript) <= options.MaxTranscriptCharacters) return $"<transcript>\n{transcript}\n</transcript>";
            if (hitBlocks.Count > 0)
            {
                return $"<transcript_excerpts>\n{Excerpts(options.MaxTranscriptCharacters)}\n</transcript_excerpts>";
            }
            return $"<transcript>\n{TextElements.Prefix(transcript, options.MaxTranscriptCharacters)}\n{Prompts.Text("ask.omitted")}\n</transcript>";
        }

        // 設計判断: DEC-MTG-054
        /// <summary>答えの中の「M2:」「M2：」を拾い、引用された会議を出てきた順に返す</summary>
        public static IReadOnlyList<AskSource> Cited(string text, IReadOnlyList<AskSource> sources)
        {
            var result = new List<AskSource>();
            foreach (Match match in CitationPattern().Matches(text))
            {
                if (!int.TryParse(match.Groups[1].Value, NumberStyles.None, CultureInfo.InvariantCulture, out var n)) continue;
                if (sources.FirstOrDefault(s => s.Number == n) is { } source && !result.Contains(source)) result.Add(source);
            }
            return result;
        }

        /// <summary>検索に使わない語（質問の言い回しや、期間で扱う語）。Mac 版と同じ</summary>
        private static readonly HashSet<string> StopWords = new(StringComparer.Ordinal)
        {
            "会議", "ミーティング", "mtg", "打ち合わせ", "打合せ", "内容", "何", "なに", "誰", "だれ", "いつ", "どこ", "どう",  // skip-tr（言語の決まりに使う語。FUT-014）
            "今日", "本日", "昨日", "一昨日", "明日", "今週", "先週", "先々週", "来週", "今月", "先月", "来月", "前回", "最近", "直近",  // skip-tr（言語の決まりに使う語。FUT-014）
            "教え", "決定", "話", "件", "こと", "もの", "ため", "とき", "について",  // skip-tr（言語の決まりに使う語。FUT-014）
        };

        private enum CharKind { Kanji, Katakana, Hiragana, Word, Other }

        private static CharKind KindOf(string element)
        {
            if (!System.Text.Rune.TryGetRuneAt(element, 0, out var rune)) return CharKind.Other;
            var v = rune.Value;
            if (v is >= 0x3040 and <= 0x309F) return CharKind.Hiragana;
            if (v is >= 0x30A0 and <= 0x30FF or >= 0x31F0 and <= 0x31FF) return CharKind.Katakana;
            if (v is >= 0x4E00 and <= 0x9FFF or >= 0x3400 and <= 0x4DBF or >= 0xF900 and <= 0xFAFF or >= 0x20000 and <= 0x3FFFF
                or 0x3005 or 0x3006 or 0x30F6) return CharKind.Kanji;
            return System.Text.Rune.IsLetterOrDigit(rune) ? CharKind.Word : CharKind.Other;
        }

        // 設計判断: DEC-MTG-052, DEC-MTG-154
        /// <summary>
        /// 質問から検索語を取り出す。文字の種類（漢字・カタカナ・ひらがな・英数字）の切れ目で語に分け、
        /// ひらがなを含む語・1 文字の語・言い回しの語は除き、続いて出てくる語はつなげた複合語（「料金」「プラン」→「料金プラン」）も加える
        /// </summary>
        public static IReadOnlyList<string> Keywords(string question)
        {
            var text = MeetingSearch.Fold(question);
            var tokens = new List<(string Token, int Start, int End)>();
            var elements = new List<string>();
            var enumerator = StringInfo.GetTextElementEnumerator(text);
            while (enumerator.MoveNext()) elements.Add(enumerator.GetTextElement());
            for (var i = 0; i < elements.Count;)
            {
                var kind = KindOf(elements[i]);
                if (kind == CharKind.Other)
                {
                    i++;
                    continue;
                }
                var start = i;
                while (i < elements.Count && KindOf(elements[i]) == kind) i++;
                tokens.Add((string.Concat(elements.Skip(start).Take(i - start)), start, i));
            }
            var keywords = new List<string>();
            var run = new List<string>();
            int? lastEnd = null;
            void FlushRun()
            {
                if (run.Count >= 2)
                {
                    var compound = string.Concat(run);
                    if (!keywords.Contains(compound)) keywords.Insert(0, compound);
                }
                run.Clear();
            }
            foreach (var (token, start, end) in tokens)
            {
                var useful = TextElements.Count(token) >= 2 && !StopWords.Contains(token) && !token.Any(c => c is >= '぀' and <= 'ゟ');
                if (useful)
                {
                    if (lastEnd != start) FlushRun();
                    run.Add(token);
                    if (!keywords.Contains(token)) keywords.Add(token);
                }
                else
                {
                    FlushRun();
                }
                lastEnd = end;
            }
            FlushRun();
            return keywords;
        }

        // 設計判断: DEC-MTG-052
        /// <summary>質問の中の「今日」「昨日」「先週」「先月」「11月2日」「11/2」などから期間を決める。週は月曜始まり</summary>
        public static AskInterval? PeriodIn(string question, DateTimeOffset now, TimeZoneInfo zone)
        {
            var text = MeetingSearch.Fold(question);
            var local = TimeZoneInfo.ConvertTime(now, zone);
            var today = local.Date;
            DateTimeOffset At(DateTime day) => CommandPeriod.StartOfDay(day, zone);
            AskInterval Days(int offset, int length = 1) => new(At(today.AddDays(offset)), At(today.AddDays(offset + length)));
            AskInterval Week(int offset)
            {
                var monday = today.AddDays(-(((int)today.DayOfWeek + 6) % 7)).AddDays(7 * offset);
                return new(At(monday), At(monday.AddDays(7)));
            }
            AskInterval Month(int offset)
            {
                var first = new DateTime(today.Year, today.Month, 1).AddMonths(offset);
                return new(At(first), At(first.AddMonths(1)));
            }

            // 「11月2日」「11/2」
            var match = DayPattern().Match(text);
            if (match.Success
                && int.TryParse(match.Groups[1].Value, NumberStyles.None, CultureInfo.InvariantCulture, out var m)
                && int.TryParse(match.Groups[2].Value, NumberStyles.None, CultureInfo.InvariantCulture, out var d)
                && m is >= 1 and <= 12 && d >= 1 && d <= DateTime.DaysInMonth(today.Year, m))
            {
                var date = new DateTime(today.Year, m, d);
                // 未来の日付なら去年のこと
                if (At(date) > now && d <= DateTime.DaysInMonth(today.Year - 1, m)) date = new DateTime(today.Year - 1, m, d);
                return new AskInterval(At(date), At(date.AddDays(1)));
            }
            if (text.Contains("一昨日") || text.Contains("おととい")) return Days(-2);  // skip-tr（言語の決まりに使う語）
            if (text.Contains("昨日") || text.Contains("きのう")) return Days(-1);  // skip-tr（言語の決まりに使う語）
            if (text.Contains("今日") || text.Contains("本日") || text.Contains("きょう")) return Days(0);  // skip-tr（言語の決まりに使う語）
            if (text.Contains("先々週")) return Week(-2);  // skip-tr（言語の決まりに使う語）
            if (text.Contains("先週")) return Week(-1);  // skip-tr（言語の決まりに使う語）
            if (text.Contains("今週")) return Week(0);  // skip-tr（言語の決まりに使う語）
            if (text.Contains("先月")) return Month(-1);  // skip-tr（言語の決まりに使う語）
            if (text.Contains("今月")) return Month(0);  // skip-tr（言語の決まりに使う語）
            return null;
        }

        [GeneratedRegex(@"M(\d+)\s*[:：]")]
        private static partial Regex CitationPattern();

        [GeneratedRegex(@"(\d{1,2})\s*(?:月|/)\s*(\d{1,2})日?")]  // skip-tr（言語の決まりに使う語）
        private static partial Regex DayPattern();
    }
}
