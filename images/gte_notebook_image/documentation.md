# JupyterHub for dsbook & bibook

A Littlest JupyterHub (TLJH) serving the notebooks for **Data Science for
Biotechnology Students** and **Bioinformatics for Biotechnology Students**.
Both book environments are pre-installed, so nothing is built at first login.

## Configuration

    admin_user: <KTH_USERNAME>   # mandatory - becomes the JupyterHub admin
    hostname: ""                 # optional DNS name; enables HTTPS
    letsencrypt_email: ""        # required if hostname is set

## For students

Open the web link and sign in. On first login you set your own password.
Fetch material with the launch links in the books (nbgitpuller), which
update your copy without discarding your edits:

    http://<IP>/hub/user-redirect/git-pull?repo=https%3A//github.com/statisticalbiotechnology/dsbook&urlpath=lab/tree/dsbook/dsbook/intro.md&branch=main

## For the admin

    ssh -i [SSH key] ubuntu@[ip address]

    sudo /opt/tljh/hub/bin/tljh-config show
    sudo /opt/tljh/user/bin/pip install PACKAGE   # add for all users

Shared environment: `/opt/tljh/user/`. Reference clones: `/srv/books/`.