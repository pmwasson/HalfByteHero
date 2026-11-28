cd ..\build

::---------------------------------------------------------------------------
:: Convert images
::---------------------------------------------------------------------------
python3 ..\scripts\imageConvert.py ..\images\title.png title.png >  ..\build\title.asm  || exit
python3 ..\scripts\imageConvert.py --level ..\images\level0.png level0.png >  ..\build\level0.asm  || exit
python3 ..\scripts\imageConvert.py --level ..\images\level1.png level1.png >  ..\build\level1.asm  || exit
python3 ..\scripts\imageConvert.py --level ..\images\level2.png level2.png >  ..\build\level2.asm  || exit

::---------------------------------------------------------------------------
:: Compile code
::   Assemble twice: 1 to generate listing, 2 to generate object
::---------------------------------------------------------------------------

:: Half Byte Hero
ca65 -I ..\src -I ..\build -t apple2 ..\src\game.asm -l game.dis -o ..\build\game.o || exit
cl65 -I ..\src --asm-include-dir ..\build -t apple2 -u __EXEHDR__ ..\src\game.asm apple2.lib  -o hbh.apple2 -C ..\src\start2000.cfg || exit

::---------------------------------------------------------------------------
:: Build disk
::---------------------------------------------------------------------------

:: Start with a blank prodos disk
copy ..\disk\template_prodos.dsk hbh.dsk  || exit

ac-windows -as hbh.dsk hbh.system sys < hbh.apple2    || exit


:: Throw on basic
ac-windows -p   hbh.dsk basic.system sys < ..\disk\BASIC.SYSTEM  || exit

:: Copy results out of the build directory
copy hbh.dsk ..\disk || exit

::---------------------------------------------------------------------------
:: Test on emulator
::---------------------------------------------------------------------------

Applewin -no-printscreen-dlg -d1 hbh.dsk

