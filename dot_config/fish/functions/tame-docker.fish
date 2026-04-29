function tame-docker
    echo "🔥 Docker taming"

    # -----------------------------
    # 1. Check current Docker cgroup driver
    # -----------------------------
    set driver (docker info 2>/dev/null | awk -F': ' '/Cgroup Driver/ {print $2}')

    if test "$driver" != "systemd"
        echo "Docker cgroup driver is not systemd ($driver)"
        echo "Applying daemon.json fix..."

        set json '{"exec-opts": ["native.cgroupdriver=systemd"]}'

        if test -f /etc/docker/daemon.json
            set existing (cat /etc/docker/daemon.json)

            if test "$existing" = "$json"
                echo "daemon.json already correct"
            else
                echo $json | sudo tee /etc/docker/daemon.json
            end
        else
            echo $json | sudo tee /etc/docker/daemon.json
        end

        set restart_docker 1
    else
        echo "Docker cgroup driver already systemd"
        set restart_docker 0
    end

    # -----------------------------
    # 2. Apply system-wide CPU quota (idempotent)
    # Reserve 1 physical core for the OS
    # -----------------------------
    set _sockets (lscpu | awk -F: '/^Socket\(s\)/ {gsub(/ /,"",$2); print $2}')
    set _cores_per_socket (lscpu | awk -F: '/^Core\(s\) per socket/ {gsub(/ /,"",$2); print $2}')
    set _physical_cores (math $_sockets \* $_cores_per_socket)
    set target_cpu_quota (string join "" (math (math $_physical_cores - 1) \* 100) "%")
    echo "Detected $_physical_cores physical core(s), reserving 1 for OS → CPUQuota=$target_cpu_quota"

    set current_cpu (systemctl show system.slice -p CPUQuota | string split "=")[2]

    if test "$current_cpu" != "$target_cpu_quota"
        echo "Setting CPUQuota=$target_cpu_quota on system.slice"
        sudo systemctl set-property system.slice CPUQuota=$target_cpu_quota
    else
        echo "CPUQuota already $target_cpu_quota"
    end

    # -----------------------------
    # 3. Apply IO weight (idempotent)
    # -----------------------------
    set current_io (systemctl show system.slice -p IOWeight | string split "=")[2]

    if test "$current_io" != "50"
        echo "Setting IOWeight=50 on system.slice"
        sudo systemctl set-property system.slice IOWeight=50
    else
        echo "IOWeight already 50"
    end

    # -----------------------------
    # 4. Restart services only if needed
    # -----------------------------
    if test "$restart_docker" = 1
        echo "Restarting Docker..."
        sudo systemctl restart docker
    else
        echo "Docker restart not required"
    end

    echo "Restarting containerd (safe refresh)"
    sudo systemctl restart containerd

    # -----------------------------
    # 5. Verification
    # -----------------------------
    echo "🔍 Verification"

    echo -n "CPUQuota: "
    systemctl show system.slice -p CPUQuota

    echo -n "IOWeight: "
    systemctl show system.slice -p IOWeight

    echo -n "Docker cgroup driver: "
    docker info 2>/dev/null | awk -F': ' '/Cgroup Driver/ {print $2}'

    echo "💧 Done"
end
