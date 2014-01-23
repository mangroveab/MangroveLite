## MangroveLite

### Install (Git)

    # Install git and clone MangroveLite
    aptitude install git
    git clone https://github.com/mangrove/MangroveLite.git
    cd MangroveLite
    
    # Edit options to enter server IP, MySQL password etc.
    nano options.conf
    
    # Make all scripts executable.
    chmod 700 *.sh
    chmod 700 options.conf
    
    # Install LAMP stack.
    ./install.sh
    
    # Add a new Linux user and add domains to the user.
    adduser johndoe
    ./domain.sh add johndoe yourdomain.com
    ./domain.sh add johndoe subdomain.yourdomain.com