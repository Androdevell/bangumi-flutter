#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shobjidl.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  ::SetCurrentProcessExplicitAppUserModelID(L"Bangumi.Irena.Desktop");

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  // One instance per desktop session. Dart validates every bounded link again.
  HANDLE instance_mutex = CreateMutexW(nullptr, FALSE, L"Local\\Bangumi.Irena.Desktop.Instance");
  if (instance_mutex && GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing = FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"Bangumi");
    if (existing) {
      auto args = GetCommandLineArguments();
      if (!args.empty() && args[0].size() <= 8192) {
        COPYDATASTRUCT data{};
        data.dwData = 0x42474d;
        data.cbData = static_cast<DWORD>(args[0].size() + 1);
        data.lpData = const_cast<char*>(args[0].c_str());
        DWORD_PTR result = 0;
        SendMessageTimeoutW(existing, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG, 2000, &result);
      }
      ShowWindow(existing, SW_RESTORE);
      SetForegroundWindow(existing);
      CloseHandle(instance_mutex);
      CoUninitialize();
      return EXIT_SUCCESS;
    }
  }

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Bangumi", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (instance_mutex) CloseHandle(instance_mutex);
  return EXIT_SUCCESS;
}
