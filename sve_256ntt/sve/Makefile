# SPDX-License-Identifier: Apache-2.0

.PHONY: clean

TARGET = bench_bunroll_a4
CC  ?= gcc
LD  := $(CC)

SOURCES = \
    hal/hal.c \
    bench_bunroll_a4.c \
    ntt_kyber_sve_bunroll_a4.S \
    kyber_tw.S \
    tw_ln2_uzp.S

CFLAGS := \
	-Wall \
	-Wextra \
	-Werror=unused-result \
	-Wpedantic \
	-Werror \
	-Wmissing-prototypes \
	-Wshadow \
	-Wpointer-arith \
	-Wredundant-decls \
	-Wno-long-long \
	-Wno-unknown-pragmas \
	-Wno-unused-command-line-argument \
	-O3 \
	-fomit-frame-pointer \
	-mcpu=neoverse-v1 \
	-std=c99 \
	-pedantic \
	-Ihal \
	-MMD \
	$(CFLAGS)

ifeq ($(CYCLES),PMU)
	CFLAGS += -DPMU_CYCLES
endif

ifeq ($(CYCLES),PERF)
	CFLAGS += -DPERF_CYCLES
endif

ifeq ($(CYCLES),MAC)
	CFLAGS += -DMAC_CYCLES
endif

all: $(TARGET)

$(TARGET): $(SOURCES)
	$(CC) $(CFLAGS) $(SOURCES) -o $(TARGET)

clean:
	-$(RM) -rf $(TARGET) *.d