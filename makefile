.PHONY: all raylib

all: raylib
	zig build 
	./zig-out/bin/zrun

raylib: ./raylib-6.0_linux_amd64/include/raylib.h

raylib-6.0_linux_amd64/include/raylib.h: raylib-6.0_linux_amd64.tar.gz
	tar -xf raylib-6.0_linux_amd64.tar.gz

raylib-6.0_linux_amd64.tar.gz:
	curl -L -O https://github.com/raysan5/raylib/releases/download/6.0/raylib-6.0_linux_amd64.tar.gz 
