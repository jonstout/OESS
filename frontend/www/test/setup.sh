#!/usr/bin/bash

# Install and select required node.js version
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.35.1/install.sh | bash
nvm install 8.11.1
nvm use v8.11.1

# Install dependencies for puppeteer
sudo yum install gtk3 gtk3-devel

# Install any npm dependencies
npm install
