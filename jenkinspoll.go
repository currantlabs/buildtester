package main

import (
	"github.com/yosida95/golang-jenkins"
	"os"
)

const (
	FailedToGetJob       = -1
	FailedToGetLastBuild = -2
)

func main() {
	auth := &gojenkins.Auth{
		Username: "vince",
		ApiToken: "j@nky",
	}

	jenkins := gojenkins.NewJenkins(auth, "http://jenkins.currant.com:8080")

	job, err := jenkins.GetJob("new-day")

	if err != nil {
		os.Exit(FailedToGetJob)
	}

	build, err := jenkins.GetLastBuild(job)
	if err != nil {
		os.Exit(FailedToGetLastBuild)
	}

	os.Exit(build.Number)

}
