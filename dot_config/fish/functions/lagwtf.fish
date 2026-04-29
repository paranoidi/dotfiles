function lagwtf --description "System responsiveness diagnostics with auto-flagged problems"
    # =========================================================
    # Output helpers (colors auto-disable when stdout is not a TTY)
    # =========================================================
    set -l use_color 1
    if not isatty stdout
        set use_color 0
    end

    function __lagwtf_c -V use_color
        # __lagwtf_c <color> <text...>
        if test $use_color -eq 1
            set_color $argv[1]
            echo -n $argv[2..-1]
            set_color normal
        else
            echo -n $argv[2..-1]
        end
    end

    function __lagwtf_header -V use_color
        echo ""
        if test $use_color -eq 1
            set_color --bold cyan
        end
        echo "──── $argv[1] ────"
        if test $use_color -eq 1
            set_color normal
        end
        if set -q argv[2]
            echo "  💡 $argv[2]"
        end
    end

    # float-aware comparison; usage: if __lagwtf_cmp $a '>' $b
    function __lagwtf_cmp
        awk -v a="$argv[1]" -v op="$argv[2]" -v b="$argv[3]" 'BEGIN {
            a+=0; b+=0
            if (op==">")  exit !(a>b)
            if (op==">=") exit !(a>=b)
            if (op=="<")  exit !(a<b)
            if (op=="<=") exit !(a<=b)
            exit 1
        }'
    end

    set -g _lagwtf_findings
    set -g _lagwtf_crit_count 0

    function __lagwtf_record -V use_color
        # __lagwtf_record <ok|warn|crit> <label> <detail> [remediation]
        set -l level $argv[1]
        set -l label $argv[2]
        set -l detail $argv[3]
        set -l remedy ""
        if set -q argv[4]
            set remedy $argv[4]
        end

        switch $level
            case ok
                __lagwtf_c green "  [OK]   "
                echo "$label — $detail"
            case warn
                __lagwtf_c yellow "  [WARN] "
                echo "$label — $detail"
                set -g _lagwtf_findings $_lagwtf_findings "WARN|$label|$detail|$remedy"
            case crit
                __lagwtf_c red "  [CRIT] "
                echo "$label — $detail"
                set -g _lagwtf_findings $_lagwtf_findings "CRIT|$label|$detail|$remedy"
                set -g _lagwtf_crit_count (math $_lagwtf_crit_count + 1)
        end
    end

    # =========================================================
    # System capacity (used for thresholds)
    # =========================================================
    set -l logical_cpus (nproc)
    set -l physical_cores $logical_cpus
    if command -v lscpu >/dev/null
        set -l _sockets (lscpu | awk -F: '/^Socket\(s\)/ {gsub(/ /,"",$2); print $2}')
        set -l _cps (lscpu | awk -F: '/^Core\(s\) per socket/ {gsub(/ /,"",$2); print $2}')
        if test -n "$_sockets" -a -n "$_cps"
            set physical_cores (math $_sockets \* $_cps)
        end
    end
    set -l mem_total_kb (awk '/^MemTotal:/ {print $2}' /proc/meminfo)
    set -l mem_total_mb (math $mem_total_kb / 1024)

    # =========================================================
    # Banner
    # =========================================================
    if test $use_color -eq 1
        set_color --bold magenta
    end
    echo "=========================================================="
    echo " System Responsiveness Diagnostics  (lagwtf)"
    echo "=========================================================="
    if test $use_color -eq 1
        set_color normal
    end
    echo "Host: $physical_cores physical core(s) / $logical_cpus logical CPU(s), "(math --scale=1 $mem_total_mb / 1024)" GiB RAM"
    echo "Each section prints raw data, then auto-flagged findings."
    echo "Final summary lists problems in priority order."

    # =========================================================
    # 1. Load average
    # =========================================================
    __lagwtf_header "LOAD AVERAGE" "1m > #cpus = saturated; trend (1m vs 15m) shows direction"
    set -l loadline (uptime)
    echo "  $loadline"
    set -l loads (uptime | string match -rg 'load average:\s*([0-9.]+),\s*([0-9.]+),\s*([0-9.]+)')
    if test (count $loads) -ge 3
        set -l l1 $loads[1]
        set -l l5 $loads[2]
        set -l l15 $loads[3]
        set -l ratio (math --scale=2 $l1 / $logical_cpus)
        echo "  load/cpus ratio (1m): $ratio"
        if __lagwtf_cmp $l1 '>' (math "2 * $logical_cpus")
            __lagwtf_record crit "Load average" "1m=$l1 > 2× logical CPUs ($logical_cpus)" "Identify hot processes; reduce parallelism"
        else if __lagwtf_cmp $l1 '>' $logical_cpus
            __lagwtf_record warn "Load average" "1m=$l1 above logical CPUs ($logical_cpus)" "Watch run queue and CPU PSI"
        else
            __lagwtf_record ok "Load average" "1m=$l1 within $logical_cpus CPUs"
        end
        if __lagwtf_cmp $l1 '>' (math "1.5 * $l15")
            __lagwtf_record warn "Load trending up" "1m=$l1 vs 15m=$l15" "Recent spike — capture top processes now"
        end
    end

    # =========================================================
    # 2. CPU pressure (PSI)
    # =========================================================
    __lagwtf_header "CPU PRESSURE (PSI)" "avg10 = % of last 10s where tasks waited for CPU"
    if test -f /proc/pressure/cpu
        cat /proc/pressure/cpu | sed 's/^/  /'
        set -l cpu_some_avg10 (awk '/^some/ {for (i=2;i<=NF;i++) if ($i ~ /^avg10=/) {split($i,a,"="); print a[2]}}' /proc/pressure/cpu)
        if test -n "$cpu_some_avg10"
            if __lagwtf_cmp $cpu_some_avg10 '>=' 30
                __lagwtf_record crit "CPU PSI some avg10" "$cpu_some_avg10%" "Tasks heavily starved for CPU"
            else if __lagwtf_cmp $cpu_some_avg10 '>=' 10
                __lagwtf_record warn "CPU PSI some avg10" "$cpu_some_avg10%" "Moderate CPU contention"
            else
                __lagwtf_record ok "CPU PSI some avg10" "$cpu_some_avg10%"
            end
        end
    else
        echo "  /proc/pressure/cpu not available"
    end

    if test -f /sys/fs/cgroup/system.slice/cpu.stat
        echo ""
        echo "  system.slice cpu.stat:"
        cat /sys/fs/cgroup/system.slice/cpu.stat | sed 's/^/    /'
        set -l throttled (awk '/^nr_throttled / {print $2}' /sys/fs/cgroup/system.slice/cpu.stat)
        set -l periods (awk '/^nr_periods / {print $2}' /sys/fs/cgroup/system.slice/cpu.stat)
        if test -n "$throttled" -a "$throttled" != "0" -a -n "$periods" -a "$periods" != "0"
            set -l pct (math --scale=1 $throttled \* 100 / $periods)
            if __lagwtf_cmp $pct '>' 5
                __lagwtf_record warn "system.slice throttled" "$pct% of periods (cumulative)" "CPUQuota may be too tight"
            end
        end
    end

    # =========================================================
    # 3. Memory pressure
    # =========================================================
    __lagwtf_header "MEMORY PRESSURE (PSI)" "memory PSI is the #1 cause of UI/mouse stalls"
    if test -f /proc/pressure/memory
        cat /proc/pressure/memory | sed 's/^/  /'
        set -l mem_some (awk '/^some/ {for (i=2;i<=NF;i++) if ($i ~ /^avg10=/) {split($i,a,"="); print a[2]}}' /proc/pressure/memory)
        set -l mem_full (awk '/^full/ {for (i=2;i<=NF;i++) if ($i ~ /^avg10=/) {split($i,a,"="); print a[2]}}' /proc/pressure/memory)
        if test -n "$mem_some"
            if __lagwtf_cmp $mem_some '>=' 5
                __lagwtf_record crit "Memory PSI some avg10" "$mem_some%" "Reclaim stalls — kill memory hogs or add RAM"
            else if __lagwtf_cmp $mem_some '>=' 1
                __lagwtf_record warn "Memory PSI some avg10" "$mem_some%" "Reclaim pressure beginning"
            else
                __lagwtf_record ok "Memory PSI some avg10" "$mem_some%"
            end
        end
        if test -n "$mem_full"; and __lagwtf_cmp $mem_full '>=' 1
            __lagwtf_record crit "Memory PSI full avg10" "$mem_full%" "Whole system stalled on memory"
        end
    else
        echo "  /proc/pressure/memory not available"
    end

    echo ""
    free -h | sed 's/^/  /'
    set -l mem_avail_kb (awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
    set -l swap_total_kb (awk '/^SwapTotal:/ {print $2}' /proc/meminfo)
    set -l swap_free_kb (awk '/^SwapFree:/ {print $2}' /proc/meminfo)
    set -l avail_pct (math --scale=1 $mem_avail_kb \* 100 / $mem_total_kb)
    echo "  available: $avail_pct% of RAM"
    if __lagwtf_cmp $avail_pct '<' 5
        __lagwtf_record crit "RAM available" "$avail_pct% free" "Free memory urgently or OOM is imminent"
    else if __lagwtf_cmp $avail_pct '<' 15
        __lagwtf_record warn "RAM available" "$avail_pct% free" "Reclaim about to engage"
    else
        __lagwtf_record ok "RAM available" "$avail_pct%"
    end
    if test "$swap_total_kb" != "0"
        set -l swap_used_kb (math $swap_total_kb - $swap_free_kb)
        set -l swap_pct (math --scale=1 $swap_used_kb \* 100 / $swap_total_kb)
        echo "  swap used: $swap_pct%"
        if __lagwtf_cmp $swap_pct '>' 50
            __lagwtf_record crit "Swap usage" "$swap_pct%" "Heavy swapping — add RAM or kill hogs"
        else if __lagwtf_cmp $swap_pct '>' 25
            __lagwtf_record warn "Swap usage" "$swap_pct%" "Working set exceeds RAM"
        end
    end

    # major page faults (delta over 1s)
    set -l pgmaj1 (awk '/^pgmajfault/ {print $2}' /proc/vmstat)
    sleep 1
    set -l pgmaj2 (awk '/^pgmajfault/ {print $2}' /proc/vmstat)
    set -l pgmaj_rate (math $pgmaj2 - $pgmaj1)
    echo "  major faults/s: $pgmaj_rate"
    if test $pgmaj_rate -gt 100
        __lagwtf_record crit "Major page faults" "$pgmaj_rate/s" "Thrashing — pages re-read from disk/swap"
    else if test $pgmaj_rate -gt 20
        __lagwtf_record warn "Major page faults" "$pgmaj_rate/s" "Some thrashing"
    end

    # =========================================================
    # 4. IO pressure
    # =========================================================
    __lagwtf_header "IO PRESSURE (PSI)" "IO PSI > 10 sustained = disk bottleneck"
    if test -f /proc/pressure/io
        cat /proc/pressure/io | sed 's/^/  /'
        set -l io_some (awk '/^some/ {for (i=2;i<=NF;i++) if ($i ~ /^avg10=/) {split($i,a,"="); print a[2]}}' /proc/pressure/io)
        if test -n "$io_some"
            if __lagwtf_cmp $io_some '>=' 30
                __lagwtf_record crit "IO PSI some avg10" "$io_some%" "Severe disk contention"
            else if __lagwtf_cmp $io_some '>=' 10
                __lagwtf_record warn "IO PSI some avg10" "$io_some%" "Disk is a bottleneck"
            else
                __lagwtf_record ok "IO PSI some avg10" "$io_some%"
            end
        end
    else
        echo "  /proc/pressure/io not available"
    end

    if command -v iostat >/dev/null
        echo ""
        echo "  iostat -xz 1 2 (last sample):"
        iostat -xz 1 2 2>/dev/null | awk 'BEGIN{section=0} /^Device/{section++} section==2 {print}' | sed 's/^/    /'
        # Flag any device with %util > 80 or await > 50ms (last sample)
        set -l io_findings (iostat -xz 1 2 2>/dev/null | awk '
            BEGIN{section=0}
            /^Device/{section++; if(section==2){for(i=1;i<=NF;i++){h[i]=$i; if($i=="%util")u=i; if($i=="await")a=i; if($i=="r_await")ra=i; if($i=="w_await")wa=i}} next}
            section==2 && NF>0 {
                util=(u?$u:0); aw=(a?$a:(ra && wa ? ($ra+$wa)/2 : 0))
                if (util>80) print "CRIT|" $1 "|%util=" util
                else if (util>50) print "WARN|" $1 "|%util=" util
                if (aw>50) print "CRIT|" $1 "|await=" aw "ms"
                else if (aw>20) print "WARN|" $1 "|await=" aw "ms"
            }')
        for line in $io_findings
            test -z "$line"; and continue
            set -l p (string split "|" $line)
            switch $p[1]
                case CRIT
                    __lagwtf_record crit "Disk $p[2]" "$p[3]" "Identify heavy IO process: sudo iotop -o"
                case WARN
                    __lagwtf_record warn "Disk $p[2]" "$p[3]"
            end
        end
    else
        echo "  iostat not installed (pkg: sysstat) — skipping per-device check"
    end

    # =========================================================
    # 5. Scheduler / runqueue
    # =========================================================
    __lagwtf_header "SCHEDULER / RUNQUEUE" "vmstat r > #cpus = oversubscribed; b > 0 sustained = IO blocked"
    if command -v vmstat >/dev/null
        set -l vmlines (vmstat 1 3 | tail -n +2)
        printf '  %s\n' $vmlines
        # average r and b across the last 2 data samples (skip first which is boot-time avg)
        set -l rb (echo $vmlines | string split \n | tail -n 2 | awk '{r+=$1; b+=$2; n++} END {if(n>0) printf "%.1f %.1f\n", r/n, b/n}')
        set -l r_avg (echo $rb | awk '{print $1}')
        set -l b_avg (echo $rb | awk '{print $2}')
        echo "  avg runqueue r=$r_avg, blocked b=$b_avg (last 2 samples)"
        if test -n "$r_avg"
            if __lagwtf_cmp $r_avg '>' (math "2 * $logical_cpus")
                __lagwtf_record crit "Runqueue depth" "r=$r_avg vs $logical_cpus CPUs" "CPU heavily oversubscribed"
            else if __lagwtf_cmp $r_avg '>' $logical_cpus
                __lagwtf_record warn "Runqueue depth" "r=$r_avg vs $logical_cpus CPUs" "Scheduler oversubscribed"
            else
                __lagwtf_record ok "Runqueue depth" "r=$r_avg"
            end
        end
        if test -n "$b_avg"; and __lagwtf_cmp $b_avg '>=' 2
            __lagwtf_record warn "Blocked tasks" "b=$b_avg" "Tasks waiting on uninterruptible IO"
        end
    else
        echo "  vmstat not installed (pkg: procps)"
    end

    # =========================================================
    # 6. Top processes
    # =========================================================
    __lagwtf_header "TOP PROCESSES" "single proc > 50% CPU or > 25% RAM = likely culprit"
    # Exclude ps/awk/lagwtf itself from listings (they spike briefly while sampling)
    set -l _self_re '^(ps|awk|lagwtf)$'
    echo "  By CPU:"
    ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu --no-headers | awk -v re="$_self_re" '$5 !~ re' | head -5 | sed 's/^/    /'
    echo "  By MEM:"
    ps -eo pid,user,%cpu,%mem,comm --sort=-%mem --no-headers | awk -v re="$_self_re" '$5 !~ re' | head -5 | sed 's/^/    /'

    set -l top_cpu (ps -eo %cpu,comm --sort=-%cpu --no-headers | awk -v re="$_self_re" '$2 !~ re' | head -1 | string trim)
    set -l top_cpu_val (echo $top_cpu | awk '{print $1}')
    set -l top_cpu_name (echo $top_cpu | awk '{print $2}')
    if test -n "$top_cpu_val"; and __lagwtf_cmp $top_cpu_val '>' 50
        __lagwtf_record warn "CPU hog" "$top_cpu_name at $top_cpu_val%" "Investigate or renice"
    end
    set -l top_mem (ps -eo %mem,comm --sort=-%mem --no-headers | awk -v re="$_self_re" '$2 !~ re' | head -1 | string trim)
    set -l top_mem_val (echo $top_mem | awk '{print $1}')
    set -l top_mem_name (echo $top_mem | awk '{print $2}')
    if test -n "$top_mem_val"; and __lagwtf_cmp $top_mem_val '>' 25
        __lagwtf_record warn "Memory hog" "$top_mem_name at $top_mem_val%" "Investigate; consider memory limit"
    end

    # =========================================================
    # 7. Interrupts (delta over 1s)
    # =========================================================
    __lagwtf_header "INTERRUPTS" "rapidly growing non-timer IRQs can cause input lag at low CPU%"
    if test -f /proc/interrupts
        set -l snap1 /tmp/lagwtf_irq1.$fish_pid
        set -l snap2 /tmp/lagwtf_irq2.$fish_pid
        cp /proc/interrupts $snap1
        sleep 1
        cp /proc/interrupts $snap2
        echo "  Top 5 IRQs by delta/s:"
        awk '
            NR==FNR { for(i=2;i<=NF-2;i++) a[$1,i]=$i; next }
            {
                sum=0
                for(i=2;i<=NF-2;i++) {
                    if (($1,i) in a) sum += ($i - a[$1,i])
                }
                if (sum>0) printf "%s\t%d\t%s\n", $1, sum, $NF
            }
        ' $snap1 $snap2 | sort -k2 -n -r | head -5 | awk '{printf "    %-8s %8d/s  %s\n", $1, $2, $3}'

        set -l hot (awk '
            NR==FNR { for(i=2;i<=NF-2;i++) a[$1,i]=$i; next }
            {
                sum=0
                for(i=2;i<=NF-2;i++) if (($1,i) in a) sum += ($i - a[$1,i])
                if (sum>10000 && $NF !~ /timer|Rescheduling/ && $(NF-1) !~ /timer/) printf "%s|%d|%s\n", $1, sum, $NF
            }
        ' $snap1 $snap2)
        rm -f $snap1 $snap2
        for line in (string split \n -- $hot)
            test -z "$line"; and continue
            set -l p (string split "|" $line)
            __lagwtf_record warn "IRQ $p[1]" "$p[2]/s ($p[3])" "Driver/hardware activity may cause latency"
        end
    else
        echo "  /proc/interrupts not available"
    end

    # =========================================================
    # 8. cgroup distribution
    # =========================================================
    __lagwtf_header "CGROUP DISTRIBUTION" "which slice/container is consuming resources"
    if command -v systemd-cgtop >/dev/null
        systemd-cgtop -n 1 -b --order=cpu 2>/dev/null | head -15 | column -t | sed 's/^/  /'
    else
        echo "  systemd-cgtop not available"
    end

    # =========================================================
    # 9. Thermal / throttling
    # =========================================================
    __lagwtf_header "THERMAL" "throttling causes lag at low CPU%"
    set -l hot_temp 0
    set -l hot_zone ""
    set -l any_zone 0
    for f in /sys/class/thermal/thermal_zone*/temp
        test -e $f; or continue
        set any_zone 1
        set -l raw (cat $f 2>/dev/null)
        test -z "$raw"; and continue
        set -l c (math --scale=1 $raw / 1000)
        set -l type_file (dirname $f)/type
        set -l ztype "?"
        if test -e $type_file
            set ztype (cat $type_file)
        end
        echo "  $ztype: $c°C"
        if __lagwtf_cmp $c '>' $hot_temp
            set hot_temp $c
            set hot_zone $ztype
        end
    end
    if test $any_zone -eq 0
        echo "  no thermal zones exposed"
    else if __lagwtf_cmp $hot_temp '>' 90
        __lagwtf_record crit "CPU temperature" "$hot_zone $hot_temp°C" "Thermal throttling — improve cooling"
    else if __lagwtf_cmp $hot_temp '>' 80
        __lagwtf_record warn "CPU temperature" "$hot_zone $hot_temp°C" "Approaching throttle threshold"
    else if __lagwtf_cmp $hot_temp '>' 0
        __lagwtf_record ok "CPU temperature" "max $hot_temp°C ($hot_zone)"
    end

    # =========================================================
    # SUMMARY
    # =========================================================
    echo ""
    if test $use_color -eq 1
        set_color --bold magenta
    end
    echo "=========================================================="
    echo " SUMMARY"
    echo "=========================================================="
    if test $use_color -eq 1
        set_color normal
    end

    if test (count $_lagwtf_findings) -eq 0
        __lagwtf_c green "✓ No problems detected."
        echo ""
        echo ""
        echo "If lag persists, investigate compositor/GPU:"
        echo "  - glxinfo | grep -i renderer"
        echo "  - journalctl -u display-manager --since '5 min ago'"
        echo "  - check vsync / monitor refresh rate"
    else
        echo "Findings (priority order):"
        echo ""
        for level in CRIT WARN
            for f in $_lagwtf_findings
                set -l p (string split "|" $f)
                test "$p[1]" = "$level"; or continue
                switch $level
                    case CRIT
                        __lagwtf_c red "  ● CRIT "
                    case WARN
                        __lagwtf_c yellow "  ● WARN "
                end
                echo "$p[2] — $p[3]"
                if test -n "$p[4]"
                    echo "          → $p[4]"
                end
            end
        end
        echo ""
        echo "Follow-up commands by symptom:"
        echo "  - memory pressure  : smem -tk | ps -eo pid,rss,comm --sort=-rss | head"
        echo "  - io pressure      : sudo iotop -o | iostat -xz 2"
        echo "  - cpu pressure     : pidstat 1 5 | perf top"
        echo "  - thermal          : sensors | watch -n1 'grep MHz /proc/cpuinfo'"
    end

    set -l exit_code 0
    if test $_lagwtf_crit_count -gt 0
        set exit_code 1
    end

    # cleanup global state and helpers
    set -e _lagwtf_findings
    set -e _lagwtf_crit_count
    functions -e __lagwtf_c __lagwtf_header __lagwtf_record

    return $exit_code
end
