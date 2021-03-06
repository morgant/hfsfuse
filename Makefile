-include config.mak

CC ?= cc
AR ?= ar
RANLIB ?= ranlib
INSTALL ?= install
TAR ?= tar
CONFIG_CFLAGS ?= -O3 -std=gnu11
WITH_UBLIO ?= local
WITH_UTF8PROC ?= local
CONFIG_CFLAGS := $(CONFIG_CFLAGS) $(CFLAGS)

CFLAGS := -D_FILE_OFFSET_BITS=64 $(CONFIG_CFLAGS)

# extra flags we don't want to forward to the "external" libs like libhfs/ublio/utf8proc
LOCAL_CFLAGS=-Wall -Wextra -pedantic -Wno-gnu-zero-variadic-macro-arguments -Wno-unused-parameter
# older versions of gcc/clang need these as well
LOCAL_CFLAGS+=-Wno-missing-field-initializers -Wno-missing-braces

TARGETS = hfsfuse hfsdump
FUSE_FLAGS = -DFUSE_USE_VERSION=28
FUSE_LIB = -lfuse
OS := $(shell uname)
ifeq ($(OS), Darwin)
	APP_FLAGS += -DHAVE_BIRTHTIME
	ifeq ($(shell [ -e /usr/local/lib/libosxfuse.dylib ] && echo 1), 1)
		FUSE_FLAGS += -I/usr/local/include/osxfuse
		FUSE_LIB = -losxfuse
	endif
else ifeq ($(OS), Haiku)
	CFLAGS += -D_BSD_SOURCE
	APP_LIB += -lbsd
	FUSE_FLAGS += -I/system/develop/headers/userlandfs/fuse -I/system/develop/headers/bsd
	FUSE_LIB = -L/system/lib/ -luserlandfs_fuse
	PREFIX ?= /boot/home/config/non-packaged
else ifeq ($(OS), FreeBSD)
	APP_FLAGS += -DHAVE_BIRTHTIME
	APP_FLAGS += -I/usr/local/include
	APP_LIB += -L/usr/local/lib
	FUSE_FLAGS += -I/usr/local/include
else ifeq ($(OS), DragonFly)
	APP_FLAGS += -I/usr/local/include
	APP_LIB += -L/usr/local/lib
	FUSE_FLAGS += -I/usr/local/include
else ifeq ($(OS), NetBSD)
$(info NetBSD detected, only hfsdump will be built by default)
	TARGETS=hfsdump
endif

PREFIX ?= /usr/local

define CONFIG
CC=$(CC)
AR=$(AR)
RANLIB=$(RANLIB)
INSTALL=$(INSTALL)
PREFIX=$(PREFIX)
WITH_UBLIO=$(WITH_UBLIO)
WITH_UTF8PROC=$(WITH_UTF8PROC)
CONFIG_CFLAGS=$(CONFIG_CFLAGS)
endef
export CONFIG

LIBS = lib/libhfsuser/libhfsuser.a lib/libhfs/libhfs.a
LIBDIRS = $(abspath $(dir $(LIBS)))
INCLUDE = $(foreach lib,$(LIBDIRS),-I$(lib))

ifneq ($(WITH_UBLIO), none)
	APP_FLAGS += -DHAVE_UBLIO
	ifeq ($(WITH_UBLIO), system)
		APP_LIB += -lublio
	else ifeq ($(WITH_UBLIO), local)
		LIBS += lib/ublio/libublio.a
	else
$(error Invalid option "$(WITH_UBLIO)" for WITH_UBLIO. Use one of: none, system, local)
	endif
endif
ifneq ($(WITH_UTF8PROC), none)
	APP_FLAGS += -DHAVE_UTF8PROC
	ifeq ($(WITH_UTF8PROC), system)
		APP_LIB += -lutf8proc
	else ifeq ($(WITH_UTF8PROC), local)
		LIBS += lib/utf8proc/libutf8proc.a
	else
$(error Invalid option "$(WITH_UTF8PROC)" for WITH_UTF8PROC. Use one of: none, system, local)
	endif
endif

RELEASE_NAME=hfsfuse
GIT_HEAD_SHA=$(shell git rev-parse --short HEAD 2> /dev/null)
ifneq ($(GIT_HEAD_SHA), )
	VERSION = 0.$(shell git rev-list HEAD --count)
	RELEASE_NAME := $(RELEASE_NAME)-$(VERSION)
	VERSION_STRING = \"$(VERSION)-$(GIT_HEAD_SHA)\"
	CFLAGS += -DHFSFUSE_VERSION_STRING=$(VERSION_STRING)
else ifeq ($(wildcard src/version.h), )
    $(warning Warning: git repo nor prepackaged version.h found, hfsfuse will be built without version information)
	CFLAGS += -DHFSFUSE_VERSION_STRING=\"omitted\"
endif

export PREFIX CC CFLAGS LOCAL_CFLAGS APP_FLAGS LIBDIRS AR RANLIB INCLUDE

.PHONY: all clean always_check config install uninstall install-lib uninstall-lib lib version dist

all: $(TARGETS)

%.o: %.c
	$(CC) $(LOCAL_CFLAGS) $(INCLUDE) $(CFLAGS) -c -o $*.o $^

src/hfsfuse.o: src/hfsfuse.c
	$(CC) $(LOCAL_CFLAGS) $(FUSE_FLAGS) $(INCLUDE) $(CFLAGS) -c -o $*.o $^

$(LIBS): always_check
	$(MAKE) -C $(dir $@)

lib: $(LIBS)

hfsfuse: src/hfsfuse.o $(LIBS)
	$(CC) $(CFLAGS) $(APP_LIB) -o $@ src/hfsfuse.o $(LIBS) $(FUSE_LIB) -lpthread

hfsdump: src/hfsdump.o $(LIBS)
	$(CC) $(CFLAGS) $(APP_LIB) -o $@ src/hfsdump.o $(LIBS) -lpthread

clean:
	for dir in $(LIBDIRS); do $(MAKE) -C $$dir clean; done
	rm -f src/hfsfuse.o hfsfuse src/hfsdump.o hfsdump

distclean: clean
	rm -f config.mak src/version.h

install-lib: $(LIBS)
	for dir in $(LIBDIRS); do $(MAKE) -C $$dir install; done

uninstall-lib: $(LIBS)
	for dir in $(LIBDIRS); do $(MAKE) -C $$dir uninstall; done

ifeq ($(OS), Haiku)
install: $(TARGETS)
	mkdir -p $(PREFIX)/add-ons/userlandfs/
	$(INSTALL) -m 644 hfsfuse $(PREFIX)/add-ons/userlandfs/
	$(INSTALL) hfsdump $(PREFIX)/bin/

uninstall:
	rm -f $(PREFIX)/add-ons/userlandfs/hfsfuse $(PREFIX)/bin/hfsdump
else
install:$(TARGETS)
	$(INSTALL) $^ $(PREFIX)/bin/

uninstall:
	rm -f $(PREFIX)/bin/hfsfuse $(PREFIX)/bin/hfsdump
endif

version:
	echo \#define HFSFUSE_VERSION_STRING $(VERSION_STRING) > src/version.h

config:
	echo "$$CONFIG" > config.mak

dist: version
	ln -s . $(RELEASE_NAME)
	git ls-files | sed "s/^/$(RELEASE_NAME)\//" | COPYFILE_DISABLE=1 $(TAR) -czf "$(RELEASE_NAME).tar.gz" -T - -- "$(RELEASE_NAME)/src/version.h"
	rm -f -- $(RELEASE_NAME)
