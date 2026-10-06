using Gtk;

namespace Singularity.Apps.QrCodes {

    public class CodeView : DrawingArea {
        private QrCode? _code;
        private Barcode? _barcode;
        private int side;

        public QrCode? code {
            get { return _code; }
            set {
                _code = value;
                _barcode = null;
                content_width = side;
                content_height = side;
                update_property (AccessibleProperty.DESCRIPTION, _code != null ? _("QR code, version %d").printf (_code.version) : _("No QR code"), -1);
                queue_draw ();
            }
        }

        public Barcode? barcode {
            get { return _barcode; }
            set {
                _barcode = value;
                _code = null;
                if (_barcode != null) {
                    content_width = side;
                    content_height = (int) (side * 0.62);
                    update_property (AccessibleProperty.DESCRIPTION, _("%s barcode").printf (_barcode.format.label ()), -1);
                }
                queue_draw ();
            }
        }

        public CodeView (int size) {
            side = size;
            content_width = size;
            content_height = size;
            accessible_role = AccessibleRole.IMG;
            update_property (AccessibleProperty.LABEL, _("Code"), -1);
            set_draw_func (paint);
        }

        private void paint (DrawingArea area, Cairo.Context cr, int w, int h) {
            if (_barcode != null) {
                int bw = _barcode.total_width;
                int bh = Render.barcode_height (_barcode);
                double module = double.min (w / (double) bw, h / (double) bh);
                if (module >= 1 && Math.floor (module) / module >= 0.8) module = Math.floor (module);
                double x = Math.floor ((w - module * bw) / 2);
                double y = Math.floor ((h - module * bh) / 2);
                Render.draw_barcode (cr, _barcode, x, y, module);
                return;
            }
            if (_code == null) return;
            int n = _code.size + Render.QUIET * 2;
            int s = int.min (w, h);
            double module = s / (double) n;
            if (module >= 1) module = Math.floor (module);
            double px = module * n;
            double x = Math.floor ((w - px) / 2);
            double y = Math.floor ((h - px) / 2);
            Render.draw (cr, _code, x, y, module);
        }
    }
}
