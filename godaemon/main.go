package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"time"
)

var DCSFF_POLL_FOR_ACTIONS = getEnv("DCSFF_POLL_FOR_ACTIONS", "http://localhost:8080/")
var DCSFF_POST_WAREHOUSE = getEnv("DCSFF_POST_WAREHOUSE", "http://localhost:8080/")

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
}

func getNextAction() string {
	resp, err := http.Get(DCSFF_POLL_FOR_ACTIONS)
	if err != nil {
		log.Fatal(err)
	}
  defer resp.Body.Close()
	body, err := ioutil.ReadAll(resp.Body)
	if err != nil {
		log.Fatal(err)
	}
	return body
}

func sendWarehouse(json string) {
	log.Println("Posting message: " + json)
	req, err := http.NewRequest("POST", DCSFF_POST_WAREHOUSE, bytes.NewBuffer(json))
	if err != nil {
		log.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		log.Fatal(err)
	}
	defer resp.Body.Close()
}

func handleConnection(conn net.Conn) {

	defer func() {
		log.Println("Connection is being closed")
		conn.Close()
	}()

	reader := bufio.NewReader(conn)

	for {
		conn.SetReadDeadline(time.Now().Add(60 * time.Second))

		// Read tokens delimited by newline
		var apimessage = ""
		s, err := reader.ReadString('\n')
		if err != nil {
			log.Fatal(err)
		}

		s = strings.Trim(s, " ")
		if s == "" {
			var json := apimessage
			apimessage := ""
			log.Println("Posting message: " + json)
			sendWarehouse(json)
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
			log.Fatal(err)
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
			case t := <-ticker.C:
				s := getNextAction();
				log.Println("Got: " + s)
			}
		}
	}()
}

func main() {
	startPolling()
	listen() // listen is blocking as it will keep listening and accepting connections
}
