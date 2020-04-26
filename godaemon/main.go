package main

import (
	"bufio"
	"bytes"
	"io"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/user"
	"strings"
	"time"
)

var DCSFF_SERVER_ID = getEnv("DCSFF_SERVER_ID", "server1")
var DCSFF_SERVER_EXEC = getEnv("DCSFF_SERVER_EXEC", "C:\\DCS\\bin\\dcs.exe")
var DCSFF_LISTEN_PORT = getEnv("DCSFF_LISTEN_PORT", "5555")
var DCSFF_API = getEnv("DCSFF_API", "http://localhost:8080")
var DCSFF_APITOKEN = getEnv("DCSFF_APITOKEN", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwicm9sZXMiOlsiZGFlbW9uIl19.9jKMYjh89WT190T8IUP0qUcL8N4mfox7EcoQurlAv0g")

// These remain constant in the api side implementation
var DCSFF_POLL_FOR_ACTIONS = DCSFF_API + "/daemon-api/" + DCSFF_SERVER_ID + "/actions"
var DCSFF_POST_WAREHOUSE = DCSFF_API + "/daemon-api/" + DCSFF_SERVER_ID + "/warehouses"
var DCSFF_POST_DEADUNITS = DCSFF_API + "/daemon-api/" + DCSFF_SERVER_ID + "/deadunits"
var DCSFF_POST_MOVEDUNITS = DCSFF_API + "/daemon-api/" + DCSFF_SERVER_ID + "/movedunits"
var DCSFF_NEXT_MISSION = DCSFF_API + "/daemon-api/" + DCSFF_SERVER_ID + "/missions"
var DCSFF_MISSION_STARTED = DCSFF_API + "/daemon-api/" + DCSFF_SERVER_ID + "/actions/MISSION_STARTED"

var firstPoll = true

var command *exec.Cmd = nil

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}
func downloadFile(filepath string, url string) error {
	// Get the data
	req, err := http.NewRequest("GET", DCSFF_NEXT_MISSION, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+DCSFF_APITOKEN)
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	// Create the file
	out, err := os.Create(filepath)
	if err != nil {
		return err
	}
	defer out.Close()
	// Write the body to file
	_, err = io.Copy(out, resp.Body)
	return err
}

func startNewMission() {
	log.Println("Starting new mission, fetching file from server.")
	usr, err := user.Current()
	if err != nil {
		return
	}
	fromurl := DCSFF_NEXT_MISSION
	dcsuserpath := usr.HomeDir + "\\Saved Games\\" + DCSFF_SERVER_ID
	path := dcsuserpath + "\\mission.miz"
	log.Println("downloading mission: " + fromurl + " >>> " + path)
	if err := downloadFile(path, fromurl); err != nil {
		log.Println(err)
	} else {
		command = exec.Command(DCSFF_SERVER_EXEC,
			"--server",
			"--norender",
			"-w",
			DCSFF_SERVER_ID)

		err := command.Start()
		if err != nil {
			log.Println(err)
		}
		log.Printf("DCS running...")
		err = command.Wait()
		log.Printf("DCS ended")
		if err != nil {
			log.Println(err)
		}
	}
}

func stopMission() {
	log.Println("Stop mission received...")
	if command != nil {
		log.Println("Stopping server...")
		command.Process.Kill()
		command = nil
	}
}

func getNextAction() string {
	req, err := http.NewRequest("GET", DCSFF_POLL_FOR_ACTIONS, nil)
	if err != nil {
		return "{}"
	}
	req.Header.Set("Authorization", "Bearer "+DCSFF_APITOKEN)
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return "{}"
	}
	defer resp.Body.Close()
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		return "{}"
	}
	if firstPoll && resp.Status == "200 OK" {
		firstPoll = false
		log.Println("First poll successful, token is valid.")
	}
	return string(body)
}

func sendPost(url string, json string) {
	sendBody("POST", url, json)
}
func sendPut(url string, json string) {
	sendBody("PUT", url, json)
}

func sendBody(method string, url string, json string) {
	req, err := http.NewRequest(method, url, bytes.NewBuffer([]byte(json)))
	if err != nil {
		log.Println(err)
		return
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+DCSFF_APITOKEN)
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		log.Println(err)
		return
	}
	defer resp.Body.Close()

	if resp.Status != "200 OK" && resp.Status != "201 Created" {
		log.Println("response Status:", resp.Status)
		log.Println("response Headers:", resp.Header)
		body, _ := ioutil.ReadAll(resp.Body)
		log.Println("response Body:", string(body))
	}
}

func handleConnection(conn net.Conn) {

	defer conn.Close()

	reader := bufio.NewReader(conn)

	apimessage := ""
	for {
		conn.SetReadDeadline(time.Now().Add(5 * time.Second))

		// Read tokens delimited by newline
		s, err := reader.ReadString('\n')
		if err != nil {
			continue
		}

		s = strings.Trim(s, " ")
		s = strings.Trim(s, "\n")
		if s == "" {
			log.Println("Received message: " + s)
			json := apimessage
			apimessage = ""
			command := json[0:1]
			json = json[1:]
			switch command {
			case "S":
				log.Println("Mission started.")
				sendPut(DCSFF_MISSION_STARTED, json)
			case "W":
				log.Println("Sending warehouses: " + json)
				sendPost(DCSFF_POST_WAREHOUSE, json)
			case "D":
				log.Println("Sending dead units: " + json)
				sendPost(DCSFF_POST_DEADUNITS, json)
			case "M":
				log.Println("Sending moved units: " + json)
				sendPost(DCSFF_POST_MOVEDUNITS, json)
			}
			return
		} else {
			apimessage = apimessage + s
		}
	}
}

func listen() {

	listener, err := net.Listen("tcp", ":"+DCSFF_LISTEN_PORT)
	if err != nil {
		panic(err)
	}

	defer func() {
		listener.Close()
		log.Println("Listener closed")
	}()

	log.Println("Listening...")
	for {
		conn, err := listener.Accept()
		if err != nil {
			log.Println(err)
			continue
		}
		go handleConnection(conn)
	}
}

func startPolling() {
	ticker := time.NewTicker(5 * time.Second)
	log.Println("Starting poller.")
	go func() {
		for {
			select {
			case <-ticker.C:
				s := getNextAction()
				switch s {
				case "\"STOP_MISSION\"":
					go stopMission()
				case "\"START_NEW_MISSION\"":
					go startNewMission()
				}
			}
		}
	}()
}

func main() {
	startPolling()
	listen() // listen is blocking as it will keep listening and accepting connections
}
