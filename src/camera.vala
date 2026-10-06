namespace Singularity.Apps.QrCodes {

    public class CameraScanner : Object {
        private const int64 DECODE_INTERVAL = 250000;

        private Gst.Pipeline? pipeline;
        private uint bus_watch;
        private int portal_fd = -1;
        private int64 last_decode;
        private bool decoding;
        private bool frame_pending;
        private Mutex frame_lock;
        private Gst.Sample? pending;
        private uint generation;

        public bool running { get; private set; }
        public string source_name { get; private set; default = ""; }

        public signal void frame (Gdk.Texture texture);
        public signal void decoded (Gee.List<Decoded> codes);
        public signal void failed (string message);

        private static Gst.Element make (string factory, string? name = null) throws Error {
            var e = Gst.ElementFactory.make (factory, name);
            if (e == null) throw new IOError.NOT_FOUND (_("The %s component of GStreamer is missing.").printf (factory));
            return e;
        }

        public async void start () throws Error {
            stop ();
            uint gen = ++generation;
            Gst.Element? src = null;
            bool portal_tried = false;
            if (Gst.ElementFactory.find ("pipewiresrc") != null && yield Portal.camera_present ()) {
                portal_tried = true;
                try {
                    int fd = yield Portal.open_camera ();
                    if (gen != generation) {
                        Posix.close (fd);
                        return;
                    }
                    portal_fd = fd;
                    src = make ("pipewiresrc");
                    src.set ("fd", fd);
                    source_name = _("Camera");
                } catch (PortalError e) {
                    if (e is PortalError.DENIED || e is PortalError.CANCELLED) throw e;
                    src = null;
                }
            }
            if (gen != generation) return;
            if (src == null) src = local_source ();
            if (src == null) {
                if (portal_tried) throw new PortalError.NO_CAMERA (_("The camera could not be opened."));
                throw new PortalError.NO_CAMERA (_("No camera was found. Connect a camera, or check that it is turned on and not used by another app."));
            }
            build (src);
            running = true;
            last_decode = 0;
            var ret = pipeline.set_state (Gst.State.PLAYING);
            if (ret == Gst.StateChangeReturn.FAILURE) {
                stop ();
                throw new IOError.FAILED (_("The camera could not be started."));
            }
        }

        private Gst.Element? local_source () {
            var monitor = new Gst.DeviceMonitor ();
            monitor.add_filter ("Video/Source", new Gst.Caps.empty_simple ("video/x-raw"));
            if (monitor.start ()) {
                foreach (var d in monitor.get_devices ()) {
                    var e = d.create_element (null);
                    if (e != null) {
                        source_name = d.display_name;
                        monitor.stop ();
                        return e;
                    }
                }
                monitor.stop ();
            }
            if (FileUtils.test ("/dev/video0", FileTest.EXISTS)) {
                var v = Gst.ElementFactory.make ("v4l2src", null);
                if (v != null) {
                    source_name = _("Camera");
                    return v;
                }
            }
            return null;
        }

        private void build (Gst.Element src) throws Error {
            pipeline = new Gst.Pipeline ("qrcodes-camera");
            var convert = make ("videoconvert");
            var scale = make ("videoscale");
            var filter = make ("capsfilter");
            filter.set ("caps", Gst.Caps.from_string ("video/x-raw,format=RGBA"));
            var appsink = (Gst.App.Sink) make ("appsink");
            appsink.max_buffers = 1;
            appsink.drop = true;
            appsink.emit_signals = true;
            appsink.sync = false;
            appsink.new_sample.connect (on_sample);
            pipeline.add_many (src, convert, scale, filter, appsink);
            if (!src.link (convert) || !convert.link (scale) || !scale.link (filter) || !filter.link (appsink)) {
                throw new IOError.FAILED (_("The camera stream could not be set up."));
            }
            bus_watch = pipeline.get_bus ().add_watch (Priority.DEFAULT, on_bus);
        }

        private bool on_bus (Gst.Bus bus, Gst.Message msg) {
            if (msg.type == Gst.MessageType.ERROR) {
                Error err;
                string debug;
                msg.parse_error (out err, out debug);
                stop ();
                failed (err.message);
            }
            return true;
        }

        private Gst.FlowReturn on_sample (Gst.App.Sink s) {
            var sample = s.pull_sample ();
            if (sample == null) return Gst.FlowReturn.OK;
            uint gen = generation;
            frame_lock.lock ();
            pending = sample;
            bool schedule = !frame_pending;
            frame_pending = true;
            frame_lock.unlock ();
            if (schedule) {
                Idle.add (() => {
                    frame_lock.lock ();
                    var latest = pending;
                    pending = null;
                    frame_pending = false;
                    frame_lock.unlock ();
                    if (latest != null && gen == generation && running) {
                        var tex = to_texture (latest);
                        if (tex != null) frame (tex);
                    }
                    return Source.REMOVE;
                });
            }
            int64 now = get_monotonic_time ();
            if (!decoding && now - last_decode >= DECODE_INTERVAL) {
                decoding = true;
                last_decode = now;
                Decoded[] found = decode_sample (sample);
                decoding = false;
                if (found.length > 0) {
                    var codes = new Gee.ArrayList<Decoded> ();
                    foreach (var d in found) codes.add (d);
                    Idle.add (() => {
                        if (gen == generation && running) decoded (codes);
                        return Source.REMOVE;
                    });
                }
            }
            return Gst.FlowReturn.OK;
        }

        private static bool sample_geometry (Gst.Sample sample, out int w, out int h, out int stride) {
            w = h = stride = 0;
            var caps = sample.get_caps ();
            if (caps == null) return false;
            unowned Gst.Structure st = caps.get_structure (0);
            if (!st.get_int ("width", out w) || !st.get_int ("height", out h)) return false;
            stride = w * 4;
            var info = new Gst.Video.Info ();
            if (info.from_caps (caps)) stride = info.stride[0];
            return w > 0 && h > 0;
        }

        private static Decoded[] decode_sample (Gst.Sample sample) {
            int w, h, stride;
            if (!sample_geometry (sample, out w, out h, out stride)) return {};
            var buffer = sample.get_buffer ();
            Gst.MapInfo map;
            if (!buffer.map (out map, Gst.MapFlags.READ)) return {};
            Decoded[] found = {};
            if (map.data.length >= stride * h) found = Scan.decode_gray (Scan.gray_from_pixels (map.data, w, h, stride, 4, false), w, h);
            buffer.unmap (map);
            return found;
        }

        private static Gdk.Texture? to_texture (Gst.Sample sample) {
            int w, h, stride;
            if (!sample_geometry (sample, out w, out h, out stride)) return null;
            var buffer = sample.get_buffer ();
            Gst.MapInfo map;
            if (!buffer.map (out map, Gst.MapFlags.READ)) return null;
            var bytes = new Bytes (map.data);
            buffer.unmap (map);
            if (bytes.length < stride * h) return null;
            return new Gdk.MemoryTexture (w, h, Gdk.MemoryFormat.R8G8B8A8, bytes, stride);
        }

        public void stop () {
            generation++;
            running = false;
            if (pipeline != null) {
                pipeline.set_state (Gst.State.NULL);
                if (bus_watch != 0) Source.remove (bus_watch);
                bus_watch = 0;
                pipeline = null;
            }
            if (portal_fd >= 0) {
                Posix.close (portal_fd);
                portal_fd = -1;
            }
        }
    }
}
