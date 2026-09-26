#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string>
#include <vector>

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR arguments, int) {
  std::vector<wchar_t> buffer(32768);
  const DWORD length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
  if (!length || length >= buffer.size()) return 1;
  const std::wstring path(buffer.data(), length);
  const std::wstring runtime = path.substr(0, path.find_last_of(L"\\/")) + L"\\runtime";
  const std::wstring executable = runtime + L"\\simple_live_app.exe";
  // Windows supplies the unparsed argument tail: preserve quotes and Unicode.
  std::wstring command = L"\"" + executable + L"\"";
  if (arguments && *arguments) command += std::wstring(L" ") + arguments;
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  PROCESS_INFORMATION process{};
  if (!CreateProcessW(executable.c_str(), command.data(), nullptr, nullptr, FALSE,
                      0, nullptr, runtime.c_str(), &startup, &process)) {
    const std::wstring message = L"无法启动 Simple Live（错误 " + std::to_wstring(GetLastError()) +
        L"）。请完整解压便携包，并保留 runtime 文件夹。";
    MessageBoxW(nullptr, message.c_str(), L"Simple Live", MB_OK | MB_ICONERROR);
    return 1;
  }
  CloseHandle(process.hThread);
  // Keeping this small launcher alive lets scripts observe the application's exit.
  WaitForSingleObject(process.hProcess, INFINITE);
  DWORD exit_code = 1;
  GetExitCodeProcess(process.hProcess, &exit_code);
  CloseHandle(process.hProcess);
  return static_cast<int>(exit_code);
}
