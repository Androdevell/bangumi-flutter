#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr char kAppIconChannel[] = "com.bgm.irena/app-icon";

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  link_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "com.bgm.irena/links", &flutter::StandardMethodCodec::GetInstance());
  app_icon_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kAppIconChannel,
          &flutter::StandardMethodCodec::GetInstance());
  app_icon_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() != "setAppIcon") {
          result->NotImplemented();
          return;
        }
        bool anime = false;
        const auto* arguments = std::get_if<flutter::EncodableMap>(
            call.arguments());
        if (arguments != nullptr) {
          const auto entry = arguments->find(flutter::EncodableValue("style"));
          if (entry != arguments->end()) {
            const auto* style = std::get_if<std::string>(&entry->second);
            anime = style != nullptr && *style == "anime";
          }
        }
        result->Success(flutter::EncodableValue(SetAppIcon(anime)));
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  link_channel_.reset();
  app_icon_channel_.reset();
  ReleaseCustomIcons();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

bool FlutterWindow::SetAppIcon(bool anime) {
  HICON big_icon = nullptr;
  HICON small_icon = nullptr;
  const HINSTANCE instance = GetModuleHandle(nullptr);
  const int resource_id = anime ? IDI_ANIME_ICON : IDI_APP_ICON;
  big_icon = reinterpret_cast<HICON>(LoadImageW(
      instance, MAKEINTRESOURCEW(resource_id), IMAGE_ICON,
      GetSystemMetrics(SM_CXICON), GetSystemMetrics(SM_CYICON), LR_SHARED));
  small_icon = reinterpret_cast<HICON>(LoadImageW(
      instance, MAKEINTRESOURCEW(resource_id), IMAGE_ICON,
      GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), LR_SHARED));
  if (big_icon == nullptr || small_icon == nullptr) return false;

  SendMessage(GetHandle(), WM_SETICON, ICON_BIG,
              reinterpret_cast<LPARAM>(big_icon));
  SendMessage(GetHandle(), WM_SETICON, ICON_SMALL,
              reinterpret_cast<LPARAM>(small_icon));
  ReleaseCustomIcons();
  return true;
}

void FlutterWindow::ReleaseCustomIcons() {
  if (custom_icon_big_ != nullptr) {
    DestroyIcon(custom_icon_big_);
    custom_icon_big_ = nullptr;
  }
  if (custom_icon_small_ != nullptr) {
    DestroyIcon(custom_icon_small_);
    custom_icon_small_ = nullptr;
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_COPYDATA && link_channel_ && lparam) {
    const auto* data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
    if (data->dwData == 0x42474d && data->lpData && data->cbData > 1 && data->cbData <= 8193) {
      const char* text = static_cast<const char*>(data->lpData);
      if (text[data->cbData - 1] == '\0') {
        link_channel_->InvokeMethod("link", std::make_unique<flutter::EncodableValue>(std::string(text, data->cbData - 1)));
        return TRUE;
      }
    }
    return FALSE;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
