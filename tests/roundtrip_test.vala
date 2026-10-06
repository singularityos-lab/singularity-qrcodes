using Singularity;
using Singularity.Apps.QrCodes;

string tmpdir;

uint8[] rasterize (QrCode qr, int scale, out int side) {
    side = (qr.size + Render.QUIET * 2) * scale;
    var gray = new uint8[side * side];
    for (int i = 0; i < gray.length; i++) gray[i] = 255;
    for (int y = 0; y < qr.size; y++) {
        for (int x = 0; x < qr.size; x++) {
            if (!qr.get_module (x, y)) continue;
            for (int dy = 0; dy < scale; dy++) {
                for (int dx = 0; dx < scale; dx++) {
                    gray[((y + Render.QUIET) * scale + dy) * side + (x + Render.QUIET) * scale + dx] = 0;
                }
            }
        }
    }
    return gray;
}

string decode (QrCode qr) {
    int side;
    var gray = rasterize (qr, qr.version > 20 ? 3 : 4, out side);
    var found = Scan.decode_gray (gray, side, side);
    if (found.length != 1) return "";
    assert (found[0].format == CodeFormat.QR);
    return found[0].text;
}

string text_of (int n, int seed) {
    const string ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,:;/?=&-_";
    var sb = new StringBuilder ();
    for (int i = 0; i < n; i++) sb.append_c (ALPHABET[(i * 7 + seed * 13) % ALPHABET.length]);
    return sb.str;
}

Decoded[] scan_barcode (Barcode b, int module) {
    try {
        var bytes = Render.barcode_png_bytes (b, module);
        var pixbuf = new Gdk.Pixbuf.from_stream (new MemoryInputStream.from_data (bytes));
        return Scan.decode_pixbuf (pixbuf);
    } catch (Error e) {
        error ("%s", e.message);
    }
}

void check_barcode (CodeFormat f, string text, string want) {
    check_read_as (f, text, f, want);
}

void check_read_as (CodeFormat f, string text, CodeFormat read, string want) {
    try {
        var b = Barcode.encode (f, text);
        foreach (int module in new int[] { 2, 3 }) {
            var found = scan_barcode (b, module);
            if (found.length != 1) error ("%s %s: %d results at module %d", f.id (), text, found.length, module);
            if (found[0].format != read) error ("%s %s: read as %s", f.id (), text, found[0].format.id ());
            if (found[0].text != want) error ("%s %s: read as %s", f.id (), text, found[0].text);
        }
    } catch (EncodeError e) {
        error ("%s", e.message);
    }
}

void main (string[] args) {
    Test.init (ref args);
    tmpdir = args.length > 1 ? args[1] : Environment.get_tmp_dir ();

    Test.add_func ("/roundtrip/all-versions-and-levels", () => {
        foreach (var level in QrEcLevel.all ()) {
            for (int v = 1; v <= 40; v++) {
                string text = text_of (QrCode.max_bytes (v, level), v);
                try {
                    var qr = QrCode.encode_text (text, level);
                    assert (qr.version == v);
                    string got = decode (qr);
                    if (got != text) error ("version %d level %s did not decode", v, level.id ());
                } catch (QrEncodeError e) {
                    error ("%s", e.message);
                }
            }
        }
    });

    Test.add_func ("/roundtrip/every-mask", () => {
        for (int m = 0; m < 8; m++) {
            try {
                var qr = QrCode.encode_text ("https://example.org/mask/%d".printf (m), QrEcLevel.QUARTILE, m);
                assert (qr.mask == m);
                assert (decode (qr) == "https://example.org/mask/%d".printf (m));
            } catch (QrEncodeError e) {
                error ("%s", e.message);
            }
        }
    });

    Test.add_func ("/roundtrip/utf8-and-payloads", () => {
        var wifi = new WifiInfo ();
        wifi.ssid = "Caffè; \"Wi,Fi\": \\ ☕";
        wifi.security = "WPA";
        wifi.password = "p;a:s,s\\";
        string[] texts = { "Caffè ☕ Ünïcödé 日本語", Payload.wifi (wifi), "BEGIN:VCARD\nVERSION:3.0\nFN:Ada Lovelace\nEND:VCARD" };
        foreach (string t in texts) {
            try {
                var qr = QrCode.encode_text (t, QrEcLevel.MEDIUM);
                assert (decode (qr) == t);
            } catch (QrEncodeError e) {
                error ("%s", e.message);
            }
        }
        try {
            var qr = QrCode.encode_text (Payload.wifi (wifi), QrEcLevel.HIGH);
            var c = Content.parse (decode (qr));
            assert (c.kind == ContentKind.WIFI);
            assert (c.wifi.ssid == wifi.ssid);
            assert (c.wifi.password == wifi.password);
        } catch (QrEncodeError e) {
            error ("%s", e.message);
        }
    });

    Test.add_func ("/roundtrip/png-file", () => {
        try {
            var qr = QrCode.encode_text ("otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP", QrEcLevel.MEDIUM);
            string path = Path.build_filename (tmpdir, "qrcodes-roundtrip.png");
            Render.save_png (qr, 6, path);
            var found = Scan.decode_file (path);
            FileUtils.remove (path);
            assert (found.length == 1);
            assert (found[0].text == "otpauth://totp/Example:alice?secret=JBSWY3DPEHPK3PXP");
        } catch (Error e) {
            error ("%s", e.message);
        }
    });

    Test.add_func ("/roundtrip/png-bytes", () => {
        try {
            var qr = QrCode.encode_text ("geo:45.4642,9.19", QrEcLevel.LOW);
            var bytes = Render.png_bytes (qr, 5);
            var pixbuf = new Gdk.Pixbuf.from_stream (new MemoryInputStream.from_data (bytes));
            var found = Scan.decode_pixbuf (pixbuf);
            assert (found.length == 1 && found[0].text == "geo:45.4642,9.19");
        } catch (Error e) {
            error ("%s", e.message);
        }
    });

    Test.add_func ("/roundtrip/svg-file", () => {
        bool svg_loader = false;
        foreach (var f in Gdk.Pixbuf.get_formats ()) if (f.get_name () == "svg") svg_loader = true;
        if (!svg_loader) {
            Test.skip ("no SVG loader for gdk-pixbuf");
            return;
        }
        try {
            var qr = QrCode.encode_text ("https://singularity.example/svg", QrEcLevel.HIGH);
            string path = Path.build_filename (tmpdir, "qrcodes-roundtrip.svg");
            FileUtils.set_contents (path, Render.svg (qr, 6));
            var found = Scan.decode_file (path);
            FileUtils.remove (path);
            assert (found.length == 1 && found[0].text == "https://singularity.example/svg");
        } catch (Error e) {
            error ("%s", e.message);
        }
    });

    Test.add_func ("/roundtrip/inverted", () => {
        try {
            var qr = QrCode.encode_text ("inverted colours", QrEcLevel.MEDIUM);
            int side;
            var gray = rasterize (qr, 4, out side);
            for (int i = 0; i < gray.length; i++) gray[i] = 255 - gray[i];
            var found = Scan.decode_gray (gray, side, side);
            assert (found.length == 1 && found[0].text == "inverted colours");
        } catch (QrEncodeError e) {
            error ("%s", e.message);
        }
    });

    Test.add_func ("/roundtrip/nothing", () => {
        var gray = new uint8[200 * 200];
        for (int i = 0; i < gray.length; i++) gray[i] = (uint8) (i % 251);
        assert (Scan.decode_gray (gray, 200, 200).length == 0);
    });

    Test.add_func ("/roundtrip/ean-upc", () => {
        check_barcode (CodeFormat.EAN13, "4006381333931", "4006381333931");
        check_barcode (CodeFormat.EAN13, "590123412345", "5901234123457");
        check_barcode (CodeFormat.EAN13, "9780306406157", "9780306406157");
        check_barcode (CodeFormat.EAN8, "96385074", "96385074");
        check_barcode (CodeFormat.EAN8, "5512345", "55123457");
        check_barcode (CodeFormat.UPCA, "036000291452", "036000291452");
        check_barcode (CodeFormat.UPCA, "72527273070", "725272730706");
        for (int first = 0; first <= 9; first++) {
            string payload = "%d%011d".printf (first, 123456789 + first * 7919);
            string full = payload + Gtin.check_digit (payload).to_string ();
            if (first == 0) check_read_as (CodeFormat.EAN13, payload, CodeFormat.UPCA, full.substring (1));
            else check_barcode (CodeFormat.EAN13, payload, full);
        }
    });

    Test.add_func ("/roundtrip/code128", () => {
        var all_b = new StringBuilder ();
        for (int c = 32; c < 127; c++) all_b.append_c ((char) c);
        string printable = all_b.str;
        for (int i = 0; i < printable.length; i += 40) {
            string part = printable.substring (i, int.min (40, printable.length - i));
            check_barcode (CodeFormat.CODE128, part, part);
        }
        var all_c = new StringBuilder ();
        for (int v = 0; v < 100; v += 2) all_c.append ("%02d".printf (v));
        check_barcode (CodeFormat.CODE128, all_c.str.substring (0, 60), all_c.str.substring (0, 60));
        check_barcode (CodeFormat.CODE128, all_c.str.substring (60, 40), all_c.str.substring (60, 40));
        check_barcode (CodeFormat.CODE128, "12", "12");
        check_barcode (CodeFormat.CODE128, "12345", "12345");
        check_barcode (CodeFormat.CODE128, "AB123456cd", "AB123456cd");
        check_barcode (CodeFormat.CODE128, "123456x", "123456x");
        check_barcode (CodeFormat.CODE128, "LOT\t42\x01end", "LOT\t42\x01end");
        check_barcode (CodeFormat.CODE128, "https://example.org/a?b=1", "https://example.org/a?b=1");
    });

    Test.add_func ("/roundtrip/barcode-files", () => {
        try {
            var b = Barcode.encode (CodeFormat.EAN13, "4006381333931");
            string png = Path.build_filename (tmpdir, "qrcodes-roundtrip-ean.png");
            Render.save_barcode_png (b, 3, png);
            var found = Scan.decode_file (png);
            FileUtils.remove (png);
            assert (found.length == 1 && found[0].format == CodeFormat.EAN13 && found[0].text == "4006381333931");
            bool svg_loader = false;
            foreach (var f in Gdk.Pixbuf.get_formats ()) if (f.get_name () == "svg") svg_loader = true;
            if (!svg_loader) return;
            var c = Barcode.encode (CodeFormat.CODE128, "SVG-128 ok");
            string svg = Path.build_filename (tmpdir, "qrcodes-roundtrip-128.svg");
            FileUtils.set_contents (svg, Render.barcode_svg (c, 3));
            found = Scan.decode_file (svg);
            FileUtils.remove (svg);
            assert (found.length == 1 && found[0].format == CodeFormat.CODE128 && found[0].text == "SVG-128 ok");
        } catch (Error e) {
            error ("%s", e.message);
        }
    });

    Test.add_func ("/roundtrip/several-codes", () => {
        try {
            var q1 = QrCode.encode_text ("https://example.org/one", QrEcLevel.MEDIUM);
            var q2 = QrCode.encode_text ("WIFI:T:WPA;S:Two;P:secret;;", QrEcLevel.MEDIUM);
            var bar = Barcode.encode (CodeFormat.EAN13, "4006381333931");
            var s = new Cairo.ImageSurface (Cairo.Format.RGB24, 900, 520);
            var cr = new Cairo.Context (s);
            cr.set_source_rgb (1, 1, 1);
            cr.paint ();
            Render.draw (cr, q1, 20, 20, 6);
            Render.draw (cr, q2, 460, 20, 6);
            Render.draw_barcode (cr, bar, 200, 300, 3);
            s.flush ();
            string path = Path.build_filename (tmpdir, "qrcodes-roundtrip-several.png");
            s.write_to_png (path);
            var found = Scan.decode_file (path);
            FileUtils.remove (path);
            assert (found.length == 3);
            var texts = new Gee.HashSet<string> ();
            foreach (var d in found) texts.add (d.format.id () + " " + d.text);
            assert ("qr https://example.org/one" in texts);
            assert ("qr WIFI:T:WPA;S:Two;P:secret;;" in texts);
            assert ("ean13 4006381333931" in texts);
        } catch (Error e) {
            error ("%s", e.message);
        }
    });

    Test.add_func ("/roundtrip/batch-csv", () => {
        try {
            var groups = new Gee.ArrayList<ScanGroup> ();
            string[] names = { "a.png", "b.png", "c.png" };
            for (int i = 0; i < names.length; i++) {
                string path = Path.build_filename (tmpdir, "qrcodes-batch-" + names[i]);
                if (i == 0) Render.save_png (QrCode.encode_text ("first", QrEcLevel.LOW), 5, path);
                else if (i == 1) Render.save_barcode_png (Barcode.encode (CodeFormat.EAN8, "96385074"), 3, path);
                else FileUtils.set_contents (path, "not a picture");
                var g = new ScanGroup (names[i]);
                try {
                    foreach (var d in Scan.decode_file (path)) g.codes.add (d);
                } catch (Error e) {
                    g.error = "unreadable";
                }
                groups.add (g);
                FileUtils.remove (path);
            }
            string doc = Csv.document (groups);
            assert (doc == "File,Format,Type,Content\r\na.png,QR Code,Text,first\r\nb.png,EAN-8,Product Code,96385074\r\nc.png,,unreadable,\r\n");
        } catch (Error e) {
            error ("%s", e.message);
        }
    });

    Test.run ();
}
