package main

import (
	"flag"
	"fmt"
	"os"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	switch os.Args[1] {
	case "run":
		runCmd(os.Args[2:])
	case "serve":
		serveCmd(os.Args[2:])
	case "version":
		fmt.Println("prdigest 0.0.0-dev")
	case "help", "-h", "--help":
		usage()
	default:
		fmt.Fprintf(os.Stderr, "unknown command %q\n", os.Args[1])
		usage()
		os.Exit(2)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, `prdigest — multi-repo daily merged-PR digests for Telegram

Usage:
  prdigest run   [--config PATH] [--date YYYY-MM-DD] [--dry-run]
  prdigest serve [--config PATH]
  prdigest version

Environment:
  GITHUB_TOKEN          GitHub API token (read PRs)
  TELEGRAM_BOT_TOKEN    Telegram bot token
  PRDIGEST_CONFIG       default config path
`)
}

func runCmd(args []string) {
	fs := flag.NewFlagSet("run", flag.ExitOnError)
	cfg := fs.String("config", envOr("PRDIGEST_CONFIG", "configs/config.example.yml"), "config path")
	date := fs.String("date", "", "local day YYYY-MM-DD (default: yesterday in config timezone)")
	dry := fs.Bool("dry-run", false, "print message, do not send")
	_ = fs.Parse(args)
	fmt.Printf("prdigest run: not implemented yet (config=%s date=%q dry-run=%v)\n", *cfg, *date, *dry)
	fmt.Println("Scaffold only — implementation coming next.")
	os.Exit(0)
}

func serveCmd(args []string) {
	fs := flag.NewFlagSet("serve", flag.ExitOnError)
	cfg := fs.String("config", envOr("PRDIGEST_CONFIG", "configs/config.example.yml"), "config path")
	_ = fs.Parse(args)
	fmt.Printf("prdigest serve: not implemented yet (config=%s)\n", *cfg)
	os.Exit(0)
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}
