BIN     := airpods-mic-guardd
PREFIX  := $(HOME)/.local/bin
LABEL   := com.ancplua.airpods-mic-guard
AGENTS  := $(HOME)/Library/LaunchAgents
UID     := $(shell id -u)

build:
	swiftc -O -o $(BIN) src/$(BIN).swift -framework CoreAudio

install: build
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null
	install -m 755 $(BIN) $(PREFIX)/$(BIN)
	install -m 644 launchd/$(LABEL).plist $(AGENTS)/$(LABEL).plist
	launchctl bootstrap gui/$(UID) $(AGENTS)/$(LABEL).plist
	launchctl print gui/$(UID)/$(LABEL) | grep -E "state|pid" | head -3

uninstall:
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null
	rm -f $(PREFIX)/$(BIN) $(AGENTS)/$(LABEL).plist

status:
	launchctl print gui/$(UID)/$(LABEL) | grep -E "state|pid|last exit"
	tail -5 $(HOME)/Library/Logs/airpods-mic-guard.log 2>/dev/null

clean:
	rm -f $(BIN)

.PHONY: build install uninstall status clean
