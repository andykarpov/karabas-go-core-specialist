# Ядро Специалист для Karabas Go / Mini / Mini G

Ядро советских домашних компьютеров Специалист (1987) и Специалист-MX (1991) для плат семейства Karabas Go (Xilinx Spartan-6 XC6SLX25). Проверено на Mini G; на Go и Mini собирается, на платах не запускалось.

Что работает: модели Original, MX и MX²; КР580ВМ80А или Z80 на 2 и 4 МГц; SDOS на образе SD; AY; мышь; физический дисковод на Go (не проверен); экран 384 × 256 с цветом обеих моделей; клавиатура 12 × 6; бипер, ВИ53 MX; страницы памяти и RAM-диск MX, RAMFOS; программы `.rks` с автозапуском; два дисковода MX (`.odi`), чтение и запись; 800 × 600 и 720 × 576; лента (не проверена).

- [docs/GUIDE.md](docs/GUIDE.md): **как пользоваться**: что положить на карту, клавиши, OSD.
- [docs/PLAN.md](docs/PLAN.md): исследование, решения, фазы.
- [docs/HARDWARE.md](docs/HARDWARE.md): карты памяти и порты.
- [docs/BACKLOG.md](docs/BACKLOG.md): открытые вопросы.

Клонировать с `--recursive`: модули плат лежат в сабмодуле `modules/` ([karabas-go-modules](https://github.com/andykarpov/karabas-go-modules)). Для `src/make_core.py` рядом нужен [karabas-go-tools](https://github.com/andykarpov/karabas-go-tools).

Лицензия GPL v3 (`LICENSE`). Сторонний код: vm80a (1801BM1, CC-BY 3.0), T80 (Daniel Wallner, BSD), jt49 (Jose Tejada, GPL v3), vg93 (FD1793_1818VG93, через core-profi; у исходника нет файла лицензии, только для физического дисковода Go), KF8253 (kitune-san, MIT), wd1793 (В. Славинский, Sorgelig, GPL v2 или новее, через core-msx и core-orion128). ПЗУ Монитора-2 и RAMFOS из комплекта Emu80. Эталоном поведения служили [Emu80](https://github.com/vpyk/emu80v4) и ядро [Specialist_MiSTer](https://github.com/MiSTer-devel/Specialist_MiSTer).
