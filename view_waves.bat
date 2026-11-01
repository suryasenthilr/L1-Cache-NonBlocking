@echo off
cd /d "%~dp0"
call "C:\Users\surya\.oss-cad-suite\oss-cad-suite\environment.bat"
start "" gtkwave "sim\apex_cache.vcd" "sim\apex_cache.gtkw"
