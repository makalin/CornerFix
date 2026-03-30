BUILD_DIR := build
DYLIB := $(BUILD_DIR)/libcornerfix.dylib
CLI := $(BUILD_DIR)/cornerfixctl
INJECT := $(BUILD_DIR)/cornerfix-inject
TEST_APP_EXECUTABLE := $(BUILD_DIR)/CornerFixTestApp.app/Contents/MacOS/CornerFixTestApp
TEST_APP_BUNDLE := $(BUILD_DIR)/CornerFixTestApp.app
CC := clang
COMMON_FLAGS := -fobjc-arc -Wall -Wextra -Werror
FRAMEWORKS := -framework Foundation -framework AppKit -framework QuartzCore -framework ScreenCaptureKit -framework CoreMedia
PREFIX ?= /usr/local

COMMON_SOURCES := src/common/CFXShared.m
DYLIB_SOURCES := $(COMMON_SOURCES) src/sharpener/CFXSwizzle.m src/sharpener/CornerFixSharpener.m
CLI_SOURCES := $(COMMON_SOURCES) src/cli/main.m
INJECT_SOURCES := src/inject/main.m
TEST_APP_SOURCES := src/testapp/main.m
TEST_APP_PLIST := src/testapp/Info.plist

.PHONY: all clean dylib cli inject testapp examples install uninstall

all: dylib cli inject testapp

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

dylib: $(DYLIB)

$(DYLIB): $(DYLIB_SOURCES) | $(BUILD_DIR)
	$(CC) $(COMMON_FLAGS) -dynamiclib $(DYLIB_SOURCES) $(FRAMEWORKS) -o $(DYLIB)

cli: $(CLI)

$(CLI): $(CLI_SOURCES) | $(BUILD_DIR)
	$(CC) $(COMMON_FLAGS) $(CLI_SOURCES) -framework Foundation -o $(CLI)

inject: $(INJECT)

$(INJECT): $(INJECT_SOURCES) | $(BUILD_DIR)
	$(CC) $(COMMON_FLAGS) $(INJECT_SOURCES) -framework Foundation -framework AppKit -o $(INJECT)

testapp: $(TEST_APP_EXECUTABLE)

$(TEST_APP_EXECUTABLE): $(TEST_APP_SOURCES) $(TEST_APP_PLIST) | $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)/CornerFixTestApp.app/Contents/MacOS
	mkdir -p $(BUILD_DIR)/CornerFixTestApp.app/Contents/Resources
	cp $(TEST_APP_PLIST) $(BUILD_DIR)/CornerFixTestApp.app/Contents/Info.plist
	$(CC) $(COMMON_FLAGS) $(TEST_APP_SOURCES) -framework Foundation -framework AppKit -o $(TEST_APP_EXECUTABLE)

examples: all
	chmod +x examples/*.sh

install: all examples
	PREFIX=$(PREFIX) ./scripts/install.sh

uninstall:
	PREFIX=$(PREFIX) ./scripts/uninstall.sh

clean:
	rm -rf $(BUILD_DIR)
