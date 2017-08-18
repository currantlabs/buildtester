SCRIPTFILE=buildtester.bash
LOGFILE=buildtester.log
LOCKFILE=/tmp/buildtester-lockfile
CHECKSTATUS=checkstatus.bash
KILLSCRIPT=killscript.bash

JENKINSPOLLER=jenkinspoll
JENKINSPOLLERLINUXEXE=jenkinspoll_linux

ARCHIVE_NAME=buildtester.tar
ARCHIVE_FILES=                  \
    Makefile                    \
    jenkinspoll.go              \
    jenkinspoll                 \
    jenkinspoll_linux           \
    test_latest_build.bash      \
    jenkinstest.bash            \
    killscript.bash             \
    checkstatus.bash            \
    ble-console                 \
    ziggy                       \
    jenkins_lib.bash            \
    tests_lib.bash              \
    buildtester.bash            \
    login-id.txt                \
    login-passwd.txt            \
    location-id.txt             \
    macaddr-configured.txt      \
    macaddr-deconfigured.txt

all:
	go build $(JENKINSPOLLER).go
	GOOS=linux go build -o $(JENKINSPOLLERLINUXEXE) $(JENKINSPOLLER).go 

run:
	@./$(SCRIPTFILE) & 

log:
	@cat $(LOGFILE)

logtail:
	@tail -f $(LOGFILE)

running:
	@./$(CHECKSTATUS)

kill:
	@./$(KILLSCRIPT)

archive:
	tar -c -f $(ARCHIVE_NAME) $(ARCHIVE_FILES)

# Some BLE commands:
console:
	sudo /home/vagrant/vince/ble-console -addr 0c:c7:31:e2:f4:58

# Note the need to escape the $ with another $ ("$$") inside the sed invocation
scan:
	sudo /home/vagrant/ziggy --prod client scan | sed 's/^.*scan result .* mac=\(.*$$\)/\1/' | grep -v client | grep "0c:c7:31"


clean:
	rm -f $(JENKINSPOLLER)
	rm -f $(JENKINSPOLLERLINUXEXE)
	rm -f $(LOGFILE)
	rm -f $(LOCKFILE)
	rm -f $(ARCHIVE_NAME)
