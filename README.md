<b>To use on a fresh VM (terminal):</b>
</br>sed -i 's/\r$//' install-thingsboard-ssl.sh
</br>chmod +x install-thingsboard-ssl.sh
</br>sudo ./install-thingsboard-ssl.sh
</br></br><b>Use defaults (no arguments needed):</b>
</br>sudo ./install-thingsboard-ssl.sh
</br></br><b>Override with custom values:</b>
</br>sudo ./install-thingsboard-ssl.sh --domain "custom.example.com" --email "user@example.com" --db-password "MyPassword123"
</br></br><b>See help:</b>
</br>sudo ./install-thingsboard-ssl.sh --help
</br></br><b>You can pass any combination, only the arguments you provide will override the defaults. For example, to change just the domain:</b>
</br>sudo ./install-thingsboard-ssl.sh --domain "other.cloudapp.azure.com"
