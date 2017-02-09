CC=clang
CFLAGS=-fobjc-arc -lreadline -framework CoreBluetooth

build/coblue-control:
	mkdir -p build;
	$(CC) $(CFLAGS) src/*.m -o $@

.PHONY:install
install:build/coblue-control
	mkdir -p /usr/local/bin
	cp build/coblue-control /usr/local/bin/coblue-control

.PHONY:uninstall
uninstall:
	rm /usr/local/bin/coblue-control

.PHONY:clean
clean:
	rm -rf build
