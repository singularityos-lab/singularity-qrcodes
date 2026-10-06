using Singularity.Apps.QrCodes;

void main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/csv/field", () => {
        assert (Csv.field ("plain") == "plain");
        assert (Csv.field ("a,b") == "\"a,b\"");
        assert (Csv.field ("say \"hi\"") == "\"say \"\"hi\"\"\"");
        assert (Csv.field ("two\nlines") == "\"two\nlines\"");
        assert (Csv.field (" padded") == "\" padded\"");
        assert (Csv.field ("") == "");
        assert (Csv.field ("Caffè ☕") == "Caffè ☕");
    });

    Test.add_func ("/csv/formula-guard", () => {
        assert (Csv.field ("=HYPERLINK(\"x\")") == "\"'=HYPERLINK(\"\"x\"\")\"");
        assert (Csv.field ("+1 555") == "'+1 555");
        assert (Csv.field ("@cmd") == "'@cmd");
        assert (Csv.field ("-2") == "'-2");
        assert (Csv.field ("4006381333931") == "4006381333931");
    });

    Test.add_func ("/csv/document", () => {
        var groups = new Gee.ArrayList<ScanGroup> ();
        var a = new ScanGroup ("shelf, left.jpg");
        a.codes.add (new Decoded (CodeFormat.EAN13, "4006381333931"));
        a.codes.add (new Decoded (CodeFormat.QR, "WIFI:T:WPA;S:Home;P:pw;;"));
        groups.add (a);
        var b = new ScanGroup ("blank.png");
        groups.add (b);
        var c = new ScanGroup ("broken.png");
        c.error = "The file is not a picture QR Codes can open.";
        groups.add (c);
        var d = new ScanGroup ("label.png");
        d.codes.add (new Decoded (CodeFormat.CODE128, "https://example.org/a,b"));
        groups.add (d);
        assert (Csv.count (groups) == 3);
        string doc = Csv.document (groups);
        string[] lines = doc.split ("\r\n");
        assert (lines.length == 7);
        assert (lines[0] == "File,Format,Type,Content");
        assert (lines[1] == "\"shelf, left.jpg\",EAN-13,Product Code,4006381333931");
        assert (lines[2] == "\"shelf, left.jpg\",QR Code,Wi-Fi Network,WIFI:T:WPA;S:Home;P:pw;;");
        assert (lines[3] == "blank.png,,No code found,");
        assert (lines[4] == "broken.png,,The file is not a picture QR Codes can open.,");
        assert (lines[5] == "label.png,Code 128,Web Link,\"https://example.org/a,b\"");
        assert (lines[6] == "");
    });

    Test.run ();
}
