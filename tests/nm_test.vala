using Singularity.Apps.QrCodes;

[DBus (name = "org.freedesktop.NetworkManager.Settings")]
public errordomain FakeSettingsError {
    [DBus (name = "PermissionDenied")]
    PERMISSION_DENIED,
    [DBus (name = "NoSecrets")]
    NO_SECRETS
}

[DBus (name = "org.freedesktop.NetworkManager")]
public class FakeManager : Object {
    [DBus (visible = false)]
    public ObjectPath primary { get; set; default = new ObjectPath ("/"); }
    [DBus (visible = false)]
    public ObjectPath[] active { get; set; default = {}; }

    [DBus (name = "PrimaryConnection")]
    public ObjectPath primary_connection {
        owned get { return primary; }
    }

    [DBus (name = "ActiveConnections")]
    public ObjectPath[] active_connections {
        owned get { return active; }
    }
}

[DBus (name = "org.freedesktop.NetworkManager.Connection.Active")]
public class FakeActive : Object {
    public string kind;
    public string settings_path;

    public FakeActive (string kind, string settings_path) {
        this.kind = kind;
        this.settings_path = settings_path;
    }

    [DBus (name = "Type")]
    public string conn_type {
        owned get { return kind; }
    }

    [DBus (name = "Connection")]
    public ObjectPath connection {
        owned get { return new ObjectPath (settings_path); }
    }
}

[DBus (name = "org.freedesktop.NetworkManager.Settings.Connection")]
public class FakeConnection : Object {
    public string ssid;
    public string key_mgmt;
    public string psk;
    public int refuse;
    public int secret_calls;

    public FakeConnection (string ssid, string key_mgmt, string psk, int refuse = 0) {
        this.ssid = ssid;
        this.key_mgmt = key_mgmt;
        this.psk = psk;
        this.refuse = refuse;
    }

    public HashTable<string, HashTable<string, Variant>> get_settings () throws Error {
        var all = new HashTable<string, HashTable<string, Variant>> (str_hash, str_equal);
        var wl = new HashTable<string, Variant> (str_hash, str_equal);
        wl["ssid"] = new Variant.from_bytes (new VariantType ("ay"), new Bytes (ssid.data), true);
        wl["mode"] = new Variant.string ("infrastructure");
        all["802-11-wireless"] = wl;
        if (key_mgmt != "") {
            var sec = new HashTable<string, Variant> (str_hash, str_equal);
            sec["key-mgmt"] = new Variant.string (key_mgmt);
            all["802-11-wireless-security"] = sec;
        }
        return all;
    }

    public HashTable<string, HashTable<string, Variant>> get_secrets (string setting) throws Error {
        secret_calls++;
        if (refuse == 1) throw new FakeSettingsError.PERMISSION_DENIED ("not allowed");
        if (refuse == 2) throw new FakeSettingsError.NO_SECRETS ("no agent");
        var all = new HashTable<string, HashTable<string, Variant>> (str_hash, str_equal);
        var sec = new HashTable<string, Variant> (str_hash, str_equal);
        if (setting == "802-11-wireless-security") sec["psk"] = new Variant.string (psk);
        all[setting] = sec;
        return all;
    }
}

[DBus (name = "org.freedesktop.NetworkManager.Settings")]
public class FakeSettings : Object {
    public ObjectPath[] paths = {};

    public ObjectPath[] list_connections () throws Error {
        return paths;
    }
}

TestDBus test_bus;
DBusConnection server;
FakeManager manager;
uint[] registrations;

void register_path (string path, Object obj) {
    try {
        if (obj is FakeManager) registrations += server.register_object (path, (FakeManager) obj);
        else if (obj is FakeActive) registrations += server.register_object (path, (FakeActive) obj);
        else if (obj is FakeSettings) registrations += server.register_object (path, (FakeSettings) obj);
        else registrations += server.register_object (path, (FakeConnection) obj);
    } catch (IOError e) {
        error ("%s", e.message);
    }
}

void unregister_all () {
    foreach (uint id in registrations) server.unregister_object (id);
    registrations = {};
}

WifiInfo? run_share (out string? problem, out NetworkError? failure) {
    var loop = new MainLoop ();
    WifiInfo? result = null;
    string? p = null;
    NetworkError? f = null;
    Network.current_wifi.begin ((o, res) => {
        try {
            result = Network.current_wifi.end (res, out p);
        } catch (NetworkError e) {
            f = e;
        }
        loop.quit ();
    });
    loop.run ();
    problem = p;
    failure = f;
    return result;
}

WifiInfo? run_saved (string ssid, out string? problem, out NetworkError? failure) {
    var loop = new MainLoop ();
    WifiInfo? result = null;
    string? p = null;
    NetworkError? f = null;
    Network.saved_wifi.begin (ssid, (o, res) => {
        try {
            result = Network.saved_wifi.end (res, out p);
        } catch (NetworkError e) {
            f = e;
        }
        loop.quit ();
    });
    loop.run ();
    problem = p;
    failure = f;
    return result;
}

void setup (FakeConnection conn, string type = "802-11-wireless", bool primary = true) {
    unregister_all ();
    manager = new FakeManager ();
    var active = new FakeActive (type, "/org/freedesktop/NetworkManager/Settings/7");
    var wired = new FakeActive ("802-3-ethernet", "/org/freedesktop/NetworkManager/Settings/1");
    register_path ("/org/freedesktop/NetworkManager", manager);
    register_path ("/org/freedesktop/NetworkManager/ActiveConnection/1", wired);
    register_path ("/org/freedesktop/NetworkManager/ActiveConnection/2", active);
    register_path ("/org/freedesktop/NetworkManager/Settings/7", conn);
    manager.primary = new ObjectPath (primary ? "/org/freedesktop/NetworkManager/ActiveConnection/1" : "/");
    manager.active = { new ObjectPath ("/org/freedesktop/NetworkManager/ActiveConnection/1"), new ObjectPath ("/org/freedesktop/NetworkManager/ActiveConnection/2") };
}

void main (string[] args) {
    Test.init (ref args);
    test_bus = new TestDBus (TestDBusFlags.NONE);
    test_bus.up ();
    Environment.set_variable ("DBUS_SYSTEM_BUS_ADDRESS", test_bus.get_bus_address (), true);

    Test.add_func ("/nm/no-networkmanager", () => {
        string? problem;
        NetworkError? failure;
        run_share (out problem, out failure);
        assert (failure != null && failure is NetworkError.UNAVAILABLE);
    });

    try {
        server = new DBusConnection.for_address_sync (test_bus.get_bus_address (),
            DBusConnectionFlags.AUTHENTICATION_CLIENT | DBusConnectionFlags.MESSAGE_BUS_CONNECTION);
    } catch (Error e) {
        error ("%s", e.message);
    }

    Test.add_func ("/nm/share-wpa", () => {
        own_nm ();
        var conn = new FakeConnection ("Café ☕", "wpa-psk", "p;a:ss");
        setup (conn);
        string? problem;
        NetworkError? failure;
        var info = run_share (out problem, out failure);
        assert (failure == null);
        assert (problem == null);
        assert (info.ssid == "Café ☕");
        assert (info.security == "WPA");
        assert (info.password == "p;a:ss");
        assert (conn.secret_calls == 1);
        assert (Payload.wifi (info) == "WIFI:T:WPA;S:Café ☕;P:p\\;a\\:ss;;");
    });

    Test.add_func ("/nm/share-open", () => {
        var conn = new FakeConnection ("Library", "", "");
        setup (conn, "802-11-wireless", false);
        string? problem;
        NetworkError? failure;
        var info = run_share (out problem, out failure);
        assert (failure == null && problem == null);
        assert (info.security == "nopass");
        assert (conn.secret_calls == 0);
    });

    Test.add_func ("/nm/secret-refused", () => {
        var conn = new FakeConnection ("Home", "sae", "x", 1);
        setup (conn);
        string? problem;
        NetworkError? failure;
        var info = run_share (out problem, out failure);
        assert (failure == null);
        assert (info.ssid == "Home" && info.security == "SAE" && info.password == "");
        assert (problem != null && problem.contains ("not allowed"));
    });

    Test.add_func ("/nm/secret-missing", () => {
        var conn = new FakeConnection ("Home", "wpa-psk", "x", 2);
        setup (conn);
        string? problem;
        NetworkError? failure;
        var info = run_share (out problem, out failure);
        assert (failure == null && info.password == "");
        assert (problem != null && problem.contains ("not saved"));
    });

    Test.add_func ("/nm/not-connected", () => {
        var conn = new FakeConnection ("Home", "wpa-psk", "x");
        setup (conn, "802-3-ethernet");
        string? problem;
        NetworkError? failure;
        run_share (out problem, out failure);
        assert (failure != null && failure is NetworkError.NOT_CONNECTED);
    });

    Test.add_func ("/nm/enterprise", () => {
        var conn = new FakeConnection ("Office", "wpa-eap", "x");
        setup (conn);
        string? problem;
        NetworkError? failure;
        run_share (out problem, out failure);
        assert (failure != null && failure is NetworkError.ENTERPRISE);
        assert (conn.secret_calls == 0);
    });

    Test.add_func ("/nm/share-saved-by-name", () => {
        var current = new FakeConnection ("Café ☕", "wpa-psk", "current-pass");
        setup (current);
        var other = new FakeConnection ("Harbor Guest", "sae", "harbor-pass");
        var open = new FakeConnection ("Library", "", "");
        var settings = new FakeSettings ();
        settings.paths = {
            new ObjectPath ("/org/freedesktop/NetworkManager/Settings/7"),
            new ObjectPath ("/org/freedesktop/NetworkManager/Settings/8"),
            new ObjectPath ("/org/freedesktop/NetworkManager/Settings/9")
        };
        register_path ("/org/freedesktop/NetworkManager/Settings", settings);
        register_path ("/org/freedesktop/NetworkManager/Settings/8", other);
        register_path ("/org/freedesktop/NetworkManager/Settings/9", open);
        string? problem;
        NetworkError? failure;
        var info = run_saved ("Harbor Guest", out problem, out failure);
        assert (failure == null && problem == null);
        assert (info.ssid == "Harbor Guest" && info.security == "SAE" && info.password == "harbor-pass");
        assert (other.secret_calls == 1 && current.secret_calls == 0);
        info = run_saved ("Library", out problem, out failure);
        assert (failure == null && problem == null && info.security == "nopass");
        assert (open.secret_calls == 0);
        run_saved ("Nowhere", out problem, out failure);
        assert (failure != null && failure is NetworkError.NOT_CONNECTED);
    });

    int result = Test.run ();
    unregister_all ();
    test_bus.down ();
    Process.exit (result);
}

bool owned_name = false;

void own_nm () {
    if (owned_name) return;
    var loop = new MainLoop ();
    Bus.own_name_on_connection (server, "org.freedesktop.NetworkManager", BusNameOwnerFlags.NONE, () => loop.quit (), () => {
        error ("could not own the NetworkManager name");
    });
    loop.run ();
    owned_name = true;
}
