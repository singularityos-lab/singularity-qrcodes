project('singularity-qrcodes', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-qrcodes"', language: 'c')
subdir('po')

gtk_dep = dependency('gtk4', version: '>= 4.16')
gee_dep = dependency('gee-0.8')
json_dep = dependency('json-glib-1.0')
gio_dep = dependency('gio-2.0')
giounix_dep = dependency('gio-unix-2.0')
cairo_dep = dependency('cairo')
pixbuf_dep = dependency('gdk-pixbuf-2.0')
gst_dep = dependency('gstreamer-1.0')
gstapp_dep = dependency('gstreamer-app-1.0')
gstvideo_dep = dependency('gstreamer-video-1.0')
posix_dep = meson.get_compiler('vala').find_library('posix')
m_dep = meson.get_compiler('c').find_library('m', required: false)
zbar_dep = dependency('zbar', required: false)
if not zbar_dep.found() and not get_option('qr').disabled()
  if meson.get_compiler('c').links('int zbar_image_scanner_create(void); int main(void) { return zbar_image_scanner_create() == 0; }',
      args: ['-l:libzbar.so.0'], name: 'zbar runtime library')
    zbar_dep = declare_dependency(include_directories: include_directories('third_party/zbar'),
      link_args: ['-l:libzbar.so.0'])
  elif get_option('qr').enabled()
    error('ZBar was requested but neither its development files nor libzbar.so.0 were found')
  endif
endif

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

core_sources = files(
  'src/format.vala',
  'src/content.vala',
  'src/payload.vala',
)

encoder_sources = files(
  'src/barcode.vala',
  'src/render.vala',
)

vala_args = []
link_with = []
if zbar_dep.found()
  qr_bridge = static_library('qr-bridge', 'src/qr-bridge.c',
    dependencies: [dependency('glib-2.0'), zbar_dep])
  scan_sources = files('src/scan.vala')
  link_with += qr_bridge
  vala_args += ['--vapidir=' + meson.current_source_dir() / 'vapi', '--pkg=qrbridge']
else
  scan_sources = files('src/scan-missing.vala')
endif

executable('singularity-qrcodes',
  core_sources + encoder_sources + scan_sources + files(
    'src/history.vala',
    'src/batch.vala',
    'src/contacts.vala',
    'src/portal.vala',
    'src/network.vala',
    'src/camera.vala',
    'src/view.vala',
    'src/picker.vala',
    'src/window.vala',
    'src/search.vala',
    'src/app.vala',
  ),
  vala_args: vala_args,
  include_directories: include_directories('src'),
  link_with: link_with,
  dependencies: [gtk_dep, gee_dep, json_dep, gio_dep, giounix_dep, cairo_dep, pixbuf_dep, gst_dep, gstapp_dep, gstvideo_dep, posix_dep, m_dep, libsingularity_dep],
  install: true
)

plugin_dir = get_option('libdir') / 'singularity' / 'plugins' / 'qrcodes'
shared_module('qrcodes',
  core_sources + encoder_sources + files('src/network.vala', 'src/plugin/plugin.vala'),
  dependencies: [gtk_dep, gee_dep, gio_dep, giounix_dep, cairo_dep, m_dep, libsingularity_dep, dependency('libpeas-2')],
  install: true,
  install_dir: plugin_dir
)
install_data('data/qrcodes.plugin', install_dir: plugin_dir)

install_data('data/icons/hicolor/symbolic/apps/qrcodes-code-symbolic.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'symbolic' / 'apps'
)

install_data('data/dev.sinty.qrcodes.search.ini',
  rename: 'dev.sinty.qrcodes.ini',
  install_dir: get_option('datadir') / 'singularity' / 'search-providers'
)

install_data('data/dev.sinty.qrcodes.scan-image.ini',
  install_dir: get_option('datadir') / 'singularity' / 'files-actions'
)

service_conf = configuration_data()
service_conf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input: 'data/dev.sinty.qrcodes.service.in',
  output: 'dev.sinty.qrcodes.service',
  configuration: service_conf,
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)

install_data('data/dev.sinty.qrcodes.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data('data/dev.sinty.qrcodes.gschema.xml',
  install_dir: get_option('datadir') / 'glib-2.0' / 'schemas'
)

install_data('data/dev.sinty.qrcodes.json',
  install_dir: get_option('datadir') / 'singularity' / 'app-settings'
)

install_data('data/icons/dev.sinty.qrcodes.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)

fixtures = meson.current_source_dir() / 'tests' / 'fixtures'
core_deps = [gio_dep, gee_dep]

content_test = executable('content-test', core_sources + files('tests/content_test.vala'),
  dependencies: core_deps)
test('content', content_test)

payload_test = executable('payload-test', core_sources + files('tests/payload_test.vala'),
  dependencies: core_deps)
test('payload', payload_test)

render_test = executable('render-test', core_sources + encoder_sources + files('tests/render_test.vala'),
  dependencies: core_deps + [cairo_dep, m_dep, libsingularity_dep])
test('render', render_test)

barcode_test = executable('barcode-test', core_sources + encoder_sources + files('tests/barcode_test.vala'),
  dependencies: core_deps + [cairo_dep, m_dep, libsingularity_dep])
test('barcode', barcode_test)

contacts_test = executable('contacts-test', core_sources + files('src/contacts.vala', 'tests/contacts_test.vala'),
  dependencies: core_deps)
test('contacts', contacts_test, args: [fixtures])

batch_test = executable('batch-test', core_sources + files('src/batch.vala', 'tests/batch_test.vala'),
  dependencies: core_deps)
test('batch', batch_test)

history_test = executable('history-test', files('src/history.vala', 'tests/history_test.vala'),
  dependencies: core_deps + [json_dep, posix_dep])
test('history', history_test)

network_test = executable('network-test', core_sources + files('src/network.vala', 'tests/network_test.vala'),
  dependencies: core_deps)
test('network', network_test)

dbus_daemon = find_program('dbus-daemon', required: false)
if dbus_daemon.found()
  nm_test = executable('nm-test', core_sources + files('src/network.vala', 'tests/nm_test.vala'),
    dependencies: core_deps)
  test('nm', nm_test, timeout: 60)
endif

if zbar_dep.found()
  roundtrip_test = executable('roundtrip-test', core_sources + encoder_sources + scan_sources + files('src/batch.vala', 'tests/roundtrip_test.vala'),
    vala_args: vala_args,
    include_directories: include_directories('src'),
    link_with: link_with,
    dependencies: core_deps + [cairo_dep, m_dep, pixbuf_dep, gtk_dep, libsingularity_dep])
  test('roundtrip', roundtrip_test, args: [meson.current_build_dir()], timeout: 120)
endif
