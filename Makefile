VERSION := $(shell cat VERSION)

.PHONY: build run install uninstall release clean

build:
	./scripts/build.sh

run: build
	-pkill -x OwlMac
	open build/OwlMac.app

install:
	./install.sh

uninstall:
	./uninstall.sh

# Publishes dist/OwlMac.zip so `curl … install.sh | bash` picks it up.
release: build
	gh release create "v$(VERSION)" dist/OwlMac.zip --title "OwlMac v$(VERSION)" --generate-notes

clean:
	rm -rf build dist
