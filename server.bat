@echo off
rem Starts the poker game server. Stop it with Ctrl+C or by closing this window;
rem everything is saved after every hand, so stopping is always safe.
rem Players connect to this PC's address on UDP port 7777 (forward it on the router).
rem Data (accounts, certificate, backups): %APPDATA%\Godot\app_userdata\Poker
set GODOT=C:\Godot_v4.6.1-stable_mono_win64\Godot_v4.6.1-stable_mono_win64_console.exe
"%GODOT%" --headless --path "%~dp0poker" -- --server
pause
