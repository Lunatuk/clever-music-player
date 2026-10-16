#include "include/flutter_secure_storage_windows/flutter_secure_storage_windows_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <memory>

namespace {
// This application uses the Dart DPAPI backend exclusively. The upstream
// pre-4.x credential/AES migration channel is deliberately unavailable:
// no legacy files/credentials are read, rewritten or removed.
class DisabledLegacyStorage : public flutter::Plugin {
 public:
  explicit DisabledLegacyStorage(flutter::PluginRegistrarWindows* registrar)
      : channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "plugins.it_nomads.com/flutter_secure_storage",
            &flutter::StandardMethodCodec::GetInstance())) {
    channel_->SetMethodCallHandler([](const auto&, auto result) {
      result->NotImplemented();
    });
  }
 private:
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
}  // namespace

void FlutterSecureStorageWindowsPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  auto* windows_registrar = flutter::PluginRegistrarManager::GetInstance()
      ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar);
  windows_registrar->AddPlugin(std::make_unique<DisabledLegacyStorage>(windows_registrar));
}
