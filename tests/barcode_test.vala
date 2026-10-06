using Singularity.Apps.QrCodes;

string bits (string groups) {
    return groups.replace (" ", "");
}

string widths_to_bits (string[] symbols) {
    var sb = new StringBuilder ();
    foreach (string w in symbols) {
        bool bar = true;
        foreach (char c in w.to_utf8 ()) {
            for (int i = 0; i < c - '0'; i++) sb.append_c (bar ? '1' : '0');
            bar = !bar;
        }
    }
    return sb.str;
}

Barcode make (CodeFormat f, string text) {
    try {
        return Barcode.encode (f, text);
    } catch (EncodeError e) {
        error ("%s: %s", text, e.message);
    }
}

void expect_invalid (CodeFormat f, string text) {
    try {
        Barcode.encode (f, text);
        error ("%s should be rejected", text);
    } catch (EncodeError e) {
    }
}

void main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/barcode/check-digits", () => {
        assert (Gtin.check_digit ("400638133393") == 1);
        assert (Gtin.check_digit ("590123412345") == 7);
        assert (Gtin.check_digit ("03600029145") == 2);
        assert (Gtin.check_digit ("9638507") == 4);
        assert (Gtin.check_digit ("978030640615") == 7);
        assert (Gtin.valid ("4006381333931"));
        assert (!Gtin.valid ("4006381333932"));
        assert (!Gtin.valid ("40063813339a1"));
        assert (Gtin.is_isbn ("9780306406157"));
        assert (!Gtin.is_isbn ("4006381333931"));
    });

    Test.add_func ("/barcode/complete", () => {
        try {
            assert (Barcode.complete (CodeFormat.EAN13, "400638133393") == "4006381333931");
            assert (Barcode.complete (CodeFormat.EAN13, "4006381333931") == "4006381333931");
            assert (Barcode.complete (CodeFormat.EAN13, " 400-638 133393 ") == "4006381333931");
            assert (Barcode.complete (CodeFormat.EAN8, "9638507") == "96385074");
            assert (Barcode.complete (CodeFormat.UPCA, "03600029145") == "036000291452");
        } catch (EncodeError e) {
            error ("%s", e.message);
        }
        expect_invalid (CodeFormat.EAN13, "4006381333932");
        expect_invalid (CodeFormat.EAN13, "40063813");
        expect_invalid (CodeFormat.EAN13, "4006381333a31");
        expect_invalid (CodeFormat.EAN8, "963850745");
        expect_invalid (CodeFormat.UPCA, "0360002914");
        expect_invalid (CodeFormat.QR, "1234");
    });

    Test.add_func ("/barcode/ean13-reference", () => {
        var b = make (CodeFormat.EAN13, "5901234123457");
        string want = bits ("101 0001011 0100111 0110011 0010011 0111101 0011101 01010 1100110 1101100 1000010 1011100 1001110 1000100 101");
        assert (b.pattern () == want);
        assert (b.width == 95);
        assert (b.quiet_left == 11 && b.quiet_right == 7);
        assert (b.is_guard (0) && b.is_guard (46) && b.is_guard (94) && !b.is_guard (3));
        assert (b.runs.size == 3 && b.runs[0].text == "5" && b.runs[1].text == "901234" && b.runs[2].text == "123457");
    });

    Test.add_func ("/barcode/ean8-reference", () => {
        var b = make (CodeFormat.EAN8, "96385074");
        string want = bits ("101 0001011 0101111 0111101 0110111 01010 1001110 1110010 1000100 1011100 101");
        assert (b.pattern () == want);
        assert (b.width == 67);
        assert (b.text == "96385074");
    });

    Test.add_func ("/barcode/upca-reference", () => {
        var b = make (CodeFormat.UPCA, "036000291452");
        string want = bits ("101 0001101 0111101 0101111 0001101 0001101 0001101 01010 1101100 1110100 1100110 1011100 1001110 1101100 101");
        assert (b.pattern () == want);
        assert (b.text == "036000291452");
        assert (b.format == CodeFormat.UPCA);
        assert (b.is_guard (3) && b.is_guard (91) && !b.is_guard (10));
        assert (b.runs.size == 4 && b.runs[0].text == "0" && b.runs[3].text == "2");
    });

    Test.add_func ("/barcode/code128-widths", () => {
        assert (Barcode.CODE128_WIDTHS.length == 107);
        for (int i = 0; i < Barcode.CODE128_WIDTHS.length; i++) {
            int sum = 0;
            foreach (char c in Barcode.CODE128_WIDTHS[i].to_utf8 ()) sum += c - '0';
            assert (sum == (i == Barcode.STOP ? 13 : 11));
        }
        var seen = new Gee.HashSet<string> ();
        foreach (string w in Barcode.CODE128_WIDTHS) assert (seen.add (w));
    });

    Test.add_func ("/barcode/code128-reference", () => {
        var b = make (CodeFormat.CODE128, "12");
        assert (b.pattern () == widths_to_bits ({ "211232", "112232", "122231", "2331112" }));
        assert (b.width == 11 * 3 + 13);
    });

    Test.add_func ("/barcode/code128-sets", () => {
        try {
            int[] v = Barcode.code128_values ("1234");
            int[] want = { Barcode.START_C, 12, 34, (105 + 12 + 2 * 34) % 103, Barcode.STOP };
            assert (v.length == want.length);
            for (int i = 0; i < v.length; i++) assert (v[i] == want[i]);

            v = Barcode.code128_values ("Wikipedia");
            int[] wiki = { Barcode.START_B, 55, 73, 75, 73, 80, 69, 68, 73, 65 };
            for (int i = 0; i < wiki.length; i++) assert (v[i] == wiki[i]);
            int sum = 104;
            for (int i = 1; i < wiki.length; i++) sum += i * wiki[i];
            assert (v[wiki.length] == sum % 103);
            assert (v.length == wiki.length + 2);

            v = Barcode.code128_values ("AB123456");
            int[] mixed = { Barcode.START_B, 33, 34, 99, 12, 34, 56 };
            for (int i = 0; i < mixed.length; i++) assert (v[i] == mixed[i]);
            assert (v.length == mixed.length + 2);

            v = Barcode.code128_values ("12345");
            int[] odd = { Barcode.START_B, 17, 99, 23, 45 };
            for (int i = 0; i < odd.length; i++) assert (v[i] == odd[i]);

            v = Barcode.code128_values ("A\tB");
            int[] ctrl = { Barcode.START_A, 33, 73, 34 };
            for (int i = 0; i < ctrl.length; i++) assert (v[i] == ctrl[i]);

            v = Barcode.code128_values ("\tab");
            int[] ab = { Barcode.START_A, 73, 100, 65, 66 };
            for (int i = 0; i < ab.length; i++) assert (v[i] == ab[i]);

            v = Barcode.code128_values ("123456x");
            int[] cb = { Barcode.START_C, 12, 34, 56, 100, 88 };
            for (int i = 0; i < cb.length; i++) assert (v[i] == cb[i]);

            v = Barcode.code128_values ("123");
            assert (v[0] == Barcode.START_B && v.length == 6);
        } catch (EncodeError e) {
            error ("%s", e.message);
        }
        expect_invalid (CodeFormat.CODE128, "");
        expect_invalid (CodeFormat.CODE128, "Caffè");
        expect_invalid (CodeFormat.CODE128, string.nfill (Barcode.MAX_CODE128 + 1, 'x'));
    });

    Test.add_func ("/barcode/render", () => {
        var b = make (CodeFormat.EAN13, "4006381333931");
        var s = Render.barcode_surface (b, 3);
        assert (s.get_width () == b.total_width * 3);
        assert (s.get_height () == Render.barcode_height (b) * 3);
        unowned uint8[] data = s.get_data ();
        int stride = s.get_stride ();
        int y = (Render.BAR_MARGIN + 10) * 3;
        for (int x = 0; x < b.width; x++) {
            int px = (b.quiet_left + x) * 3 + 1;
            bool dark = data[y * stride + px * 4] < 128;
            assert (dark == b.get_bar (x));
        }
        string svg = Render.barcode_svg (b);
        assert (svg.has_prefix ("<?xml"));
        assert (svg.contains ("crispEdges"));
        assert (svg.contains (">006381<") && svg.contains (">333931<") && svg.contains (">4<"));
        var tricky = make (CodeFormat.CODE128, "a<b&c");
        assert (Render.barcode_svg (tricky).contains ("a&lt;b&amp;c"));
    });

    Test.run ();
}
