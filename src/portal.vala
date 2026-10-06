namespace Singularity.Apps.QrCodes {

    public errordomain PortalError {
        UNSUPPORTED,
        CANCELLED,
        DENIED,
        NO_CAMERA,
        FAILED
    }

    namespace Portal {
        private const string BUS_NAME = "org.freedesktop.portal.Desktop";
        private const string OBJECT_PATH = "/org/freedesktop/portal/desktop";

        public PortalError map_dbus_error (Error e) {
            if (e is PortalError) return (PortalError) e;
            if (e is DBusError.SERVICE_UNKNOWN || e is DBusError.NAME_HAS_NO_OWNER || e is DBusError.UNKNOWN_METHOD
                || e is DBusError.UNKNOWN_INTERFACE || e is DBusError.UNKNOWN_OBJECT || e is DBusError.NOT_SUPPORTED) {
                return new PortalError.UNSUPPORTED (_("The desktop portal on this system does not offer this feature."));
            }
            if (e is DBusError.ACCESS_DENIED) return new PortalError.DENIED (_("Access was denied."));
            return new PortalError.FAILED (e.message);
        }

        public string request_path (string unique_name, string token) {
            string sender = unique_name.has_prefix (":") ? unique_name.substring (1) : unique_name;
            return "%s/request/%s/%s".printf (OBJECT_PATH, sender.replace (".", "_"), token);
        }

        private class Request : Object {
            public uint32 code = 2;
            public Variant results = new Variant.array (new VariantType ("{sv}"), {});
            public bool done;
            public SourceFunc? resume;

            public void on_response (DBusConnection conn, string? sender, string path, string iface, string name, Variant parameters) {
                if (done) return;
                done = true;
                parameters.get ("(u@a{sv})", out code, out results);
                if (resume != null) Idle.add ((owned) resume);
            }
        }

        private async Variant request (DBusConnection bus, string iface, string method, string? parent, VariantBuilder opts, out uint32 code) throws Error {
            string token = "sinty_qrcodes_%u".printf (Random.next_int ());
            string handle = request_path (bus.unique_name, token);
            var req = new Request ();
            uint sub = bus.signal_subscribe (BUS_NAME, "org.freedesktop.portal.Request", "Response", handle, null, DBusSignalFlags.NONE, req.on_response);
            try {
                opts.add ("{sv}", "handle_token", new Variant.string (token));
                Variant args = parent != null ? new Variant ("(s@a{sv})", parent, opts.end ()) : new Variant ("(@a{sv})", opts.end ());
                var reply = yield bus.call (BUS_NAME, OBJECT_PATH, iface, method, args, new VariantType ("(o)"), DBusCallFlags.NONE, -1, null);
                string returned;
                reply.get ("(o)", out returned);
                if (returned != handle) {
                    bus.signal_unsubscribe (sub);
                    sub = bus.signal_subscribe (BUS_NAME, "org.freedesktop.portal.Request", "Response", returned, null, DBusSignalFlags.NONE, req.on_response);
                }
                if (!req.done) {
                    req.resume = request.callback;
                    yield;
                }
            } finally {
                bus.signal_unsubscribe (sub);
            }
            code = req.code;
            return req.results;
        }

        public async string screenshot (string parent_window = "") throws PortalError {
            try {
                var bus = yield Bus.get (BusType.SESSION);
                var opts = new VariantBuilder (new VariantType ("a{sv}"));
                opts.add ("{sv}", "interactive", new Variant.boolean (true));
                opts.add ("{sv}", "modal", new Variant.boolean (true));
                uint32 code;
                var results = yield request (bus, "org.freedesktop.portal.Screenshot", "Screenshot", parent_window, opts, out code);
                if (code == 1) throw new PortalError.CANCELLED ("cancelled");
                if (code != 0) throw new PortalError.FAILED (_("The screenshot could not be taken."));
                var uri = results.lookup_value ("uri", VariantType.STRING);
                if (uri == null) throw new PortalError.FAILED (_("The desktop portal did not return a screenshot."));
                return uri.get_string ();
            } catch (Error e) {
                throw map_dbus_error (e);
            }
        }

        public async bool camera_present () {
            try {
                var bus = yield Bus.get (BusType.SESSION);
                var reply = yield bus.call (BUS_NAME, OBJECT_PATH, "org.freedesktop.DBus.Properties", "Get",
                    new Variant ("(ss)", "org.freedesktop.portal.Camera", "IsCameraPresent"), new VariantType ("(v)"), DBusCallFlags.NONE, 3000, null);
                Variant v;
                reply.get ("(v)", out v);
                return v.is_of_type (VariantType.BOOLEAN) && v.get_boolean ();
            } catch (Error e) {
                return false;
            }
        }

        public async int open_camera () throws PortalError {
            DBusConnection bus;
            try {
                bus = yield Bus.get (BusType.SESSION);
            } catch (Error e) {
                throw map_dbus_error (e);
            }
            try {
                var opts = new VariantBuilder (new VariantType ("a{sv}"));
                uint32 code;
                yield request (bus, "org.freedesktop.portal.Camera", "AccessCamera", null, opts, out code);
                if (code == 1) throw new PortalError.CANCELLED ("cancelled");
                if (code != 0) throw new PortalError.DENIED (_("QR Codes is not allowed to use the camera. You can allow it in the privacy settings."));
            } catch (Error e) {
                throw map_dbus_error (e);
            }
            try {
                UnixFDList fds;
                var empty = new VariantBuilder (new VariantType ("a{sv}"));
                var reply = yield bus.call_with_unix_fd_list (BUS_NAME, OBJECT_PATH, "org.freedesktop.portal.Camera", "OpenPipeWireRemote",
                    new Variant ("(@a{sv})", empty.end ()), new VariantType ("(h)"), DBusCallFlags.NONE, -1, null, null, out fds);
                int32 index;
                reply.get ("(h)", out index);
                if (fds == null) throw new PortalError.FAILED (_("The camera could not be opened."));
                return fds.get (index);
            } catch (Error e) {
                throw map_dbus_error (e);
            }
        }
    }
}
