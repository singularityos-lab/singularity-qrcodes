using Singularity.Apps.QrCodes;

Variant? section (Variant settings, string name) {
    return settings.lookup_value (name, new VariantType ("a{sv}"));
}

string str (Variant sec, string key) {
    var v = sec.lookup_value (key, VariantType.STRING);
    return v != null ? v.get_string () : "";
}

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

    Test.add_func ("/network/wpa", () => {
        var s = Network.settings (wifi ("Café ☕", "WPA", "hunter22"), "uuid-1");
        assert (s.get_type_string () == "a{sa{sv}}");
        var conn = section (s, "connection");
        assert (str (conn, "id") == "Café ☕");
        assert (str (conn, "type") == "802-11-wireless");
        assert (str (conn, "uuid") == "uuid-1");
        var wl = section (s, "802-11-wireless");
        var ssid = wl.lookup_value ("ssid", new VariantType ("ay"));
        assert (ssid != null);
        assert (ssid.get_size () == "Café ☕".length);
        assert (Memory.cmp (ssid.get_data (), "Café ☕".data, "Café ☕".length) == 0);
        assert (str (wl, "mode") == "infrastructure");
        assert (wl.lookup_value ("hidden", VariantType.BOOLEAN) == null);
        var sec = section (s, "802-11-wireless-security");
        assert (str (sec, "key-mgmt") == "wpa-psk");
        assert (str (sec, "psk") == "hunter22");
    });

    Test.add_func ("/network/open-hidden", () => {
        var s = Network.settings (wifi ("Lobby", "nopass", "", true), "u");
        assert (section (s, "802-11-wireless-security") == null);
        var hidden = section (s, "802-11-wireless").lookup_value ("hidden", VariantType.BOOLEAN);
        assert (hidden != null && hidden.get_boolean ());
    });

    Test.add_func ("/network/sae", () => {
        var sec = section (Network.settings (wifi ("New", "SAE", "pw"), "u"), "802-11-wireless-security");
        assert (str (sec, "key-mgmt") == "sae");
        assert (str (sec, "psk") == "pw");
    });

    Test.add_func ("/network/wep", () => {
        var sec = section (Network.settings (wifi ("Old", "WEP", "0123456789"), "u"), "802-11-wireless-security");
        assert (str (sec, "key-mgmt") == "none");
        assert (str (sec, "wep-key0") == "0123456789");
        assert (sec.lookup_value ("wep-key-type", VariantType.UINT32).get_uint32 () == 1);
        var phrase = section (Network.settings (wifi ("Old", "WEP", "a long passphrase"), "u"), "802-11-wireless-security");
        assert (phrase.lookup_value ("wep-key-type", VariantType.UINT32).get_uint32 () == 2);
        assert (Network.wep_is_key ("abcde"));
        assert (Network.wep_is_key ("0123456789abcdef0123456789"));
        assert (!Network.wep_is_key ("012345678g"));
        assert (!Network.wep_is_key ("toolongforakeybutnotphrase"));
    });

    Test.add_func ("/network/from-scanned-code", () => {
        var c = Content.parse ("WIFI:T:WPA;S:Home\\;Net;P:pa\\:ss;H:true;;");
        var s = Network.settings (c.wifi, "u");
        assert (str (section (s, "connection"), "id") == "Home;Net");
        assert (str (section (s, "802-11-wireless-security"), "psk") == "pa:ss");
    });

    Test.add_func ("/network/read-settings", () => {
        try {
            var info = Network.wifi_from_settings (Network.settings (wifi ("Café ☕", "WPA", "secret", true), "u"));
            assert (info.ssid == "Café ☕");
            assert (info.security == "WPA");
            assert (info.hidden);
            assert (info.password == "");
            assert (Network.wifi_from_settings (Network.settings (wifi ("Open", "nopass", ""), "u")).security == "nopass");
            assert (Network.wifi_from_settings (Network.settings (wifi ("Six", "SAE", "x"), "u")).security == "SAE");
            assert (Network.wifi_from_settings (Network.settings (wifi ("Old", "WEP", "abcde"), "u")).security == "WEP");
        } catch (NetworkError e) {
            error ("%s", e.message);
        }
    });

    Test.add_func ("/network/enterprise-and-wired", () => {
        var all = new VariantBuilder (new VariantType ("a{sa{sv}}"));
        var wl = new VariantBuilder (new VariantType ("a{sv}"));
        wl.add ("{sv}", "ssid", new Variant.from_bytes (new VariantType ("ay"), new Bytes ("Office".data), true));
        all.add ("{s@a{sv}}", "802-11-wireless", wl.end ());
        var sec = new VariantBuilder (new VariantType ("a{sv}"));
        sec.add ("{sv}", "key-mgmt", new Variant.string ("wpa-eap"));
        all.add ("{s@a{sv}}", "802-11-wireless-security", sec.end ());
        try {
            Network.wifi_from_settings (all.end ());
            assert_not_reached ();
        } catch (NetworkError e) {
            assert (e is NetworkError.ENTERPRISE);
        }
        var wired = new VariantBuilder (new VariantType ("a{sa{sv}}"));
        var eth = new VariantBuilder (new VariantType ("a{sv}"));
        eth.add ("{sv}", "mtu", new Variant.uint32 (1500));
        wired.add ("{s@a{sv}}", "802-3-ethernet", eth.end ());
        try {
            Network.wifi_from_settings (wired.end ());
            assert_not_reached ();
        } catch (NetworkError e) {
            assert (e is NetworkError.NOT_CONNECTED);
        }
    });

    Test.add_func ("/network/secrets", () => {
        var info = wifi ("Home", "WPA", "");
        var s = new VariantBuilder (new VariantType ("a{sa{sv}}"));
        var sec = new VariantBuilder (new VariantType ("a{sv}"));
        sec.add ("{sv}", "psk", new Variant.string ("p;a:ss"));
        s.add ("{s@a{sv}}", "802-11-wireless-security", sec.end ());
        assert (Network.secret_from (s.end (), info) == "p;a:ss");

        var wep = wifi ("Old", "WEP", "");
        var w = new VariantBuilder (new VariantType ("a{sa{sv}}"));
        var ws = new VariantBuilder (new VariantType ("a{sv}"));
        ws.add ("{sv}", "wep-key0", new Variant.string ("zero"));
        ws.add ("{sv}", "wep-key2", new Variant.string ("two22"));
        ws.add ("{sv}", "wep-tx-keyidx", new Variant.uint32 (2));
        w.add ("{s@a{sv}}", "802-11-wireless-security", ws.end ());
        assert (Network.secret_from (w.end (), wep) == "two22");

        var empty = new VariantBuilder (new VariantType ("a{sa{sv}}"));
        assert (Network.secret_from (empty.end (), info) == null);
    });

    Test.add_func ("/network/share-payload", () => {
        var info = wifi ("Caffè; \"Wi,Fi\"", "WPA", "p:w;d\\");
        string p = Payload.wifi (info);
        assert (p == "WIFI:T:WPA;S:Caffè\\; \\\"Wi\\,Fi\\\";P:p\\:w\\;d\\\\;;");
        var c = Content.parse (p);
        assert (c.kind == ContentKind.WIFI);
        assert (c.wifi.ssid == info.ssid && c.wifi.password == info.password);
        assert (Payload.wifi (wifi ("Open Cafe", "nopass", "ignored")) == "WIFI:T:nopass;S:Open Cafe;;");
        assert (Payload.wifi (wifi ("Hidden", "SAE", "pw", true)) == "WIFI:T:SAE;S:Hidden;P:pw;H:true;;");
    });

    Test.add_func ("/network/ssid-bytes", () => {
        uint8[] raw = { 'N', 'e', 't', 0xff, '1' };
        string s = Network.ssid_text (new Variant.from_bytes (new VariantType ("ay"), new Bytes (raw), true));
        assert (s.validate ());
        assert (s.has_prefix ("Net") && s.has_suffix ("1"));
    });

    Test.run ();
}
