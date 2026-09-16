#!/bin/bash

USER_PACKAGES={{packages}}

# shared object storage (project-wide)
APP_CRED_ID="{{cred_id}}"
APP_CRED_SECRET="{{cred_secret}}"
OS_AUTH_URL="{{cloud_url}}/v3"
OS_PROJECT_NAME="{{project_name}}"
OS_USER_DOMAIN_NAME="{{cloud_domain}}"
OS_PROJECT_DOMAIN_NAME="{{project_domain}}"
CONTAINER_NAME="{{project_data}}"
MOUNT_DIR="/mnt/${CONTAINER_NAME}"

# rclone configuration
mkdir -p /root/.config/rclone
cat > /root/.config/rclone/rclone.conf <<EOF
[swift]
type = swift
auth = ${OS_AUTH_URL}
domain = ${OS_USER_DOMAIN_NAME}
tenant = ${OS_PROJECT_NAME}
tenant_domain = ${OS_PROJECT_DOMAIN_NAME}
application_credential_id = ${APP_CRED_ID}
application_credential_secret = ${APP_CRED_SECRET}
env_auth = false
EOF

# install requested packages
dnf install -y "${USER_PACKAGES[@]}"

# create mount point
mkdir -p "${MOUNT_DIR}"

# create systemd service
SERVICE_FILE="/etc/systemd/system/rclone-swift.service"

cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Rclone mount for OpenStack Swift storage
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/rclone mount swift:${CONTAINER_NAME} ${MOUNT_DIR} \\
    --allow-other \\
    --uid 1000 \\
    --gid 1000 \\
    --vfs-cache-mode full \\
    --vfs-cache-max-age 24h \\
    --vfs-cache-max-size 10G \\
    --buffer-size 256M \\
    --log-file /var/log/rclone-swift.log \\
    --config /root/.config/rclone/rclone.conf
ExecStop=/bin/fusermount -u ${MOUNT_DIR}
Restart=on-failure
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

# HPC packages
dnf -y install environment-modules openmpi munge slurm slurm-slurmd slurm-slurmctld slurm-slurmdbd

# initialize munge
/usr/sbin/create-munge-key 

# SLURM service account
export SLURM_UID=980
groupadd -g $SLURM_UID slurm
useradd -r -m -c "SLURM workload manager" -d /var/lib/slurm -u $SLURM_UID -g slurm -s /bin/bash slurm

# SLURM config
HOSTNAME=$(hostname)
NODELINE=$(slurmd -C | grep NodeName)

cat <<EOF >/etc/slurm/slurm.conf
ClusterName=${HOSTNAME}
SlurmctldHost=${HOSTNAME}
MpiDefault=pmix
ProctrackType=proctrack/cgroup
ReturnToService=1
SlurmctldPidFile=/var/run/slurm/slurmctld.pid
SlurmctldPort=6817
SlurmdPidFile=/var/run/slurm/slurmd.pid
SlurmdPort=6818
SlurmdSpoolDir=/var/spool/slurm/d
SlurmUser=root
StateSaveLocation=/var/spool/slurm/ctld
SwitchType=switch/none
TaskPlugin=task/none
InactiveLimit=0
KillWait=30
MinJobAge=300
SlurmctldTimeout=120
SlurmdTimeout=300
Waittime=0
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_CPU_Memory
DefMemPerCPU=2048
AccountingStorageType=accounting_storage/none
AccountingStoreFlags=job_comment
JobCompType=jobcomp/none
JobAcctGatherFrequency=30
JobAcctGatherType=jobacct_gather/none
SlurmctldDebug=info
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdDebug=info
SlurmdLogFile=/var/log/slurm/slurmd.log
${NODELINE} State=UNKNOWN
PartitionName=main Nodes=ALL Default=YES MaxTime=INFINITE State=UP
EOF

# enable and start services
systemctl daemon-reload

for svc in rclone-swift munge slurmctld slurmd; do
  systemctl enable ${svc}.service
  systemctl start ${svc}.service
done
