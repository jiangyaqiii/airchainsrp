sudo systemctl stop stationd
cd $HOME/tracks
go run cmd/main.go rollback
go run cmd/main.go rollback
go run cmd/main.go rollback
sudo systemctl restart stationd
