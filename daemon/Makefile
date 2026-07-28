TARGET = ksu-toastd
CC = aarch64-linux-android-clang
CFLAGS = -static -Os -s -Wall -Wextra -pthread

all: $(TARGET)

$(TARGET): ksu-toastd.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(TARGET)
