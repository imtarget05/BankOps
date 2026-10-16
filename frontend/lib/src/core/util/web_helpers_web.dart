// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;

void promptPwaInstall() {
  try {
    js.context.callMethod('promptPwaInstall');
  } catch (_) {}
}

void openWebUrl(String url) {
  try {
    html.window.open(url, '_blank');
  } catch (_) {}
}

bool isPwaInstallSupported() {
  try {
    return js.context['isPwaInstallAvailable'] == true;
  } catch (_) {
    return false;
  }
}
