# Basic UBUNTU image version 24.04 for UQSA

This is the basic UBUNTU 24.04 + wget, bash, compilers and make.
It also installs R and openmpi, so that mpirun on Rscripts is available.



In order to use this image, use your **ssh key**
to login into the service.

`ssh -i [SSH key] ubuntu@[ip address]`

## Configuration

You can add additional packages in the configuration.

Rpackages (yaml list) will be installed in R, from CRAN.
Rpackages with a slash in them `/` will be installed from github.