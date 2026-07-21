import '../entities/browser_tab.dart';

abstract class BrowserRepository {
  List<BrowserTab> getTabs();
  BrowserTab? getActiveTab();
  BrowserTab createTab({String url = '', bool incognito = false});
  void removeTab(int tabId);
  void setActiveTab(int tabId);
  void updateTab(int tabId, {String? url, String? title});
}
