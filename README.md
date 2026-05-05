## To use on fresh VM (terminal)
sed -i 's/\r$//' install-thingsboard-ssl.sh
</br>chmod +x install-thingsboard-ssl.sh

## This will show an error + usage instructions
sudo ./install-thingsboard-ssl.sh

## Correct usage
sudo ./install-thingsboard-ssl.sh --domain "domain.example.com" --email "user@example.com" --db-password "MyPassword123"

## View help
sudo ./install-thingsboard-ssl.sh --help
