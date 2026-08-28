APP_NAME = pi-bluetooth-configuration-client-mac

.PHONY: build app run clean

build:
	swift build -c release

app: build
	./scripts/build_app.sh

run: app
	open $(APP_NAME).app

clean:
	rm -rf .build "$(APP_NAME).app"
