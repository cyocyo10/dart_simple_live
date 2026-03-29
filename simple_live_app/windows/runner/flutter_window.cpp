#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"

#include <connectivity_plus/connectivity_plus_windows_plugin.h>
#include <media_kit_libs_windows_video/media_kit_libs_windows_video_plugin_c_api.h>
#include <media_kit_video/media_kit_video_plugin_c_api.h>
#include <volume_controller/volume_controller_plugin_c_api.h>
#include <screen_brightness_windows/screen_brightness_windows_plugin.h>

// 自定义消息：延迟注册子窗口插件
#define WM_REGISTER_SUB_WINDOW_PLUGINS (WM_APP + 100)

static flutter::PluginRegistry* g_pending_registry = nullptr;
static HWND g_main_hwnd = nullptr;
// 保存主窗口被 MediaKitVideoPlugin 子类化之前的原始 WNDPROC
static WNDPROC g_main_original_wndproc = nullptr;

// 子窗口需要的插件：视频播放 + 音量 + 亮度 + 网络状态
// 不注册 window_manager（会覆盖主窗口的静态 channel）
static void RegisterPluginsForSubWindow(flutter::PluginRegistry* registry) {
  MediaKitLibsWindowsVideoPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("MediaKitLibsWindowsVideoPluginCApi"));
  MediaKitVideoPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("MediaKitVideoPluginCApi"));
  VolumeControllerPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("VolumeControllerPluginCApi"));
  ScreenBrightnessWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ScreenBrightnessWindowsPlugin"));
  ConnectivityPlusWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("ConnectivityPlusWindowsPlugin"));

  // 关键修复：MediaKitVideoPlugin 的 RegisterWithRegistrar 内部用
  // SetWindowLongPtr 子类化窗口，且使用 static instance_ 单例指针。
  // 子窗口注册后 instance_ 被覆盖为子窗口实例，导致主窗口的
  // WindowProcDelegate 通过错误的 original_window_proc_ 路由消息 → 锁死。
  // 修复：将主窗口的 WNDPROC 恢复为 MediaKitVideoPlugin 子类化之前的
  // 原始 Flutter 处理函数，绕过被污染的 WindowProcDelegate 链。
  if (g_main_hwnd && g_main_original_wndproc) {
    SetWindowLongPtr(g_main_hwnd, GWLP_WNDPROC,
                     reinterpret_cast<LONG_PTR>(g_main_original_wndproc));
  }
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
  // 保存 RegisterPlugins 前的 WNDPROC（Flutter 原始处理函数）。
  // MediaKitVideoPlugin 会在 RegisterPlugins 中用 SetWindowLongPtr 子类化
  // 主窗口。后续子窗口注册时需用此值恢复主窗口的 WNDPROC。
  g_main_hwnd = GetHandle();
  g_main_original_wndproc = reinterpret_cast<WNDPROC>(
      GetWindowLongPtr(g_main_hwnd, GWLP_WNDPROC));

  RegisterPlugins(flutter_controller_->engine());

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
