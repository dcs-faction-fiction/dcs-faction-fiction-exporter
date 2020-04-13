package main

import (
	"bufio"
	"fmt"
	"log"
	"net"
	"os"
	"time"
)

var APPURL_POLL_FOR_ACTIONS = getEnv("APPURL_POLL_FOR_ACTIONS", "http://localhost:8080/")

func getEnv(key, fallback string) string {
	if value, ok := os.LookupEnv(key); ok {
		return value
	}
	return fallback
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
		s, err := reader.ReadString('\n')
		if err != nil {
			log.Fatal(err)
		}

		fmt.Printf("%s", s)
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

				log.Println("Tick at", t)
			}
		}
	}()
}

func main() {
	startPolling()
	listen() // listen is blocking as it will keep listening and accepting connections
}
