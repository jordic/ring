package main

// Import all providers so their init() functions register them.
import (
	_ "github.com/jordic/ring/internal/providers"
)

func main() {
	Execute()
}
