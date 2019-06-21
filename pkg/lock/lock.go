package lock

import (
	"fmt"
	"os"
	"path/filepath"
	"time"
)

var (
	LocksDir       string
	Locks          map[string]LockObject
	DefaultTimeout = 24 * time.Hour
)

func Init(path string) error {
	Locks = make(map[string]LockObject)
	LocksDir = filepath.Join(path, "locks")

	err := os.MkdirAll(LocksDir, 0755)
	if err != nil {
		return fmt.Errorf("cannot initialize locks dir: %s", err)
	}

	return nil
}

type LockOptions struct {
	Timeout  time.Duration
	ReadOnly bool
}

func Lock(name string, opts LockOptions) error {
	lock := getLock(name)

	return lock.Lock(
		getTimeout(opts), opts.ReadOnly,
		func(doWait func() error) error { return onWait(name, doWait) },
	)
}

type TryLockOptions struct {
	ReadOnly bool
}

// TryLock tries to acquire a lock without a wait. Returns true if lock is acquired. Returns false if lock is acquired by another process.
func TryLock(name string, opts TryLockOptions) (bool, error) {
	res := true
	lock := getLock(name)

	err := lock.Lock(0, opts.ReadOnly, func(doWait func() error) error {
		// Wait called => is locked now, do not call doWait, just return
		res = false
		return nil
	})

	if err != nil {
		return false, err
	}

	return res, nil
}

func Unlock(name string) error {
	if _, hasKey := Locks[name]; !hasKey {
		return fmt.Errorf("no such lock `%s` found", name)
	}

	lock := getLock(name)

	return lock.Unlock()
}

func WithLock(name string, opts LockOptions, f func() error) error {
	lock := getLock(name)

	return lock.WithLock(
		getTimeout(opts), opts.ReadOnly,
		func(doWait func() error) error { return onWait(name, doWait) },
		f,
	)
}

func onWait(name string, doWait func() error) error {
	//logProcessMsg := fmt.Sprintf("Waiting for locked resource '%s'", name)
	// log.Debug(logProcessMsg)
	return doWait()
}

func getTimeout(opts LockOptions) time.Duration {
	if opts.Timeout != 0 {
		return opts.Timeout
	}
	return DefaultTimeout
}

func getLock(name string) LockObject {
	if l, hasKey := Locks[name]; hasKey {
		return l
	}

	Locks[name] = NewFileLock(name, LocksDir)

	return Locks[name]
}

type LockObject interface {
	GetName() string
	Lock(timeout time.Duration, readOnly bool, onWait func(doWait func() error) error) error
	Unlock() error
	WithLock(timeout time.Duration, readOnly bool, onWait func(doWait func() error) error, f func() error) error
}
