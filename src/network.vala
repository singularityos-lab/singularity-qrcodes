namespace Singularity.Apps.QrCodes {

    public errordomain NetworkError {
        UNAVAILABLE,
        NO_ADAPTER,
        DENIED,
        NOT_CONNECTED,
        ENTERPRISE,
        FAILED
    }

    namespace Network {
        private const string NM_NAME = "org.freedesktop.NetworkManager";
        private const string NM_PATH = "/org/freedesktop/NetworkManager";
        private const uint32 DEVICE_TYPE_WIFI = 2;
        private const string ACTIVE_IFACE = "org.freedesktop.NetworkManager.Connection.Active";
        private const string CONNECTION_IFACE = "org.freedesktop.NetworkManager.Settings.Connection";
        private const string WIRELESS = "802-11-wireless";
        private const string SECURITY = "802-11-wireless-security";

        public bool wep_is_key (string password) {
            int n = password.length;
            if (n == 5 || n == 13) return true;
            if ((n == 10 || n == 26) && Regex.match_simple ("^[0-9A-Fa-f]+$", password)) return true;
            return false;
        }

        public Variant settings (WifiInfo info, string uuid) {
            var conn = new VariantBuilder (new VariantType ("a{sv}"));
            conn.add ("{sv}", "id", new Variant.string (info.ssid));
            conn.add ("{sv}", "type", new Variant.string ("802-11-wireless"));
            conn.add ("{sv}", "uuid", new Variant.string (uuid));

            var wireless = new VariantBuilder (new VariantType ("a{sv}"));
            wireless.add ("{sv}", "ssid", new Variant.from_bytes (new VariantType ("ay"), new Bytes (info.ssid.data), true));
            wireless.add ("{sv}", "mode", new Variant.string ("infrastructure"));
            if (info.hidden) wireless.add ("{sv}", "hidden", new Variant.boolean (true));

            var all = new VariantBuilder (new VariantType ("a{sa{sv}}"));
            all.add ("{s@a{sv}}", "connection", conn.end ());
            all.add ("{s@a{sv}}", "802-11-wireless", wireless.end ());

            string security = WifiInfo.normalize_security (info.security);
            if (security != "nopass") {
                var sec = new VariantBuilder (new VariantType ("a{sv}"));
                switch (security) {
                    case "WEP":
                        sec.add ("{sv}", "key-mgmt", new Variant.string ("none"));
                        sec.add ("{sv}", "wep-key0", new Variant.string (info.password));
                        sec.add ("{sv}", "wep-key-type", new Variant.uint32 (wep_is_key (info.password) ? 1 : 2));
                        break;
                    case "SAE":
                        sec.add ("{sv}", "key-mgmt", new Variant.string ("sae"));
                        sec.add ("{sv}", "psk", new Variant.string (info.password));
                        break;
                    default:
                        sec.add ("{sv}", "key-mgmt", new Variant.string ("wpa-psk"));
                        sec.add ("{sv}", "psk", new Variant.string (info.password));
                        break;
                }
                all.add ("{s@a{sv}}", "802-11-wireless-security", sec.end ());
            }
            return all.end ();
        }

        private NetworkError map_error (Error e) {
            if (e is NetworkError) return (NetworkError) e;
            if (e is DBusError.SERVICE_UNKNOWN || e is DBusError.NAME_HAS_NO_OWNER || e is IOError.NOT_FOUND) {
                return new NetworkError.UNAVAILABLE (_("NetworkManager is not running, so QR Codes cannot join networks. Enter the password in your network settings instead."));
            }
            if (e is DBusError.ACCESS_DENIED || (e.message != null && e.message.contains ("PermissionDenied"))) {
                return new NetworkError.DENIED (_("You are not allowed to add network connections."));
            }
            DBusError.strip_remote_error (e);
            return new NetworkError.FAILED (e.message);
        }

        private async string find_wifi_device (DBusConnection bus) throws Error {
            var reply = yield bus.call (NM_NAME, NM_PATH, NM_NAME, "GetDevices", null, new VariantType ("(ao)"), DBusCallFlags.NONE, 5000, null);
            var paths = reply.get_child_value (0);
            for (size_t i = 0; i < paths.n_children (); i++) {
                string path = paths.get_child_value (i).get_string ();
                try {
                    var prop = yield bus.call (NM_NAME, path, "org.freedesktop.DBus.Properties", "Get",
                        new Variant ("(ss)", "org.freedesktop.NetworkManager.Device", "DeviceType"), new VariantType ("(v)"), DBusCallFlags.NONE, 5000, null);
                    Variant v;
                    prop.get ("(v)", out v);
                    if (v.is_of_type (VariantType.UINT32) && v.get_uint32 () == DEVICE_TYPE_WIFI) return path;
                } catch (Error e) {
                }
            }
            throw new NetworkError.NO_ADAPTER (_("This computer has no Wi-Fi adapter."));
        }

        public async void connect (WifiInfo info) throws NetworkError {
            try {
                var bus = yield Bus.get (BusType.SYSTEM);
                string device = yield find_wifi_device (bus);
                yield bus.call (NM_NAME, NM_PATH, NM_NAME, "AddAndActivateConnection",
                    new Variant ("(@a{sa{sv}}oo)", settings (info, Uuid.string_random ()), device, "/"),
                    new VariantType ("(oo)"), DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION, 30000, null);
            } catch (Error e) {
                throw map_error (e);
            }
        }

        public string ssid_text (Variant ssid) {
            var sb = new StringBuilder ();
            sb.append_len ((string) ssid.get_data (), (ssize_t) ssid.get_size ());
            return sb.str.make_valid ();
        }

        public WifiInfo wifi_from_settings (Variant settings) throws NetworkError {
            var wireless = settings.lookup_value (WIRELESS, new VariantType ("a{sv}"));
            if (wireless == null) throw new NetworkError.NOT_CONNECTED (_("The active connection is not a Wi-Fi network."));
            var ssid = wireless.lookup_value ("ssid", new VariantType ("ay"));
            if (ssid == null || ssid.get_size () == 0) throw new NetworkError.FAILED (_("The network has no name."));
            var info = new WifiInfo ();
            info.ssid = ssid_text (ssid);
            var hidden = wireless.lookup_value ("hidden", VariantType.BOOLEAN);
            info.hidden = hidden != null && hidden.get_boolean ();
            info.security = "nopass";
            var sec = settings.lookup_value (SECURITY, new VariantType ("a{sv}"));
            if (sec != null) {
                var km = sec.lookup_value ("key-mgmt", VariantType.STRING);
                string mgmt = km != null ? km.get_string () : "";
                switch (mgmt) {
                    case "wpa-psk": info.security = "WPA"; break;
                    case "sae": info.security = "SAE"; break;
                    case "none": info.security = "WEP"; break;
                    case "owe": case "": info.security = "nopass"; break;
                    default:
                        throw new NetworkError.ENTERPRISE (_("%s uses a company sign-in, which cannot be shared as a code.").printf (info.ssid));
                }
            }
            return info;
        }

        public string? secret_from (Variant secrets, WifiInfo info) {
            var sec = secrets.lookup_value (SECURITY, new VariantType ("a{sv}"));
            if (sec == null) return null;
            string key = "psk";
            if (info.security == "WEP") {
                var idx = sec.lookup_value ("wep-tx-keyidx", VariantType.UINT32);
                key = "wep-key%u".printf (idx != null ? uint.min (idx.get_uint32 (), 3) : 0);
            }
            var v = sec.lookup_value (key, VariantType.STRING);
            if (v == null || v.get_string () == "") return null;
            return v.get_string ();
        }

        private async Variant get_property (DBusConnection bus, string path, string iface, string name) throws Error {
            var reply = yield bus.call (NM_NAME, path, "org.freedesktop.DBus.Properties", "Get",
                new Variant ("(ss)", iface, name), new VariantType ("(v)"), DBusCallFlags.NONE, 5000, null);
            Variant v;
            reply.get ("(v)", out v);
            return v;
        }

        private async string? wifi_settings_path (DBusConnection bus) throws Error {
            string[] candidates = {};
            var primary = yield get_property (bus, NM_PATH, NM_NAME, "PrimaryConnection");
            if (primary.is_of_type (VariantType.OBJECT_PATH) && primary.get_string () != "/") candidates += primary.get_string ();
            var active = yield get_property (bus, NM_PATH, NM_NAME, "ActiveConnections");
            if (active.is_of_type (new VariantType ("ao"))) {
                for (size_t i = 0; i < active.n_children (); i++) candidates += active.get_child_value (i).get_string ();
            }
            foreach (string path in candidates) {
                try {
                    var type = yield get_property (bus, path, ACTIVE_IFACE, "Type");
                    if (!type.is_of_type (VariantType.STRING) || type.get_string () != WIRELESS) continue;
                    var conn = yield get_property (bus, path, ACTIVE_IFACE, "Connection");
                    if (conn.is_of_type (VariantType.OBJECT_PATH) && conn.get_string () != "/") return conn.get_string ();
                } catch (Error e) {
                }
            }
            return null;
        }

        public async WifiInfo current_wifi (out string? secret_problem) throws NetworkError {
            secret_problem = null;
            try {
                var bus = yield Bus.get (BusType.SYSTEM);
                string? path = yield wifi_settings_path (bus);
                if (path == null) throw new NetworkError.NOT_CONNECTED (_("This computer is not connected to a Wi-Fi network."));
                var reply = yield bus.call (NM_NAME, path, CONNECTION_IFACE, "GetSettings", null,
                    new VariantType ("(a{sa{sv}})"), DBusCallFlags.NONE, 5000, null);
                var info = wifi_from_settings (reply.get_child_value (0));
                return yield with_secret (bus, path, info, out secret_problem);
            } catch (Error e) {
                var mapped = map_error (e);
                if (mapped is NetworkError.UNAVAILABLE) throw new NetworkError.UNAVAILABLE (_("NetworkManager is not running, so QR Codes cannot read the current Wi-Fi network."));
                throw mapped;
            }
        }

        public bool settings_match (Variant settings, string ssid) {
            var wireless = settings.lookup_value (WIRELESS, new VariantType ("a{sv}"));
            if (wireless == null) return false;
            var mode = wireless.lookup_value ("mode", VariantType.STRING);
            if (mode != null && mode.get_string () == "ap") return false;
            var name = wireless.lookup_value ("ssid", new VariantType ("ay"));
            return name != null && name.get_size () > 0 && ssid_text (name) == ssid;
        }

        public async WifiInfo saved_wifi (string ssid, out string? secret_problem) throws NetworkError {
            secret_problem = null;
            try {
                var bus = yield Bus.get (BusType.SYSTEM);
                var list = yield bus.call (NM_NAME, NM_PATH + "/Settings", NM_NAME + ".Settings", "ListConnections", null,
                    new VariantType ("(ao)"), DBusCallFlags.NONE, 5000, null);
                var paths = list.get_child_value (0);
                for (size_t i = 0; i < paths.n_children (); i++) {
                    string path = paths.get_child_value (i).get_string ();
                    Variant settings;
                    try {
                        var reply = yield bus.call (NM_NAME, path, CONNECTION_IFACE, "GetSettings", null,
                            new VariantType ("(a{sa{sv}})"), DBusCallFlags.NONE, 5000, null);
                        settings = reply.get_child_value (0);
                    } catch (Error e) {
                        continue;
                    }
                    if (!settings_match (settings, ssid)) continue;
                    var info = wifi_from_settings (settings);
                    return yield with_secret (bus, path, info, out secret_problem);
                }
                throw new NetworkError.NOT_CONNECTED (_("%s is not saved on this computer.").printf (ssid));
            } catch (Error e) {
                var mapped = map_error (e);
                if (mapped is NetworkError.UNAVAILABLE) throw new NetworkError.UNAVAILABLE (_("NetworkManager is not running, so QR Codes cannot read the saved Wi-Fi networks."));
                throw mapped;
            }
        }

        private async WifiInfo with_secret (DBusConnection bus, string path, WifiInfo info, out string? secret_problem) {
            secret_problem = null;
            if (info.security == "nopass") return info;
            try {
                var secrets = yield bus.call (NM_NAME, path, CONNECTION_IFACE, "GetSecrets", new Variant ("(s)", SECURITY),
                    new VariantType ("(a{sa{sv}})"), DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION, 120000, null);
                string? secret = secret_from (secrets.get_child_value (0), info);
                if (secret != null) info.password = secret;
                else secret_problem = _("The password of %s is not saved on this computer.").printf (info.ssid);
            } catch (Error e) {
                string remote = DBusError.get_remote_error (e) ?? "";
                var mapped = map_error (e);
                if (remote.has_suffix ("UserCanceled")) secret_problem = _("The password request was cancelled.");
                else if (remote.has_suffix ("NoSecrets")) secret_problem = _("The password of %s is not saved on this computer.").printf (info.ssid);
                else if (mapped is NetworkError.DENIED) secret_problem = _("You are not allowed to see the password of %s.").printf (info.ssid);
                else secret_problem = mapped.message;
            }
            return info;
        }
    }
}
