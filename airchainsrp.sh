#安装需要的包
sudo apt-get update && apt-get install jq build-essential -y

curl https://dl.google.com/go/go1.22.1.linux-amd64.tar.gz | sudo tar -C/usr/local -zxvf - ;
cat <<'EOF' >>$HOME/.bashrc
export GOROOT=/usr/local/go
export GOPATH=$HOME/go
export GO111MODULE=on
export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin
EOF
source $HOME/.bashrc

cd
git clone https://github.com/airchains-network/wasm-station.git
git clone https://github.com/airchains-network/tracks.git

#设置wsam
cd wasm-station
go mod tidy
/bin/bash ./scripts/local-setup.sh

#创建并启动wasm服务
sudo tee <<EOF >/dev/null /etc/systemd/system/wasmstationd.service
[Unit]
Description=wasmstationd
After=network.target
[Service]
User=$USER
ExecStart=$HOME/wasm-station/build/wasmstationd start --api.enable
Restart=always
RestartSec=3
LimitNOFILE=10000
[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload && \
sudo systemctl enable wasmstationd && \
sudo systemctl start wasmstationd

#设置DA
cd
wget https://github.com/airchains-network/tracks/releases/download/v0.0.2/eigenlayer
sudo chmod +x eigenlayer
sudo mv eigenlayer /usr/local/bin/eigenlayer

#创建钱包
eigenlayer operator keys create  -i=true --key-type ecdsa wallet

#设置Tracks
sudo rm -rf ~/.tracks
cd $HOME/tracks
go mod tidy

#初始化sequencer
go run cmd/main.go init --daRpc "disperser-holesky.eigenda.xyz" --daKey "上面的Public Key hex" --daType "eigen" --moniker "节点名" --stationRpc "http://127.0.0.1:26657" --stationAPI "http://127.0.0.1:1317" --stationType "wasm"
go run cmd/main.go keys junction --accountName airchains地址名 --accountPath $HOME/.tracks/junction-accounts/keys
go run cmd/main.go prover v1WASM


nodeid=$(grep "node_id" ~/.tracks/config/sequencer.toml | awk -F '"' '{print $2}')
ip=$(curl -s4 ifconfig.me/ip)
bootstrapNode=/ip4/$ip/tcp/2300/p2p/$nodeid
echo $bootstrapNode

go run cmd/main.go create-station --accountName airchains地址名 --accountPath $HOME/.tracks/junction-accounts/keys --jsonRPC "https://junction-testnet-rpc.synergynodes.com/" --info "WASM Track" --tracks 刚刚air开头的地址 --bootstrapNode "刚刚显示的bootstrapNode"


sed -i 's/gasFees := fmt.Sprintf("%damf", gas)/gasFees := fmt.Sprintf("%damf", 2*gas)/' "$HOME/tracks/junction/verifyPod.go"
sed -i 's/gasFees := fmt.Sprintf("%damf", gas)/gasFees := fmt.Sprintf("%damf", 2*gas)/' "$HOME/tracks/junction/validateVRF.go"
sed -i 's/gasFees := fmt.Sprintf("%damf", gas)/gasFees := fmt.Sprintf("%damf", 3*gas)/' "$HOME/tracks/junction/submitPod.go"

sudo tee /etc/systemd/system/stationd.service > /dev/null << EOF
[Unit]
Description=station track service
After=network-online.target
[Service]
User=$USER
WorkingDirectory=$HOME/tracks/
ExecStart=$(which go) run cmd/main.go start
Restart=always
RestartSec=3
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable stationd
sudo systemctl restart stationd

cd
addr=$($HOME/wasm-station/build/wasmstationd keys show node --keyring-backend test -a)
sudo tee spam.sh > /dev/null << EOF
#!/bin/bash

while true; do
  $HOME/wasm-station/build/wasmstationd tx bank send node ${addr} 1stake --from node --chain-id station-1 --keyring-backend test -y 
  sleep 6  # Add a sleep to avoid overwhelming the system or network
done
EOF
nohup bash spam.sh &
