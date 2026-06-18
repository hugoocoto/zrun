.PHONY: all raylib desktop install

all: raylib
	zig build 
	./zig-out/bin/zrun

raylib: ./raylib-6.0_linux_amd64/include/raylib.h

raylib-6.0_linux_amd64/include/raylib.h: raylib-6.0_linux_amd64.tar.gz
	tar -xf raylib-6.0_linux_amd64.tar.gz

raylib-6.0_linux_amd64.tar.gz:
	curl -L -O https://github.com/raysan5/raylib/releases/download/6.0/raylib-6.0_linux_amd64.tar.gz 

desktop: zrun.desktop

zrun.desktop:
	echo "[Desktop Entry]" > $@
	echo "Version=1.0" >> $@
	echo "Name=zrun" >> $@
	echo "" >> $@
	echo "Exec=$(PWD)/zig-out/bin/zrun" >> $@
	echo "NoDisplay=true" >> $@
	echo "Terminal=false" >> $@
	echo "Icon=$(PWD)/zrun_icon.png" >> $@
	echo "Type=Application" >> $@

install: desktop
	mkdir -p $(HOME)/.local/bin
	ln $(PWD)/zig-out/bin/zrun -sf $(HOME)/.local/bin
	ln $(PWD)/zrun.desktop -sf $(HOME)/.local/share/applications
 
