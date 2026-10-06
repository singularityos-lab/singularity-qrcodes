namespace Singularity.Apps.QrCodes {

    namespace Render {
        public const int QUIET = 4;

        public void draw (Cairo.Context cr, QrCode qr, double x, double y, double module) {
            int n = qr.size + QUIET * 2;
            cr.save ();
            if (module == Math.floor (module)) cr.set_antialias (Cairo.Antialias.NONE);
            cr.set_source_rgb (1, 1, 1);
            cr.rectangle (x, y, n * module, n * module);
            cr.fill ();
            cr.set_source_rgb (0, 0, 0);
            for (int my = 0; my < qr.size; my++) {
                int mx = 0;
                while (mx < qr.size) {
                    if (!qr.get_module (mx, my)) {
                        mx++;
                        continue;
                    }
                    int start = mx;
                    while (mx < qr.size && qr.get_module (mx, my)) mx++;
                    cr.rectangle (x + (start + QUIET) * module, y + (my + QUIET) * module, (mx - start) * module, module);
                }
            }
            cr.fill ();
            cr.restore ();
        }

        public Cairo.ImageSurface surface (QrCode qr, int module) {
            int px = (qr.size + QUIET * 2) * module;
            var s = new Cairo.ImageSurface (Cairo.Format.RGB24, px, px);
            var cr = new Cairo.Context (s);
            draw (cr, qr, 0, 0, module);
            s.flush ();
            return s;
        }

        public int module_for_size (QrCode qr, int target_px) {
            return int.max (1, target_px / (qr.size + QUIET * 2));
        }

        public void save_png (QrCode qr, int module, string path) throws Error {
            var s = surface (qr, module);
            var status = s.write_to_png (path);
            if (status != Cairo.Status.SUCCESS) throw new IOError.FAILED (_("The image could not be saved."));
        }

        public uint8[] png_bytes (QrCode qr, int module) throws Error {
            var s = surface (qr, module);
            var buffer = new ByteArray ();
            var status = s.write_to_png_stream ((data) => {
                buffer.append (data);
                return Cairo.Status.SUCCESS;
            });
            if (status != Cairo.Status.SUCCESS) throw new IOError.FAILED (_("The image could not be created."));
            return buffer.steal ();
        }

        public string svg (QrCode qr, int module = 8) {
            int n = qr.size + QUIET * 2;
            var sb = new StringBuilder ();
            sb.append ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
            sb.append ("<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\" shape-rendering=\"crispEdges\">\n".printf (n * module, n * module, n, n));
            sb.append ("<rect width=\"%d\" height=\"%d\" fill=\"#ffffff\"/>\n".printf (n, n));
            sb.append ("<path fill=\"#000000\" d=\"");
            for (int y = 0; y < qr.size; y++) {
                int x = 0;
                while (x < qr.size) {
                    if (!qr.get_module (x, y)) {
                        x++;
                        continue;
                    }
                    int start = x;
                    while (x < qr.size && qr.get_module (x, y)) x++;
                    sb.append ("M%d %dh%dv1h-%dz".printf (start + QUIET, y + QUIET, x - start, x - start));
                }
            }
            sb.append ("\"/>\n</svg>\n");
            return sb.str;
        }

        public const int BAR_MARGIN = 6;
        public const int TEXT_BAND = 12;
        public const int GUARD_EXTRA = 6;
        public const int FONT_SIZE = 9;
        public const int TEXT_BASELINE = 10;

        public int barcode_height (Barcode b) {
            return BAR_MARGIN * 2 + b.bar_height + TEXT_BAND;
        }

        public void draw_barcode (Cairo.Context cr, Barcode b, double x, double y, double module) {
            int w = b.total_width;
            int h = barcode_height (b);
            cr.save ();
            cr.set_source_rgb (1, 1, 1);
            cr.rectangle (x, y, w * module, h * module);
            cr.fill ();
            cr.set_source_rgb (0, 0, 0);
            if (module == Math.floor (module)) cr.set_antialias (Cairo.Antialias.NONE);
            double left = x + b.quiet_left * module;
            double top = y + BAR_MARGIN * module;
            int i = 0;
            while (i < b.width) {
                if (!b.get_bar (i)) {
                    i++;
                    continue;
                }
                int start = i;
                bool guard = b.is_guard (i);
                while (i < b.width && b.get_bar (i) && b.is_guard (i) == guard) i++;
                int height = b.bar_height + (guard ? GUARD_EXTRA : 0);
                cr.rectangle (left + start * module, top, (i - start) * module, height * module);
            }
            cr.fill ();
            cr.set_antialias (Cairo.Antialias.DEFAULT);
            cr.select_font_face ("monospace", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
            cr.set_font_size (FONT_SIZE * module);
            double baseline = top + (b.bar_height + TEXT_BASELINE) * module;
            foreach (var run in b.runs) {
                if (run.text == "") continue;
                Cairo.TextExtents ext;
                cr.text_extents (run.text, out ext);
                double center = left + (run.start + run.end) / 2.0 * module;
                cr.move_to (center - ext.x_advance / 2, baseline);
                cr.show_text (run.text);
            }
            cr.restore ();
        }

        public Cairo.ImageSurface barcode_surface (Barcode b, int module) {
            var s = new Cairo.ImageSurface (Cairo.Format.RGB24, b.total_width * module, barcode_height (b) * module);
            var cr = new Cairo.Context (s);
            draw_barcode (cr, b, 0, 0, module);
            s.flush ();
            return s;
        }

        public int barcode_module_for_width (Barcode b, int target_px) {
            return int.max (1, target_px / b.total_width);
        }

        public void save_barcode_png (Barcode b, int module, string path) throws Error {
            var status = barcode_surface (b, module).write_to_png (path);
            if (status != Cairo.Status.SUCCESS) throw new IOError.FAILED (_("The image could not be saved."));
        }

        public uint8[] barcode_png_bytes (Barcode b, int module) throws Error {
            var buffer = new ByteArray ();
            var status = barcode_surface (b, module).write_to_png_stream ((data) => {
                buffer.append (data);
                return Cairo.Status.SUCCESS;
            });
            if (status != Cairo.Status.SUCCESS) throw new IOError.FAILED (_("The image could not be created."));
            return buffer.steal ();
        }

        public string barcode_svg (Barcode b, int module = 3) {
            int w = b.total_width;
            int h = barcode_height (b);
            var sb = new StringBuilder ();
            sb.append ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
            sb.append ("<svg xmlns=\"http://www.w3.org/2000/svg\" version=\"1.1\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\">\n".printf (w * module, h * module, w, h));
            sb.append ("<rect width=\"%d\" height=\"%d\" fill=\"#ffffff\"/>\n".printf (w, h));
            sb.append ("<path fill=\"#000000\" shape-rendering=\"crispEdges\" d=\"");
            int i = 0;
            while (i < b.width) {
                if (!b.get_bar (i)) {
                    i++;
                    continue;
                }
                int start = i;
                bool guard = b.is_guard (i);
                while (i < b.width && b.get_bar (i) && b.is_guard (i) == guard) i++;
                int height = b.bar_height + (guard ? GUARD_EXTRA : 0);
                sb.append ("M%d %dh%dv%dh-%dz".printf (start + b.quiet_left, BAR_MARGIN, i - start, height, i - start));
            }
            sb.append ("\"/>\n");
            foreach (var run in b.runs) {
                if (run.text == "") continue;
                double center = b.quiet_left + (run.start + run.end) / 2.0;
                char[] buf = new char[double.DTOSTR_BUF_SIZE];
                sb.append ("<text x=\"%s\" y=\"%d\" font-family=\"monospace\" font-size=\"%d\" text-anchor=\"middle\" fill=\"#000000\">%s</text>\n".printf (
                    center.format (buf, "%.1f"), BAR_MARGIN + b.bar_height + TEXT_BASELINE, FONT_SIZE, Markup.escape_text (run.text)));
            }
            sb.append ("</svg>\n");
            return sb.str;
        }
    }
}
