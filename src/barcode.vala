namespace Singularity.Apps.QrCodes {

    public errordomain EncodeError {
        TOO_LONG,
        INVALID
    }

    public class TextRun : Object {
        public string text { get; construct; }
        public int start { get; construct; }
        public int end { get; construct; }

        public TextRun (string text, int start, int end) {
            Object (text: text, start: start, end: end);
        }
    }

    public class Barcode : Object {
        private const string[] L_CODES = {
            "0001101", "0011001", "0010011", "0111101", "0100011",
            "0110001", "0101111", "0111011", "0110111", "0001011"
        };
        private const string[] EAN13_PARITY = {
            "LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG",
            "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"
        };
        public const string[] CODE128_WIDTHS = {
            "212222", "222122", "222221", "121223", "121322", "131222", "122213", "122312", "132212", "221213",
            "221312", "231212", "112232", "122132", "122231", "113222", "123122", "123221", "223211", "221132",
            "221231", "213212", "223112", "312131", "311222", "321122", "321221", "312212", "322112", "322211",
            "212123", "212321", "232121", "111323", "131123", "131321", "112313", "132113", "132311", "211313",
            "231113", "231311", "112133", "112331", "132131", "113123", "113321", "133121", "313121", "211331",
            "231131", "213113", "213311", "213131", "311123", "311321", "331121", "312113", "312311", "332111",
            "314111", "221411", "431111", "111224", "111422", "121124", "121421", "141122", "141221", "112214",
            "112412", "122114", "122411", "142112", "142211", "241211", "221114", "413111", "241112", "134111",
            "111242", "121142", "121241", "114212", "124112", "124211", "411212", "421112", "421211", "212141",
            "214121", "412121", "111143", "111341", "131141", "114113", "114311", "411113", "411311", "113141",
            "114131", "311141", "411131", "211412", "211214", "211232", "2331112"
        };
        public const int START_A = 103;
        public const int START_B = 104;
        public const int START_C = 105;
        public const int STOP = 106;
        private const int CODE_C = 99;
        private const int CODE_B_FROM_A = 100;
        private const int CODE_A_FROM_B = 101;
        private const int CODE_B_FROM_C = 100;
        private const int CODE_A_FROM_C = 101;
        public const int MAX_CODE128 = 80;

        public CodeFormat format { get; private set; }
        public string text { get; private set; }
        private bool[] bars = {};
        private bool[] guards = {};
        public int quiet_left { get; private set; }
        public int quiet_right { get; private set; }
        public int bar_height { get; private set; }
        private int[] values = {};
        public Gee.ArrayList<TextRun> runs = new Gee.ArrayList<TextRun> ();

        public int width {
            get { return bars.length; }
        }

        public int total_width {
            get { return quiet_left + bars.length + quiet_right; }
        }

        private Barcode (CodeFormat format, string text) {
            this.format = format;
            this.text = text;
        }

        public bool get_bar (int x) {
            return x >= 0 && x < bars.length && bars[x];
        }

        public bool is_guard (int x) {
            return x >= 0 && x < guards.length && guards[x];
        }

        public static string l_code (int digit) {
            return L_CODES[digit];
        }

        public static string r_code (int digit) {
            var sb = new StringBuilder ();
            foreach (char c in L_CODES[digit].to_utf8 ()) sb.append_c (c == '0' ? '1' : '0');
            return sb.str;
        }

        public static string g_code (int digit) {
            return r_code (digit).reverse ();
        }

        public static string complete (CodeFormat format, string input) throws EncodeError {
            string code = input.strip ().replace (" ", "").replace ("-", "");
            int n = format.digits ();
            if (!Gtin.all_digits (code)) throw new EncodeError.INVALID (_("%s codes hold only digits.").printf (format.label ()));
            if (code.length == n - 1) return code + Gtin.check_digit (code).to_string ();
            if (code.length != n) {
                throw new EncodeError.INVALID (_("%s codes have %d digits, or %d without the check digit.").printf (format.label (), n, n - 1));
            }
            int want = Gtin.check_digit (code.substring (0, n - 1));
            if (code[n - 1] - '0' != want) {
                throw new EncodeError.INVALID (_("The check digit does not match: the last digit should be %d.").printf (want));
            }
            return code;
        }

        public static Barcode encode (CodeFormat format, string input) throws EncodeError {
            switch (format) {
                case CodeFormat.EAN13: return ean13 (complete (format, input), false);
                case CodeFormat.UPCA: return ean13 ("0" + complete (format, input), true);
                case CodeFormat.EAN8: return ean8 (complete (format, input));
                case CodeFormat.CODE128: return code128 (input);
                default: throw new EncodeError.INVALID (_("This is not a barcode format."));
            }
        }

        private void put (string pattern, bool guard) {
            foreach (char c in pattern.to_utf8 ()) {
                bars += c == '1';
                guards += guard;
            }
        }

        private static Barcode ean13 (string code, bool upc) {
            var b = new Barcode (upc ? CodeFormat.UPCA : CodeFormat.EAN13, upc ? code.substring (1) : code);
            int first = code[0] - '0';
            string parity = EAN13_PARITY[first];
            b.put ("101", true);
            for (int i = 1; i <= 6; i++) {
                int d = code[i] - '0';
                b.put (parity[i - 1] == 'L' ? l_code (d) : g_code (d), upc && i == 1);
            }
            b.put ("01010", true);
            for (int i = 7; i <= 12; i++) b.put (r_code (code[i] - '0'), upc && i == 12);
            b.put ("101", true);
            b.bar_height = 64;
            if (upc) {
                b.quiet_left = 9;
                b.quiet_right = 9;
                b.runs.add (new TextRun (code.substring (1, 1), -8, -1));
                b.runs.add (new TextRun (code.substring (2, 5), 10, 45));
                b.runs.add (new TextRun (code.substring (7, 5), 50, 85));
                b.runs.add (new TextRun (code.substring (12, 1), 96, 103));
            } else {
                b.quiet_left = 11;
                b.quiet_right = 7;
                b.runs.add (new TextRun (code.substring (0, 1), -9, -2));
                b.runs.add (new TextRun (code.substring (1, 6), 3, 45));
                b.runs.add (new TextRun (code.substring (7, 6), 50, 92));
            }
            return b;
        }

        private static Barcode ean8 (string code) {
            var b = new Barcode (CodeFormat.EAN8, code);
            b.put ("101", true);
            for (int i = 0; i < 4; i++) b.put (l_code (code[i] - '0'), false);
            b.put ("01010", true);
            for (int i = 4; i < 8; i++) b.put (r_code (code[i] - '0'), false);
            b.put ("101", true);
            b.bar_height = 52;
            b.quiet_left = 7;
            b.quiet_right = 7;
            b.runs.add (new TextRun (code.substring (0, 4), 3, 31));
            b.runs.add (new TextRun (code.substring (4, 4), 36, 64));
            return b;
        }

        private static int digit_run (uint8[] data, int from) {
            int n = 0;
            while (from + n < data.length && data[from + n] >= '0' && data[from + n] <= '9') n++;
            return n;
        }

        private static char needed_set (uint8[] data, int from) {
            for (int i = from; i < data.length; i++) {
                if (data[i] < 32) return 'A';
                if (data[i] >= 96) return 'B';
            }
            return 'B';
        }

        private static int value_in (char set, uint8 ch) {
            if (set == 'A') return ch < 32 ? ch + 64 : ch - 32;
            return ch - 32;
        }

        public static int[] code128_values (string input) throws EncodeError {
            uint8[] data = input.data;
            if (data.length == 0) throw new EncodeError.INVALID (_("Type the text for the barcode."));
            if (data.length > MAX_CODE128) {
                throw new EncodeError.TOO_LONG (_("This is too long for a Code 128 barcode: %d characters, the limit is %d.").printf (data.length, MAX_CODE128));
            }
            foreach (uint8 ch in data) {
                if (ch > 127) throw new EncodeError.INVALID (_("Code 128 holds only basic Latin letters, digits and symbols."));
            }
            int[] values = {};
            char set = 0;
            int i = 0;
            while (i < data.length) {
                int run = digit_run (data, i);
                bool to_c;
                if (set == 0) to_c = run >= 4 || (run == 2 && data.length == 2);
                else if (set == 'C') to_c = run >= 2;
                else to_c = run >= 6 || (run >= 4 && i + run == data.length);
                if (to_c && run % 2 == 1 && set != 'C') {
                    if (set == 0) {
                        set = needed_set (data, i);
                        values += set == 'A' ? START_A : START_B;
                    }
                    values += value_in (set, data[i]);
                    i++;
                    continue;
                }
                if (to_c) {
                    if (set == 0) values += START_C;
                    else if (set != 'C') values += CODE_C;
                    set = 'C';
                    while (digit_run (data, i) >= 2) {
                        values += (data[i] - '0') * 10 + (data[i + 1] - '0');
                        i += 2;
                    }
                    continue;
                }
                uint8 ch = data[i];
                char want = ch < 32 ? 'A' : (ch >= 96 ? 'B' : (set == 'A' || set == 'B' ? set : needed_set (data, i)));
                if (set != want) {
                    if (set == 0) values += want == 'A' ? START_A : START_B;
                    else if (set == 'C') values += want == 'A' ? CODE_A_FROM_C : CODE_B_FROM_C;
                    else values += want == 'A' ? CODE_A_FROM_B : CODE_B_FROM_A;
                    set = want;
                }
                values += value_in (set, ch);
                i++;
            }
            int sum = values[0];
            for (int k = 1; k < values.length; k++) sum += k * values[k];
            values += sum % 103;
            values += STOP;
            return values;
        }

        private static Barcode code128 (string input) throws EncodeError {
            var b = new Barcode (CodeFormat.CODE128, input);
            b.values = code128_values (input);
            foreach (int v in b.values) {
                string widths = CODE128_WIDTHS[v];
                bool bar = true;
                foreach (char w in widths.to_utf8 ()) {
                    for (int k = 0; k < w - '0'; k++) {
                        b.bars += bar;
                        b.guards += false;
                    }
                    bar = !bar;
                }
            }
            b.bar_height = int.max (40, b.bars.length / 5);
            b.quiet_left = 10;
            b.quiet_right = 10;
            var shown = new StringBuilder ();
            foreach (uint8 ch in input.data) shown.append_c (ch < 32 || ch == 127 ? ' ' : (char) ch);
            b.runs.add (new TextRun (shown.str.strip (), 0, b.bars.length));
            return b;
        }

        public string pattern () {
            var sb = new StringBuilder ();
            foreach (bool x in bars) sb.append_c (x ? '1' : '0');
            return sb.str;
        }
    }
}
