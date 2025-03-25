#!/bin/bash
sudo apt-get update -y
sudo apt-get upgrade -y
# Installing Nginx
sudo apt-get install -y nginx
# Installing Node.js
curl -sL https://deb.nodesource.com/setup_20.x -o nodesource_setup.sh
sudo bash nodesource_setup.sh
sudo apt install nodejs -y
# Installing PM2
sudo npm i -g pm2
cd /home/ubuntu
mkdir app
# Checking out from Version Control
git clone https://github.com/mmdcloud/aws-mediaconvert
cd aws-mediaconvert/frontend
cp -r . /home/ubuntu/app/
cd /home/ubuntu/app/
# Copying Nginx config
cp /home/ubuntu/aws-mediaconvert/terraform/scripts/default /etc/nginx/sites-available/
# Installing dependencies
sudo npm i
sudo chmod 755 /home/ubuntu
# Building the project
sudo npm run build
sudo service nginx restart