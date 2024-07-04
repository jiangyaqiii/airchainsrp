#!/bin/bash

service_name="stationd"

if systemctl is-active --quiet $service_name; then
    echo "airchains"
else
    echo "未运行"
fi
