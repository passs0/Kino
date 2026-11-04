.PHONY: all build run clean test-media

all: build

build:
	@chmod +x build_app.sh
	@./build_app.sh

run: build
	@echo "Launching Serein.app..."
	@open build/Serein.app 2>/dev/null || ./build/Serein.app/Contents/MacOS/Serein

test-media:
	@echo "Generating sample media files in /tmp..."
	@/opt/homebrew/bin/ffmpeg -y -f lavfi -i testsrc=duration=5:size=640x360:rate=30 -f lavfi -i sine=frequency=440:duration=5 -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 128k /tmp/serein_sample_native.mp4
	@/opt/homebrew/bin/ffmpeg -y -f lavfi -i testsrc=duration=5:size=640x360:rate=30 -f lavfi -i sine=frequency=440:duration=5 -c:v libx264 -pix_fmt yuv420p -c:a aac /tmp/serein_sample_remux.mkv
	@/opt/homebrew/bin/ffmpeg -y -f lavfi -i testsrc=duration=3:size=320x240:rate=24 -f lavfi -i sine=frequency=880:duration=3 -c:v libvpx-vp9 -b:v 500k -c:a libopus /tmp/serein_sample_transcode.webm
	@echo "Sample media ready:"
	@ls -lh /tmp/serein_sample_*

clean:
	@rm -rf build
