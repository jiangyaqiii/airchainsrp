#安装依赖
sudo apt-get update && apt-get install jq build-essential snapd -y
sudo snap install --classic go

#下载wasm和tracks
cd
git clone https://github.com/airchains-network/wasm-station.git
git clone https://github.com/airchains-network/tracks.git

#设置Wasm Station
cd wasm-station
go mod tidy
/bin/bash ./scripts/local-setup.sh

#运行wasmstation
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

#下载eigenlayer cli
cd
wget https://github.com/airchains-network/tracks/releases/download/v0.0.2/eigenlayer
sudo chmod +x eigenlayer
sudo mv eigenlayer /usr/local/bin/eigenlayer

#创建key
echo "123" | eigenlayer operator keys create --key-type ecdsa --insecure wallet
#跳出弹窗保存pub key hex，后面要用

#设置tracks
sudo rm -rf ~/.tracks
cd $HOME/tracks
go mod tidy

# 提示用户输入公钥和节点名
read -p "请输入Public Key hex: " pubkey
read -p "请输入节点名: " moniker
go run cmd/main.go init \
    --daRpc "disperser-holesky.eigenda.xyz" \
    --daKey "$pubkey" \
    --daType "eigen" \
    --moniker "$moniker" \
    --stationRpc "http://127.0.0.1:26657" \
    --stationAPI "http://127.0.0.1:1317" \
    --stationType "wasm"

#创建air钱包然后去领水
go run cmd/main.go keys junction --accountName wallet --accountPath $HOME/.tracks/junction-accounts/keys

go run cmd/main.go prover v1WASM

# 询问用户是否要继续执行
read -p "是否已经领水完毕要继续执行？(yes/no): " choice

if [[ "$choice" != "yes" ]]; then
    echo "脚本已终止。"
    exit 0
fi

# 如果用户选择继续，则执行以下操作
echo "继续执行脚本..."

CONFIG_PATH="$HOME/.tracks/config/sequencer.toml"
WALLET_PATH="$HOME/.tracks/junction-accounts/keys/wallet.wallet.json"
# 从钱包文件中提取 air 开头的钱包地址
AIR_ADDRESS=$(jq -r '.address' $WALLET_PATH)

# 获取本机 IP 地址
LOCAL_IP=$(curl -s4 ifconfig.me/ip)

# 从配置文件中提取 nodeid
NODE_ID=$(grep 'node_id =' $CONFIG_PATH | awk -F'"' '{print $2}')


# 运行 tracks create-station 命令
go run cmd/main.go create-station \
    --accountName "wallet" \
    --accountPath "$HOME/.tracks/junction-accounts/keys" \
    --jsonRPC "https://airchains-rpc.kubenode.xyz/" \
    --info "WASM Track" \
    --tracks "$AIR_ADDRESS" \
    --bootstrapNode "/ip4/$LOCAL_IP/tcp/2300/p2p/$NODE_ID"

#修改gas
sed -i 's/gasFees := fmt.Sprintf("%damf", gas)/gasFees := fmt.Sprintf("%damf", 2*gas)/' "$HOME/tracks/junction/verifyPod.go"
sed -i 's/gasFees := fmt.Sprintf("%damf", gas)/gasFees := fmt.Sprintf("%damf", 2*gas)/' "$HOME/tracks/junction/validateVRF.go"
sed -i 's/gasFees := fmt.Sprintf("%damf", gas)/gasFees := fmt.Sprintf("%damf", 3*gas)/' "$HOME/tracks/junction/submitPod.go"

#启动station
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

#创建刷tx脚本并在后台执行
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
