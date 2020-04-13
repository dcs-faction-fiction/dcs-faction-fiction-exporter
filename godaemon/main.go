package main

import (
	"bufio"
	"bytes"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"time"
)

var DCSFF_POLL_FOR_ACTIONS = getEnv("DCSFF_POLL_FOR_ACTIONS", "http://localhost:8080/daemon-api/actions")
var DCSFF_POST_WAREHOUSE = getEnv("DCSFF_POST_WAREHOUSE", "http://localhost:8080/daemon-api/warehouses")
var DCSFF_APITOKEN = getEnv("DCSFF_APITOKEN", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwicm9sZXMiOlsiZGFlbW9uIl19.9jKMYjh89WT190T8IUP0qUcL8N4mfox7EcoQurlAv0g")

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}

func getNextAction() string {
	resp, err := http.Get(DCSFF_POLL_FOR_ACTIONS)
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
	req, err := http.NewRequest("POST", DCSFF_POST_WAREHOUSE, bytes.NewBuffer([]byte(json)))
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

	if resp.Status != "200" {
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

	listener, err := net.Listen("tcp", ":5555")
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
				getNextAction()
			}
		}
	}()
}

func main() {
	startPolling()
	listen() // listen is blocking as it will keep listening and accepting connections
}
