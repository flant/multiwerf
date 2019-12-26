package utils

import "math/rand"

const letterBytes = "abcdefghijklmnopqrstuvwxyz0123456789"

func GetRandomString(n int) string {
	b := make([]byte, n)
	for i := range b {
		b[i] = letterBytes[rand.Intn(len(letterBytes))]
	}

	return string(b)
}
