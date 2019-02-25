package store

import (
	"errors"
	"fmt"
	"io/ioutil"
	"os"
	"path"
)

// LocalStore provides a filesystem-backed store
type LocalStore struct {
	home string
}

// NewLocalStore returns a local store handler
func NewLocalStore(home string) (*LocalStore, error) {
	if !dirExist(home) {
		if err := os.Mkdir(home, 0700); err != nil {
			return nil, fmt.Errorf("failed to create new home directory: %s", err)
		}
	}

	return &LocalStore{
		home: home,
	}, nil
}

// Save add a new entry to the store
func (ls *LocalStore) Save(id string, record *Entry) error {
	if exist(path.Join(ls.home, id)) {
		return errors.New("duplicated entry")
	}
	contents, err := record.Encode()
	if err != nil {
		return err
	}
	return ioutil.WriteFile(path.Join(ls.home, id), contents, 0400)
}

// Close the store instance and free resources
func (ls *LocalStore) Close() error {
	return nil
}

// Verify the provided path is either a file or directory that exists
func exist(name string) bool {
	_, err := os.Stat(name)
	return err == nil
}

// Verify the provided path exists and is a directory
func dirExist(name string) bool {
	info, err := os.Stat(name)
	if err != nil {
		return false
	}
	return info.IsDir()
}
