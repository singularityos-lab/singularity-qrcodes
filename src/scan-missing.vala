namespace Singularity.Apps.QrCodes {

    namespace Scan {
        public const bool AVAILABLE = false;

        public Decoded[] decode_gray (uint8[] gray, int w, int h) {
            return {};
        }

        public Decoded[] decode_file (string path) throws Error {
            throw new IOError.NOT_SUPPORTED (_("Reading QR codes needs the ZBar library."));
        }

        public Decoded[] decode_pixbuf (Gdk.Pixbuf pixbuf) {
            return {};
        }

        public Decoded[] decode_texture (Gdk.Texture texture) {
            return {};
        }

        public uint8[] gray_from_pixels (uint8[] px, int w, int h, int stride, int channels, bool alpha) {
            return {};
        }
    }
}
