using Singularity.Apps.QrCodes;

WifiInfo wifi (string ssid, string security, string password, bool hidden = false) {
    var w = new WifiInfo ();
    w.ssid = ssid;
    w.security = security;
    w.password = password;
    w.hidden = hidden;
    return w;
}

void main (string[] args) {
    Test.init (ref args);

    Test.add_func ("/payload/wifi-escape", () => {
        assert (Payload.wifi_escape ("plain") == "plain");
        assert (Payload.wifi_escape ("a;b,c:d\\e\"f") == "a\\;b\\,c\\:d\\\\e\\\"f");
        assert (Payload.wifi_escape ("Caffè ☕") == "Caffè ☕");
    });

    Test.add_func ("/payload/wifi", () => {
        assert (Payload.wifi (wifi ("Home", "WPA", "secret")) == "WIFI:T:WPA;S:Home;P:secret;;");
        assert (Payload.wifi (wifi ("Guest", "nopass", "ignored")) == "WIFI:T:nopass;S:Guest;;");
        assert (Payload.wifi (wifi ("Hidden;One", "WEP", "k:e,y", true)) == "WIFI:T:WEP;S:Hidden\\;One;P:k\\:e\\,y;H:true;;");
        assert (Payload.wifi (wifi ("New", "wpa3", "x")) == "WIFI:T:SAE;S:New;P:x;;");
    });

    Test.add_func ("/payload/wifi-roundtrip", () => {
        string[] names = { "a", "back\\slash", "semi;colon", "com,ma", "co:lon", "\"quoted\"", "trail\\", "\\;\\,\\:", "Caffè ☕;" };
        string[] kinds = { "WPA", "SAE", "WEP", "nopass" };
        foreach (string n in names) {
            foreach (string k in kinds) {
                foreach (bool hidden in new bool[] { false, true }) {
                    var w = wifi (n, k, n + "!pw", hidden);
                    var c = Content.parse (Payload.wifi (w));
                    assert (c.kind == ContentKind.WIFI);
                    assert (c.wifi.ssid == n);
                    assert (c.wifi.security == k);
                    assert (c.wifi.hidden == hidden);
                    if (k != "nopass") assert (c.wifi.password == n + "!pw");
                    else assert (c.wifi.password == "");
                }
            }
        }
    });

    Test.add_func ("/payload/contact", () => {
        var info = new ContactInfo ();
        info.name = "Ada King Lovelace";
        info.org = "Analytical, Engines";
        info.phone = "+44 20 1234";
        info.email = "ada@example.org";
        info.url = "https://ada.example";
        info.address = "12 St James; London";
        info.note = "Line one\nLine two";
        string card = Payload.contact (info);
        assert (card.has_prefix ("BEGIN:VCARD\nVERSION:3.0\n"));
        assert (card.has_suffix ("END:VCARD"));
        assert (card.contains ("\nN:Lovelace;Ada King;;;\n"));
        assert (card.contains ("\nFN:Ada King Lovelace\n"));
        assert (card.contains ("\nORG:Analytical\\, Engines\n"));
        assert (card.contains ("\nNOTE:Line one\\nLine two\n"));
        var c = Content.parse (card);
        assert (c.kind == ContentKind.CONTACT);
        assert (c.field ("name") == "Ada King Lovelace");
        assert (c.field ("org") == "Analytical, Engines");
        assert (c.field ("phone") == "+44 20 1234");
        assert (c.field ("email") == "ada@example.org");
        assert (c.field ("url") == "https://ada.example");
        assert (c.field ("address") == "12 St James; London");
        assert (c.field ("note") == "Line one\nLine two");
    });

    Test.add_func ("/payload/contact-empty", () => {
        var info = new ContactInfo ();
        assert (info.is_empty ());
        info.email = "x@y.z";
        assert (!info.is_empty ());
        var c = Content.parse (Payload.contact (info));
        assert (c.kind == ContentKind.CONTACT);
        assert (c.title == "x@y.z");
    });

    Test.add_func ("/payload/mailto-sms", () => {
        assert (Payload.mailto ("a@b.c", "", "") == "mailto:a@b.c");
        assert (Payload.mailto ("a@b.c", "Hi & bye", "x=y") == "mailto:a@b.c?subject=Hi%20%26%20bye&body=x%3Dy");
        assert (Payload.sms ("+123", "") == "sms:+123");
        assert (Payload.sms ("+123", "a b") == "sms:+123?body=a%20b");
    });

    Test.run ();
}
