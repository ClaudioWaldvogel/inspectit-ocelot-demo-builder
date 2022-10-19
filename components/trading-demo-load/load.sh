#!/bin/sh
while :
do
  curl -v http://trading-app-frontend:8080/quote?coin=BTC\&amount=123
	sleep 5
done