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
	"os/user"
	"strings"
	"time"
)

var DCSFF_SERVER_ID = getEnv("DCSFF_SERVER_ID", "server1")
var DCSFF_LISTEN_PORT = getEnv("DCSFF_LISTEN_PORT", "5555")
var DCSFF_POLL_FOR_ACTIONS = getEnv("DCSFF_POLL_FOR_ACTIONS", "http://localhost:8080/daemon-api/actions")
var DCSFF_POST_WAREHOUSE = getEnv("DCSFF_POST_WAREHOUSE", "http://localhost:8080/daemon-api/warehouses")
var DCSFF_NEXT_MISSION = getEnv("DCSFF_POST_WAREHOUSE", "http://localhost:8080/daemon-api/missions")
var DCSFF_APITOKEN = getEnv("DCSFF_APITOKEN", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwicm9sZXMiOlsiZGFlbW9uIl19.9jKMYjh89WT190T8IUP0qUcL8N4mfox7EcoQurlAv0g")

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}
func downloadFile(filepath string, url string) error {
	// Get the data
	req, err := http.NewRequest("GET", DCSFF_NEXT_MISSION+"/"+DCSFF_SERVER_ID, nil)
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
	fromurl := DCSFF_NEXT_MISSION + "/" + DCSFF_SERVER_ID
	path := usr.HomeDir + "\\Saved Games\\" + DCSFF_SERVER_ID + "\\mission.miz"
	log.Println("downloading mission: " + fromurl + " >>> " + path)
	if err := downloadFile(path, fromurl); err != nil {
		log.Println(err)
	} else {

	}
}

func getNextAction() string {
	req, err := http.NewRequest("GET", DCSFF_POLL_FOR_ACTIONS+"/"+DCSFF_SERVER_ID, nil)
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
	return string(body)
}

func sendWarehouse(json string) {
	log.Println("Posting message: " + json)
	req, err := http.NewRequest("POST", DCSFF_POST_WAREHOUSE+"/"+DCSFF_SERVER_ID, bytes.NewBuffer([]byte(json)))
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

	if resp.Status != "200 OK" {
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
			json := apimessage
			apimessage = ""
			sendWarehouse(json)
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
				case "\"START_NEW_MISSION\"":
					startNewMission()
				}
			}
		}
	}()
}

func main() {
	startPolling()
	listen() // listen is blocking as it will keep listening and accepting connections
}
