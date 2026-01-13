#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <map>

#include "win32_window.h"

// Forward declaration
class FlutterWindow;

// Global pointer to FlutterWindow for subclass proc callback
extern FlutterWindow* g_flutter_window;

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // Process pointer messages from subclassed Flutter view
  void ProcessPointerMessage(HWND hwnd, UINT const message, WPARAM const wparam, LPARAM const lparam);

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Method channel for pointer type communication
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> pointer_channel_;

  // Cache of pointer types (Windows pointer ID -> type)
  std::map<UINT32, UINT32> pointer_type_cache_;

  // Original window procedure for Flutter view (for subclassing)
  WNDPROC original_flutter_view_proc_ = nullptr;

  // Flutter view window handle
  HWND flutter_view_hwnd_ = nullptr;

  // Subclass the Flutter view window to intercept WM_POINTER messages
  void SubclassFlutterView();

  // Handle WM_POINTER messages and detect pen vs touch
  void HandlePointerMessage(UINT const message, WPARAM const wparam, LPARAM const lparam);

  // Send pointer type info to Dart
  void SendPointerTypeToDart(UINT32 pointerId, UINT32 pointerType, UINT32 pressure);
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
