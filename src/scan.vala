namespace Singularity.Apps.QrCodes {

    namespace Scan {
        public const bool AVAILABLE = true;

        public uint8[] gray_from_pixels (uint8[] px, int w, int h, int stride, int channels, bool alpha) {
            var gray = new uint8[w * h];
            for (int y = 0; y < h; y++) {
                for (int x = 0; x < w; x++) {
                    int i = y * stride + x * channels;
                    int lum = (px[i] * 299 + px[i + 1] * 587 + px[i + 2] * 114) / 1000;
                    if (alpha) {
                        int a = px[i + 3];
                        lum = (lum * a + 255 * (255 - a)) / 255;
                    }
                    gray[y * w + x] = (uint8) lum;
                }
            }
            return gray;
        }

        public Decoded[] from_pairs (string[] pairs) {
            Decoded[] found = {};
            var seen = new Gee.HashSet<string> ();
            for (int i = 0; i + 1 < pairs.length; i += 2) {
                if (!seen.add (pairs[i] + "\n" + pairs[i + 1])) continue;
                found += new Decoded (CodeFormat.from_id (pairs[i]), pairs[i + 1]);
            }
            return found;
        }

        public Decoded[] decode_gray (uint8[] gray, int w, int h) {
            var found = from_pairs (QrBridge.decode (gray, w, h));
            if (found.length > 0) return found;
            var inverted = new uint8[gray.length];
            for (int i = 0; i < gray.length; i++) inverted[i] = 255 - gray[i];
            return from_pairs (QrBridge.decode (inverted, w, h));
        }

        public Decoded[] decode_pixbuf (Gdk.Pixbuf source) {
            var pixbuf = source;
            if (pixbuf.n_channels < 3) return {};
            int longest = int.max (pixbuf.width, pixbuf.height);
            if (longest > 2400) {
                double k = 2400.0 / longest;
                pixbuf = pixbuf.scale_simple ((int) (pixbuf.width * k), (int) (pixbuf.height * k), Gdk.InterpType.BILINEAR);
            }
            unowned uint8[] px = pixbuf.get_pixels_with_length ();
            var found = decode_gray (gray_from_pixels (px, pixbuf.width, pixbuf.height, pixbuf.rowstride, pixbuf.n_channels, pixbuf.has_alpha), pixbuf.width, pixbuf.height);
            if (found.length == 0 && longest < 400) {
                var big = pixbuf.scale_simple (pixbuf.width * 3, pixbuf.height * 3, Gdk.InterpType.NEAREST);
                unowned uint8[] bpx = big.get_pixels_with_length ();
                found = decode_gray (gray_from_pixels (bpx, big.width, big.height, big.rowstride, big.n_channels, big.has_alpha), big.width, big.height);
            }
            return found;
        }

        public Decoded[] decode_file (string path) throws Error {
            var pixbuf = new Gdk.Pixbuf.from_file (path);
            var t = pixbuf.apply_embedded_orientation ();
            return decode_pixbuf (t ?? pixbuf);
        }

        public Decoded[] decode_texture (Gdk.Texture texture) {
            var downloader = new Gdk.TextureDownloader (texture);
            downloader.set_format (Gdk.MemoryFormat.R8G8B8A8);
            size_t stride;
            var bytes = downloader.download_bytes (out stride);
            var pixbuf = new Gdk.Pixbuf.from_bytes (bytes, Gdk.Colorspace.RGB, true, 8, texture.width, texture.height, (int) stride);
            return decode_pixbuf (pixbuf);
        }
    }
}
