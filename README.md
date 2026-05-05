To use on a fresh VM:

sed -i 's/\r$//' install-thingsboard-ssl.sh
chmod +x install-thingsboard-ssl.sh
sudo ./install-thingsboard-ssl.sh


Use defaults (no arguments needed):

sudo ./install-thingsboard-ssl.sh
 

Override with custom values:

sudo ./install-thingsboard-ssl.sh --domain "custom.example.com" --email "user@example.com" --db-password "MyPassword123"


See help:

sudo ./install-thingsboard-ssl.sh --help


You can pass any combination — only the arguments you provide will override the defaults. For example, to change just the domain:

sudo ./install-thingsboard-ssl.sh --domain "other.cloudapp.azure.com"
