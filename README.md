# To use on fresh VM (terminal)
sed -i 's/\r$//' install-thingsboard-ssl.sh
</br>chmod +x install-thingsboard-ssl.sh

# This will show an error + usage instructions
sudo ./install-thingsboard-ssl.sh

# Correct usage
sudo ./install-thingsboard-ssl.sh --domain "myhabs26.malaysiawest.cloudapp.azure.com" --email "user@example.com" --db-password "myhabs@IOT26"

# View help
sudo ./install-thingsboard-ssl.sh --help
