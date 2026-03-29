#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"

#include <connectivity_plus/connectivity_plus_windows_plugin.h>

// 自定义消息：延迟注册子窗口插件
#define WM_REGISTER_SUB_WINDOW_PLUGINS (WM_APP + 100)

static flutter::PluginRegistry* g_pending_registry = nullptr;
static HWND g_main_hwnd = nullptr;

// 测试：只注册 connectivity_plus（最轻量的插件）
static void RegisterPluginsForSubWindow(flutter::PluginRegistry* registry) {
  ConnectivityPlusWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ConnectivityPlusWindowsPlugin"));
}

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

  g_main_hwnd = GetHandle();

  // 子窗口创建回调：不在此处同步注册插件（会阻塞主窗口消息循环），
  // 而是通过 PostMessage 延迟到下一轮消息循环处理
  DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
    auto *flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController *>(controller);
    g_pending_registry = flutter_view_controller->engine();
    if (g_main_hwnd) {
      PostMessage(g_main_hwnd, WM_REGISTER_SUB_WINDOW_PLUGINS, 0, 0);
    }
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
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
    case WM_REGISTER_SUB_WINDOW_PLUGINS:
      if (g_pending_registry) {
        RegisterPluginsForSubWindow(g_pending_registry);
        g_pending_registry = nullptr;
      }
      return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
