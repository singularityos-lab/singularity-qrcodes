using Singularity.Apps.QrCodes;

void main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/content/wifi-basic", () => {
        var c = Content.parse ("WIFI:T:WPA;S:HomeNet;P:secret123;;");
        assert (c.kind == ContentKind.WIFI);
        assert (c.wifi.ssid == "HomeNet");
        assert (c.wifi.security == "WPA");
        assert (c.wifi.password == "secret123");
        assert (!c.wifi.hidden);
        assert (c.title == "HomeNet");
        assert (c.field ("password") == "secret123");
        foreach (var f in c.fields) if (f.key == "password") assert (f.secret);
    });

    Test.add_func ("/content/wifi-escapes", () => {
        var c = Content.parse ("WIFI:S:My\\;Net\\,work\\:5G\\\\;T:WPA;P:pa\\;ss\\:wo\\,rd\\\\x;H:true;;");
        assert (c.kind == ContentKind.WIFI);
        assert (c.wifi.ssid == "My;Net,work:5G\\");
        assert (c.wifi.password == "pa;ss:wo,rd\\x");
        assert (c.wifi.hidden);
        var q = Content.parse ("WIFI:S:say \\\"hi\\\";T:nopass;;");
        assert (q.wifi.ssid == "say \"hi\"");
        assert (q.wifi.security == "nopass");
        assert (q.field ("password") == null);
    });

    Test.add_func ("/content/wifi-field-order-and-case", () => {
        var c = Content.parse ("wifi:p:abc;s:Cafe;t:wep;;");
        assert (c.kind == ContentKind.WIFI);
        assert (c.wifi.ssid == "Cafe");
        assert (c.wifi.security == "WEP");
        assert (c.wifi.password == "abc");
        var none = Content.parse ("WIFI:S:Open;;");
        assert (none.wifi.security == "nopass");
        var implied = Content.parse ("WIFI:S:Implied;P:hunter22;;");
        assert (implied.wifi.security == "WPA");
        var sae = Content.parse ("WIFI:T:SAE;S:New;P:x;;");
        assert (sae.wifi.security == "SAE");
        var trailing = Content.parse ("WIFI:S:ends\\\\;T:WPA;P:x;;");
        assert (trailing.wifi.ssid == "ends\\");
    });

    Test.add_func ("/content/wifi-without-ssid-is-text", () => {
        var c = Content.parse ("WIFI:T:WPA;P:x;;");
        assert (c.kind == ContentKind.TEXT);
    });

    Test.add_func ("/content/split-escaped", () => {
        var parts = Content.split_escaped ("a\\;b;c\\\\;d", ';');
        assert (parts.length == 3);
        assert (parts[0] == "a\\;b");
        assert (parts[1] == "c\\\\");
        assert (parts[2] == "d");
        assert (Content.unescape ("a\\;b\\,c\\:d\\\\e") == "a;b,c:d\\e");
    });

    Test.add_func ("/content/mecard", () => {
        var c = Content.parse ("MECARD:N:Lovelace,Ada;TEL:+441234567;EMAIL:ada@example.org;URL:https://ada.example;ADR:12 St James\\, London;NOTE:First programmer\\; mathematician;BDAY:18151210;;");
        assert (c.kind == ContentKind.CONTACT);
        assert (c.field ("name") == "Ada Lovelace");
        assert (c.title == "Ada Lovelace");
        assert (c.field ("phone") == "+441234567");
        assert (c.field ("email") == "ada@example.org");
        assert (c.field ("url") == "https://ada.example");
        assert (c.field ("address") == "12 St James, London");
        assert (c.field ("note") == "First programmer; mathematician");
        assert (c.field ("birthday") == "1815-12-10");
        var multi = Content.parse ("MECARD:N:Solo;TEL:1;TEL:2;;");
        assert (multi.field ("name") == "Solo");
        assert (multi.values ("phone").size == 2);
    });

    Test.add_func ("/content/vcard", () => {
        string card = "BEGIN:VCARD\r\nVERSION:3.0\r\nN:Hopper;Grace;Brewster;;\r\nFN:Grace Hopper\r\nORG:US Navy;Computing\r\nTITLE:Rear Admiral\r\nTEL;TYPE=CELL:+1 555 0100\r\nTEL;TYPE=WORK:+1 555 0199\r\nEMAIL;TYPE=INTERNET:grace@example.com\r\nADR;TYPE=HOME:;;1 Main St;Arlington;VA;22201;USA\r\nNOTE:Found the first\\, actual bug\\nin 1947\r\nURL:https://example.com/gra\r\n ce\r\nitem1.X-ABLABEL:ignored\r\nEND:VCARD\r\n";
        var c = Content.parse (card);
        assert (c.kind == ContentKind.CONTACT);
        assert (c.field ("name") == "Grace Hopper");
        assert (c.fields[0].key == "name");
        assert (c.field ("org") == "US Navy Computing");
        assert (c.field ("title") == "Rear Admiral");
        assert (c.values ("phone").size == 2);
        assert (c.values ("phone")[1] == "+1 555 0199");
        assert (c.field ("email") == "grace@example.com");
        assert (c.field ("address") == "1 Main St, Arlington, VA, 22201, USA");
        assert (c.field ("note") == "Found the first, actual bug\nin 1947");
        assert (c.field ("url") == "https://example.com/grace");
        var no_fn = Content.parse ("BEGIN:VCARD\nVERSION:2.1\nN:Turing;Alan\nEND:VCARD");
        assert (no_fn.field ("name") == "Alan Turing");
        assert (Content.is_vcard (" BEGIN:VCARD\nEND:VCARD"));
    });

    Test.add_func ("/content/urls", () => {
        var c = Content.parse ("https://www.example.org/path?q=1#frag");
        assert (c.kind == ContentKind.URL);
        assert (c.url == "https://www.example.org/path?q=1#frag");
        assert (c.title == "www.example.org");
        var bare = Content.parse ("www.example.com/x");
        assert (bare.kind == ContentKind.URL);
        assert (bare.url == "https://www.example.com/x");
        var up = Content.parse ("HTTP://EXAMPLE.COM");
        assert (up.kind == ContentKind.URL);
        assert (Content.parse ("http://localhost:8080/").kind == ContentKind.URL);
        assert (Content.parse ("https://nodot").kind == ContentKind.TEXT);
        assert (Content.parse ("see https://example.com now").kind == ContentKind.TEXT);
        assert (Content.parse ("javascript:alert(1)").kind == ContentKind.TEXT);
        assert (Content.parse ("  https://example.com  \n").kind == ContentKind.URL);
    });

    Test.add_func ("/content/geo", () => {
        var c = Content.parse ("geo:45.4642,9.19,120?q=Duomo%20di%20Milano");
        assert (c.kind == ContentKind.GEO);
        assert (c.field ("latitude") == "45.4642");
        assert (c.field ("longitude") == "9.19");
        assert (c.field ("altitude") != null);
        assert (c.field ("label") == "Duomo di Milano");
        assert (c.title == "Duomo di Milano");
        assert (c.url.has_prefix ("https://www.openstreetmap.org/?mlat=45.4642&mlon=9.19"));
        var neg = Content.parse ("GEO:-33.8568,151.2153;u=35");
        assert (neg.kind == ContentKind.GEO);
        assert (neg.title == "-33.8568, 151.2153");
        assert (Content.parse ("geo:95,10").kind == ContentKind.TEXT);
        assert (Content.parse ("geo:abc").kind == ContentKind.TEXT);
    });

    Test.add_func ("/content/mailto", () => {
        var c = Content.parse ("mailto:someone@example.com?subject=Hello%20there&body=Line+one&cc=boss@example.com");
        assert (c.kind == ContentKind.EMAIL);
        assert (c.field ("to") == "someone@example.com");
        assert (c.field ("subject") == "Hello there");
        assert (c.field ("body") == "Line one");
        assert (c.field ("cc") == "boss@example.com");
        assert (c.title == "someone@example.com");
        var m = Content.parse ("MATMSG:TO:a@b.c;SUB:Hi\\; there;BODY:Text;;");
        assert (m.kind == ContentKind.EMAIL);
        assert (m.field ("subject") == "Hi; there");
        assert (m.url == "mailto:a@b.c?subject=Hi%3B%20there&body=Text");
    });

    Test.add_func ("/content/tel-and-sms", () => {
        var t = Content.parse ("tel:+39%20055%20123");
        assert (t.kind == ContentKind.PHONE);
        assert (t.title == "+39 055 123");
        var s = Content.parse ("SMSTO:+15551234:Hello: world");
        assert (s.kind == ContentKind.SMS);
        assert (s.field ("phone") == "+15551234");
        assert (s.field ("body") == "Hello: world");
        assert (s.url == "sms:+15551234?body=Hello%3A%20world");
        var s2 = Content.parse ("sms:+15551234?body=Ciao%20a%20tutti");
        assert (s2.kind == ContentKind.SMS);
        assert (s2.field ("body") == "Ciao a tutti");
        assert (Content.parse ("tel:").kind == ContentKind.TEXT);
    });

    Test.add_func ("/content/otpauth", () => {
        var c = Content.parse ("otpauth://totp/ACME%20Co:john@example.com?secret=HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ&issuer=ACME%20Co&algorithm=SHA1&digits=6&period=30");
        assert (c.kind == ContentKind.OTP);
        assert (c.field ("issuer") == "ACME Co");
        assert (c.field ("account") == "john@example.com");
        assert (c.field ("secret") == "HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ");
        assert (c.field ("digits") == "6");
        assert (c.title == "ACME Co (john@example.com)");
        foreach (var f in c.fields) if (f.key == "secret") assert (f.secret);
        var h = Content.parse ("otpauth://hotp/Bank:carol?secret=GEZDGNBVGY3TQOJQ&counter=5");
        assert (h.kind == ContentKind.OTP);
        assert (h.field ("counter") == "5");
        assert (Content.parse ("otpauth://totp/NoSecret?issuer=x").kind == ContentKind.TEXT);
        assert (Content.parse ("otpauth://other/x?secret=A").kind == ContentKind.TEXT);
    });

    Test.add_func ("/content/text", () => {
        var c = Content.parse ("Just some words\nand a second line");
        assert (c.kind == ContentKind.TEXT);
        assert (c.title == "Just some words");
        assert (c.raw == "Just some words\nand a second line");
        assert (c.fields.size == 0);
        var long_line = Content.parse (string.nfill (200, 'x'));
        assert (long_line.title.char_count () == 81);
        assert (Content.parse ("").kind == ContentKind.TEXT);
    });

    Test.add_func ("/content/product-codes", () => {
        var c = Content.parse_code ("4006381333931", CodeFormat.EAN13);
        assert (c.kind == ContentKind.PRODUCT);
        assert (c.format == CodeFormat.EAN13);
        assert (c.title == "4006381333931");
        assert (c.field ("code") == "4006381333931");
        assert (c.field ("format") == "EAN-13");
        assert (c.field ("isbn") == null && c.field ("check") == null);
        assert (c.summary () == "Product Code, EAN-13");
        var book = Content.parse_code ("9780306406157", CodeFormat.EAN13);
        assert (book.field ("isbn") == "9780306406157");
        var bad = Content.parse_code ("4006381333932", CodeFormat.EAN13);
        assert (bad.field ("check") != null);
        var upc = Content.parse_code ("036000291452", CodeFormat.UPCA);
        assert (upc.kind == ContentKind.PRODUCT && upc.format == CodeFormat.UPCA);
        var link = Content.parse_code ("https://example.org/p/1", CodeFormat.CODE128);
        assert (link.kind == ContentKind.URL && link.format == CodeFormat.CODE128);
        assert (link.summary () == "Web Link, Code 128");
        var qr = Content.parse_code ("hello", CodeFormat.QR);
        assert (qr.kind == ContentKind.TEXT && qr.summary () == "Text");
        assert (Payload.product_search ("4006381333931", "duckduckgo") == "https://duckduckgo.com/?q=4006381333931");
        assert (Payload.product_search ("4006381333931", "openfoodfacts") == "https://world.openfoodfacts.org/product/4006381333931");
        assert (Payload.product_search ("a b&c", "google") == "https://www.google.com/search?q=a%20b%26c");
        assert (Payload.book_lookup ("9780306406157") == "https://openlibrary.org/isbn/9780306406157");
        assert (CodeFormat.from_id ("upca") == CodeFormat.UPCA);
        assert (CodeFormat.from_id ("nonsense") == CodeFormat.QR);
        foreach (var f in CodeFormat.barcodes ()) assert (CodeFormat.from_id (f.id ()) == f);
    });

    Test.run ();
}
