#include "flutter_window.h"

#include <optional>
#include <iostream>
#include <fstream>
#include <ctime>
#include <sstream>
#include <iomanip>

#include "flutter/generated_plugin_registrant.h"

// File-based logging for debugging (std::cout doesn't work in Windows GUI apps)
static std::ofstream g_log_file;
static bool g_log_initialized = false;

static void InitLogFile() {
    if (g_log_initialized) return;
    g_log_initialized = true;

    // Log to user's desktop for easy access
    char* userProfile = nullptr;
    size_t len = 0;
    _dupenv_s(&userProfile, &len, "USERPROFILE");
    if (userProfile) {
        std::string logPath = std::string(userProfile) + "\\Desktop\\winote_native_log.txt";
        g_log_file.open(logPath, std::ios::out | std::ios::trunc);
        free(userProfile);
    }
}

static void LogToFile(const std::string& message) {
    InitLogFile();
    if (g_log_file.is_open()) {
        auto now = std::chrono::system_clock::now();
        auto time = std::chrono::system_clock::to_time_t(now);
        auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            now.time_since_epoch()) % 1000;

        std::tm tm_buf;
        localtime_s(&tm_buf, &time);

        g_log_file << "[" << std::put_time(&tm_buf, "%H:%M:%S")
                   << "." << std::setfill('0') << std::setw(3) << ms.count() << "] "
                   << message << std::endl;
        g_log_file.flush();
    }
}

// Windows Pointer Input Message definitions
#ifndef WM_POINTERDOWN
#define WM_POINTERDOWN 0x0246
#endif
#ifndef WM_POINTERUP
#define WM_POINTERUP 0x0247
#endif
#ifndef WM_POINTERUPDATE
#define WM_POINTERUPDATE 0x0245
#endif
#ifndef WM_POINTERENTER
#define WM_POINTERENTER 0x0249
#endif
#ifndef WM_POINTERLEAVE
#define WM_POINTERLEAVE 0x024A
#endif

// Pointer type constants
#ifndef PT_POINTER
#define PT_POINTER 1
#define PT_TOUCH 2
#define PT_PEN 3
#define PT_MOUSE 4
#define PT_TOUCHPAD 5
#endif

// Macro to extract pointer ID from wParam
#ifndef GET_POINTERID_WPARAM
#define GET_POINTERID_WPARAM(wParam) (LOWORD(wParam))
#endif

// Function pointer types for dynamic loading
typedef BOOL(WINAPI* GetPointerTypeFunc)(UINT32 pointerId, POINTER_INPUT_TYPE* pointerType);
typedef BOOL(WINAPI* GetPointerPenInfoFunc)(UINT32 pointerId, POINTER_PEN_INFO* penInfo);

// Global function pointers (loaded once)
static GetPointerTypeFunc g_GetPointerType = nullptr;
static GetPointerPenInfoFunc g_GetPointerPenInfo = nullptr;
static bool g_pointer_api_initialized = false;

// Global pointer to FlutterWindow for subclass callback
FlutterWindow* g_flutter_window = nullptr;

// Original WndProc for Flutter view (stored globally for subclass)
static WNDPROC g_original_flutter_view_proc = nullptr;

// Subclass window procedure for Flutter view
static LRESULT CALLBACK FlutterViewSubclassProc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
    // Intercept WM_POINTER messages
    switch (message) {
        case WM_POINTERDOWN:
            LogToFile("FlutterViewSubclassProc: WM_POINTERDOWN received");
            if (g_flutter_window) {
                g_flutter_window->ProcessPointerMessage(hwnd, message, wparam, lparam);
            }
            break;
        case WM_POINTERUP:
            LogToFile("FlutterViewSubclassProc: WM_POINTERUP received");
            if (g_flutter_window) {
                g_flutter_window->ProcessPointerMessage(hwnd, message, wparam, lparam);
            }
            break;
        case WM_POINTERUPDATE:
            // Don't log every update (too noisy), just process
            if (g_flutter_window) {
                g_flutter_window->ProcessPointerMessage(hwnd, message, wparam, lparam);
            }
            break;
        case WM_POINTERENTER:
            LogToFile("FlutterViewSubclassProc: WM_POINTERENTER received");
            if (g_flutter_window) {
                g_flutter_window->ProcessPointerMessage(hwnd, message, wparam, lparam);
            }
            break;
        case WM_POINTERLEAVE:
            LogToFile("FlutterViewSubclassProc: WM_POINTERLEAVE received");
            if (g_flutter_window) {
                g_flutter_window->ProcessPointerMessage(hwnd, message, wparam, lparam);
            }
            break;
    }

    // Call original window procedure
    if (g_original_flutter_view_proc) {
        return CallWindowProc(g_original_flutter_view_proc, hwnd, message, wparam, lparam);
    }
    return DefWindowProc(hwnd, message, wparam, lparam);
}

// Initialize pointer API functions
static void InitializePointerApi() {
    if (g_pointer_api_initialized) return;
    g_pointer_api_initialized = true;

    LogToFile("InitializePointerApi: Starting...");

    HMODULE user32 = GetModuleHandleA("user32.dll");
    if (user32) {
        g_GetPointerType = (GetPointerTypeFunc)GetProcAddress(user32, "GetPointerType");
        g_GetPointerPenInfo = (GetPointerPenInfoFunc)GetProcAddress(user32, "GetPointerPenInfo");

        if (g_GetPointerType && g_GetPointerPenInfo) {
            LogToFile("InitializePointerApi: Pointer API initialized successfully");
        } else {
            LogToFile("InitializePointerApi: Pointer API not available");
        }
    } else {
        LogToFile("InitializePointerApi: Failed to get user32.dll handle");
    }
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {
    InitializePointerApi();
    g_flutter_window = this;
}

FlutterWindow::~FlutterWindow() {
    g_flutter_window = nullptr;
}

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

  // Setup MethodChannel for pointer type communication
  pointer_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "winote/pointer_type",
      &flutter::StandardMethodCodec::GetInstance());

  LogToFile("OnCreate: MethodChannel 'winote/pointer_type' created");

  // Get Flutter view window handle and subclass it
  flutter_view_hwnd_ = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(flutter_view_hwnd_);

  // Subclass the Flutter view to intercept WM_POINTER messages
  SubclassFlutterView();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::SubclassFlutterView() {
    if (!flutter_view_hwnd_) {
        LogToFile("SubclassFlutterView: ERROR - Flutter view HWND is null, cannot subclass");
        return;
    }

    std::ostringstream oss;
    oss << "SubclassFlutterView: Attempting to subclass HWND " << flutter_view_hwnd_;
    LogToFile(oss.str());

    // Subclass the Flutter view window
    g_original_flutter_view_proc = (WNDPROC)SetWindowLongPtr(
        flutter_view_hwnd_,
        GWLP_WNDPROC,
        (LONG_PTR)FlutterViewSubclassProc
    );

    if (g_original_flutter_view_proc) {
        original_flutter_view_proc_ = g_original_flutter_view_proc;
        std::ostringstream oss2;
        oss2 << "SubclassFlutterView: SUCCESS - Flutter view subclassed (HWND: " << flutter_view_hwnd_
             << ", Original proc: " << g_original_flutter_view_proc << ")";
        LogToFile(oss2.str());
    } else {
        std::ostringstream oss2;
        oss2 << "SubclassFlutterView: FAILED - Error code: " << GetLastError();
        LogToFile(oss2.str());
    }
}

void FlutterWindow::ProcessPointerMessage(HWND hwnd, UINT const message, WPARAM const wparam, LPARAM const lparam) {
    HandlePointerMessage(message, wparam, lparam);
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
  // Handle WM_POINTER messages BEFORE Flutter processes them
  // This allows us to detect pen vs touch and inform Dart
  switch (message) {
    case WM_POINTERDOWN:
    case WM_POINTERUP:
    case WM_POINTERUPDATE:
    case WM_POINTERENTER:
      HandlePointerMessage(message, wparam, lparam);
      break;
    case WM_POINTERLEAVE: {
      // Clean up cache when pointer leaves
      UINT32 pointerId = GET_POINTERID_WPARAM(wparam);
      pointer_type_cache_.erase(pointerId);
      break;
    }
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

void FlutterWindow::HandlePointerMessage(UINT const message, WPARAM const wparam, LPARAM const lparam) {
    if (!g_GetPointerType) {
        LogToFile("HandlePointerMessage: g_GetPointerType is null!");
        return;
    }

    UINT32 pointerId = GET_POINTERID_WPARAM(wparam);
    POINTER_INPUT_TYPE pointerType = PT_POINTER;

    if (g_GetPointerType(pointerId, &pointerType)) {
        // Cache the pointer type
        pointer_type_cache_[pointerId] = pointerType;

        UINT32 pressure = 0;

        // Get pen-specific info if it's a pen
        if (pointerType == PT_PEN && g_GetPointerPenInfo) {
            POINTER_PEN_INFO penInfo = {};
            if (g_GetPointerPenInfo(pointerId, &penInfo)) {
                pressure = penInfo.pressure;  // 0-1024
            }
        }

        // Only send on DOWN events to reduce traffic
        if (message == WM_POINTERDOWN) {
            const char* typeStr = (pointerType == PT_PEN) ? "PEN" :
                                  (pointerType == PT_TOUCH) ? "TOUCH" :
                                  (pointerType == PT_MOUSE) ? "MOUSE" : "OTHER";

            std::ostringstream oss;
            oss << "HandlePointerMessage: Pointer " << pointerId << " type: " << typeStr
                << " (value: " << pointerType << "), pressure: " << pressure;
            LogToFile(oss.str());

            SendPointerTypeToDart(pointerId, pointerType, pressure);
        }
    } else {
        std::ostringstream oss;
        oss << "HandlePointerMessage: GetPointerType failed for pointer " << pointerId
            << ", error: " << GetLastError();
        LogToFile(oss.str());
    }
}

void FlutterWindow::SendPointerTypeToDart(UINT32 pointerId, UINT32 pointerType, UINT32 pressure) {
    if (!pointer_channel_) {
        LogToFile("SendPointerTypeToDart: pointer_channel_ is null!");
        return;
    }

    flutter::EncodableMap args;
    args[flutter::EncodableValue("pointerId")] = flutter::EncodableValue(static_cast<int>(pointerId));
    args[flutter::EncodableValue("pointerType")] = flutter::EncodableValue(static_cast<int>(pointerType));
    args[flutter::EncodableValue("pressure")] = flutter::EncodableValue(static_cast<int>(pressure));

    std::ostringstream oss;
    oss << "SendPointerTypeToDart: Sending pointer " << pointerId
        << ", type " << pointerType << ", pressure " << pressure << " to Dart";
    LogToFile(oss.str());

    pointer_channel_->InvokeMethod(
        "onPointerTypeDetected",
        std::make_unique<flutter::EncodableValue>(args)
    );
}
