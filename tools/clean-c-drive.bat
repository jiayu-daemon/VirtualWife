@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul 2>&1
title C 盘清理助手

rem ============================================================
rem  Windows C 盘清理脚本
rem  设计原则：
rem    1. 只清理系统/用户"临时垃圾"，绝不碰文档、桌面、下载、浏览器数据
rem    2. 默认菜单里先给"预览模式"，确认无误再真正删除
rem    3. 所有操作写入日志，便于回溯
rem  使用方法：右键 -> 以管理员身份运行（脚本也会自动尝试提权）
rem ============================================================

set "SCRIPT=%~f0"
set "DRYRUN=0"
set "YESALL=0"

rem ---------- 检查系统盘 ----------
if /i not "%SystemDrive%"=="C:" (
    echo.
    echo  [!] 当前系统盘不是 C: ，脚本仍然按 C: 处理，请注意确认。
    echo.
)

rem ---------- 管理员权限 ----------
net session >nul 2>&1
if errorlevel 1 (
    echo.
    echo  [!] 当前不是管理员权限，正在尝试以管理员身份重新启动...
    powershell -NoProfile -Command "Start-Process -FilePath '%SCRIPT%' -Verb RunAs" >nul 2>&1
    if errorlevel 1 (
        echo  [!] 提权失败，请手动右键选择"以管理员身份运行"。
        pause
    )
    exit /b
)

rem ---------- 日志文件 ----------
set "LOGDIR=%~dp0logs"
if not exist "%LOGDIR%" md "%LOGDIR%" >nul 2>&1
if not exist "%LOGDIR%" set "LOGDIR=%USERPROFILE%"
for /f "delims=" %%i in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss" 2^>nul') do set "TS=%%i"
if not defined TS set "TS=manual"
set "LOG=%LOGDIR%\c_clean_%TS%.log"
call :Log "===== 清理任务开始 ====="

:MAIN
cls
call :Banner
call :FreeSpace "清理前"
set "GB_BEFORE=!FREEGB!"
echo.
echo   请选择操作：
echo     [1] 预览模式   （只统计可清理的大小，不删除任何文件）
echo     [2] 安全清理   （临时文件、回收站、缩略图缓存、崩溃转储）
echo     [3] 深度清理   （安全清理 + 更新缓存 + 预读取 + 旧系统文件等）
echo     [4] 自定义清理 （逐项询问，最可控）
echo     [5] 组件存储清理（DISM，耗时较长，适合长期未清理的机器）
echo     [0] 退出
echo.
choice /c 123450 /n /m "  请输入序号: "
if errorlevel 6 goto :QUIT
if errorlevel 5 goto :DISMCLEAN
if errorlevel 4 goto :CUSTOM
if errorlevel 3 goto :DEEP
if errorlevel 2 goto :SAFE
if errorlevel 1 goto :PREVIEW

rem ============================================================
rem  预览模式
rem ============================================================
:PREVIEW
set "DRYRUN=1"
set "YESALL=1"
echo.
echo  ---- 以下为可清理项目的大小估算（不会删除文件）----
call :RunSafe
call :RunDeep
set "DRYRUN=0"
set "YESALL=0"
call :FreeSpace "清理前"
echo.
pause
goto :MAIN

rem ============================================================
rem  安全清理
rem ============================================================
:SAFE
set "DRYRUN=0"
set "YESALL=0"
call :Confirm "确认执行安全清理（只清临时垃圾，不影响个人文件）?" || goto :MAIN
set "YESALL=1"
call :RunSafe
set "YESALL=0"
call :Finish
goto :MAIN

rem ============================================================
rem  深度清理
rem ============================================================
:DEEP
set "DRYRUN=0"
set "YESALL=0"
echo.
echo  [提示] 深度清理包含：Windows 更新缓存、预读取文件、传递优化缓存、
echo         旧系统目录(C:\Windows.old)。其中 Windows.old 删除后不可恢复。
call :Confirm "确认执行深度清理?" || goto :MAIN
set "YESALL=1"
call :RunSafe
call :RunDeep
set "YESALL=0"
call :Finish
goto :MAIN

rem ============================================================
rem  自定义清理
rem ============================================================
:CUSTOM
set "DRYRUN=0"
set "YESALL=0"
echo.
echo  ---- 自定义清理：逐项选择 Y 或 N ----
call :RunSafe
call :RunDeep
call :Finish
goto :MAIN

rem ============================================================
rem  DISM 组件存储清理
rem ============================================================
:DISMCLEAN
echo.
echo  [说明] 该操作会清理 WinSxS 中过期组件，通常可释放 2-8 GB，
echo         耗时 10-30 分钟，期间请勿断电。
call :Confirm "开始 DISM 组件清理?" || goto :MAIN
echo.
DISM /Online /Cleanup-Image /StartComponentCleanup
call :Log "[执行] DISM StartComponentCleanup"
call :Finish
pause
goto :MAIN

rem ============================================================
rem  子过程：安全清理项目
rem ============================================================
:RunSafe
echo.
echo  -- 临时文件 --
call :CleanDir "用户临时文件" "%TEMP%"
call :CleanDir "系统临时文件" "%SystemRoot%\Temp"
call :CleanDir "Windows 升级残留(\$WINDOWS.~BT)" "%SystemDrive%\$WINDOWS.~BT"
call :CleanDir "Windows 升级残留(\$WINDOWS.~WS)" "%SystemDrive%\$WINDOWS.~WS"
call :CleanDir "崩溃转储(CrashDumps)" "%LOCALAPPDATA%\CrashDumps"
call :CleanDir "系统小型转储(Minidump)" "%SystemRoot%\Minidump"
call :CleanDir "内核报告(LiveKernelReports)" "%SystemRoot%\LiveKernelReports"
echo.
echo  -- 回收站 / 缩略图 --
call :EmptyRecycleBin
call :CleanThumbs
exit /b 0

rem ============================================================
rem  子过程：深度清理项目
rem ============================================================
:RunDeep
echo.
echo  -- 更新缓存 / 预读取 / 传递优化 --
call :CleanWindowsUpdateCache
call :CleanDir "预读取文件(Prefetch)" "%SystemRoot%\Prefetch"
call :CleanDir "传递优化缓存" "%SystemRoot%\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization"
call :CleanDir "更新日志(WindowsUpdate)" "%SystemRoot%\Logs\WindowsUpdate"
call :CleanDir "组件安装日志(CBS)" "%SystemRoot%\Logs\CBS"
echo.
echo  -- 旧系统文件 --
call :CleanWindowsOld
exit /b 0

rem ============================================================
rem  子过程：清理单个目录
rem    %1 = 显示名称  %2 = 路径
rem ============================================================
:CleanDir
set "CN=%~1"
set "CP=%~2"
if not exist "%CP%" (
    echo    [-] %CN%：路径不存在，跳过
    exit /b 0
)
if "%CP%"=="%SystemDrive%\" (
    echo    [!] 拒绝删除磁盘根目录
    exit /b 1
)
set "SIZEMB=0"
for /f "usebackq delims=" %%S in (`powershell -NoProfile -Command "try{$s=(Get-ChildItem -LiteralPath '%CP%' -Recurse -Force -File -ErrorAction SilentlyContinue ^| Measure-Object -Property Length -Sum).Sum; if($s){[math]::Round($s/1MB,1)}else{0}}catch{0}" 2^>nul`) do set "SIZEMB=%%S"
if "%DRYRUN%"=="1" (
    echo    [预览] %CN%：约 %SIZEMB% MB
    exit /b 0
)
call :Confirm "%CN% 约 %SIZEMB% MB，清理?" || exit /b 1
del /f /q /s "%CP%\*.*" >nul 2>&1
for /d %%D in ("%CP%\*") do rd /s /q "%%D" >nul 2>&1
echo    [完成] %CN%：释放约 %SIZEMB% MB
call :Log "[完成] %CN% 释放约 %SIZEMB% MB"
exit /b 0

rem ============================================================
rem  子过程：清空回收站
rem ============================================================
:EmptyRecycleBin
if "%DRYRUN%"=="1" (
    echo    [预览] 回收站：将被清空
    exit /b 0
)
call :Confirm "清空回收站（不可恢复）?" || exit /b 1
powershell -NoProfile -Command "Clear-RecycleBin -Force -ErrorAction SilentlyContinue" >nul 2>&1
echo    [完成] 回收站已清空
call :Log "[完成] 回收站已清空"
exit /b 0

rem ============================================================
rem  子过程：清理缩略图缓存（部分文件被资源管理器占用，忽略失败）
rem ============================================================
:CleanThumbs
set "TH=%LOCALAPPDATA%\Microsoft\Windows\Explorer"
if not exist "%TH%" exit /b 0
if "%DRYRUN%"=="1" (
    echo    [预览] 缩略图缓存：仅清理未被占用的缓存文件
    exit /b 0
)
call :Confirm "清理缩略图缓存（部分文件占用会跳过）?" || exit /b 1
del /f /q "%TH%\thumbcache_*.db" >nul 2>&1
del /f /q "%TH%\iconcache_*.db" >nul 2>&1
echo    [完成] 缩略图缓存已处理（占用中的文件将在重启后释放）
call :Log "[完成] 缩略图缓存"
exit /b 0

rem ============================================================
rem  子过程：Windows 更新下载缓存
rem ============================================================
:CleanWindowsUpdateCache
set "CP=%SystemRoot%\SoftwareDistribution\Download"
if not exist "%CP%" (
    echo    [-] Windows 更新缓存：路径不存在，跳过
    exit /b 0
)
if "%DRYRUN%"=="1" (
    set "SIZEMB=0"
    for /f "usebackq delims=" %%S in (`powershell -NoProfile -Command "try{$s=(Get-ChildItem -LiteralPath '%CP%' -Recurse -Force -File -ErrorAction SilentlyContinue ^| Measure-Object -Property Length -Sum).Sum; if($s){[math]::Round($s/1MB,1)}else{0}}catch{0}" 2^>nul`) do set "SIZEMB=%%S"
    echo    [预览] Windows 更新缓存：约 !SIZEMB! MB
    exit /b 0
)
call :Confirm "清理 Windows 更新下载缓存（会临时停止更新服务）?" || exit /b 1
net stop wuauserv >nul 2>&1
net stop bits >nul 2>&1
del /f /q /s "%CP%\*.*" >nul 2>&1
for /d %%D in ("%CP%\*") do rd /s /q "%%D" >nul 2>&1
net start wuauserv >nul 2>&1
net start bits >nul 2>&1
echo    [完成] Windows 更新缓存已清理，更新服务已恢复
call :Log "[完成] Windows 更新缓存"
exit /b 0

rem ============================================================
rem  子过程：删除 Windows.old（旧系统，不可恢复）
rem ============================================================
:CleanWindowsOld
set "CP=%SystemDrive%\Windows.old"
if not exist "%CP%" (
    echo    [-] Windows.old：不存在，跳过
    exit /b 0
)
if "%DRYRUN%"=="1" (
    echo    [预览] Windows.old：将被整个删除
    exit /b 0
)
call :Confirm "删除 C:\Windows.old（旧系统备份，删除后无法回退系统）?" || exit /b 1
echo    正在获取目录权限，请稍候...
takeown /f "%CP%" /r /d y >nul 2>&1
icacls "%CP%" /grant *S-1-5-32-544:F /t /c /q >nul 2>&1
rd /s /q "%CP%" >nul 2>&1
if exist "%CP%" (
    echo    [!] 删除未完全成功，请改用：设置 ^> 系统 ^> 存储 ^> 临时文件 清理
    call :Log "[失败] Windows.old"
) else (
    echo    [完成] Windows.old 已删除
    call :Log "[完成] Windows.old"
)
exit /b 0

rem ============================================================
rem  子过程：确认提示（YESALL=1 时自动通过）
rem ============================================================
:Confirm
if "%YESALL%"=="1" exit /b 0
echo.
choice /c YN /n /m "    %~1 [Y=执行 / N=跳过] "
if errorlevel 2 exit /b 1
exit /b 0

rem ============================================================
rem  子过程：显示 C 盘可用空间
rem ============================================================
:FreeSpace
set "FREEGB=?"
for /f "usebackq delims=" %%F in (`powershell -NoProfile -Command "[math]::Round((Get-PSDrive -Name C).Free/1GB,2)" 2^>nul`) do set "FREEGB=%%F"
echo  C 盘可用空间（%~1）: !FREEGB! GB
exit /b 0

rem ============================================================
rem  子过程：写日志
rem ============================================================
:Log
>>"%LOG%" echo [%date% %time%] %~1
exit /b 0

rem ============================================================
rem  子过程：结束汇总
rem ============================================================
:Finish
echo.
call :FreeSpace "清理后"
if not "!FREEGB!"=="?" if not "!GB_BEFORE!"=="?" (
    set "DELTA=0"
    for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "[math]::Round((!FREEGB! - !GB_BEFORE!),2)" 2^>nul`) do set "DELTA=%%D"
    echo  本次释放（估算）: !DELTA! GB
)
echo  提示：部分被占用的文件需重启后才能完全释放。
echo  日志文件：%LOG%
call :Log "===== 清理任务结束 ====="
echo.
pause
exit /b 0

rem ============================================================
:Banner
echo ============================================================
echo                 Windows C 盘清理助手
echo ============================================================
echo  本脚本只清理系统临时垃圾，不会删除：
echo    个人文档 / 桌面 / 下载 / 图片 / 浏览器书签与密码 / 已安装软件
exit /b 0

:QUIT
call :Log "===== 用户退出 ====="
echo.
echo  已退出，未做任何修改的操作。
timeout /t 2 >nul
exit /b 0
