# UBUNTU image version 24.04 with persistent storage

This is the basic UBUNTU 24.04 + additional packages you want to add.
In order to use this image, use your **ssh key**
to login into the service.

`ssh -i [SSH key] ubuntu@[ip address]`

## Persistent storage

This image does also mount persistent storage available within
the instance at `/mnt/project-data`
and this storage is available for all instances within this project
and is not deleted when you delete a service.

## Configuration

You can add additional packages in the configuration.
