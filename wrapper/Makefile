TARGET = su
CC = aarch64-linux-android-clang
CFLAGS = -static -Os -s -Wall -Wextra

all: $(TARGET)

$(TARGET): su-wrapper.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)
