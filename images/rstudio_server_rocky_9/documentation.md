# RStudio server

This image is based on Rocky Linux 9.
On top of this image, RStudio server and R
is installed without any addons.
You can reach the web portal for this image
using http://<IP address>:8787 for the created user.

## Adding more users

More users can be added in the configuration script
by adding extra lines in usernames and passwords.
By default one user is added with username rstudio password rstudio

## Version

By default, this installs the 2025.09.2-418 version of RStudio server, but
you can change what version you do want by
setting versions to YYYY.MM.DD-[BUILD]
Some information can be obtained at [https://dailies.rstudio.com/rstudio/cucumberleaf-sunflower/electron/noble-amd64/](https://dailies.rstudio.com/rstudio/cucumberleaf-sunflower/electron/noble-amd64/)

## R Packages

Extra R packages can be defined for installation in the configuration script.

## YAML format

```
version: [Version]
users:
  - username: [username]
    password: [password]
Rpackages:
  - [Package name]
```
