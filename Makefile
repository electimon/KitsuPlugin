PLUGIN_NAME = 52_KitsuPlugin

IS_WINDOWS := false
MACHINE_OS := $(shell clang -dumpmachine | cut -d'-' -f3)
ifeq ($(MACHINE_OS),windows)
IS_WINDOWS := true
endif

all:
ifneq ($(IS_WINDOWS),true)
	objfw-compile --package ObjFWTLS -Wno-nullability-completeness --arc --lib 1.0 plugin.m -o $(PLUGIN_NAME)
else
	objfw-compile --package ObjFWTLS -L../../srcs -lhanami -Wno-nullability-completeness --arc --lib 1.0 plugin.m -o $(PLUGIN_NAME)
endif
