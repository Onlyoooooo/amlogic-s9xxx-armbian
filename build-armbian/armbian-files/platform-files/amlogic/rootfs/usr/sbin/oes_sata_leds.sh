#!/bin/ash

# --- 配置区 ---

# 1. 硬盘 LED 映射
# 定义一个辅助函数来获取 LED 文件路径
# 根据硬盘的ATA ID (例如 ata1, ata2) 映射到对应的物理 LED 灯文件路径
# 请根据你的硬件配置修改这些路径和ATA ID的对应关系
get_disk_led_file() {
    local ata_id_val="$1"
    case "$ata_id_val" in
        "ata1") echo "/sys/class/leds/green:disk/brightness" ;;
        "ata2") echo "/sys/class/leds/green:disk_1/brightness" ;;
        "ata3") echo "/sys/class/leds/green:disk_2/brightness" ;;
        # 如果你有更多硬盘位，可以在这里继续添加映射，例如：
        # "ata4") echo "/sys/class/leds/green:disk_3/brightness" ;; # 假设有更多的 disk LEDs
        *) echo "" ;; # 未知ATA ID，返回空字符串
    esac
}

# --- 核心函数 ---

# 设置 LED 亮度函数
# 参数: $1 为 LED 文件路径, $2 为亮度 (0 或 1)
set_led_brightness() {
    local led_path="$1"
    local brightness="$2"
    # 检查LED文件是否存在且可写，防止脚本因文件不存在而崩溃
    if [ -f "$led_path" ] && [ -w "$led_path" ]; then
        local current_brightness=$(cat "$led_path" 2>/dev/null)
        if [ "$current_brightness" != "$brightness" ]; then
            echo "调试：正在尝试设置LED [${led_path}] 亮度为 ${brightness}"
            echo "$brightness" > "$led_path"
            echo "LED [${led_path}] 已成功设置为 ${brightness}"
        else
            echo "调试：LED [${led_path}] 亮度已是 ${brightness}，无需改变。"
        fi
    else
        echo "警告：LED文件 [${led_path}] 不存在或不可写，无法设置亮度。"
    fi
}

# --- 监控逻辑 ---

# 硬盘 LED 监控的主函数
# 这个函数会持续运行，进行硬盘检测和LED控制
monitor_disk_leds_loop() {
    echo "启动SATA硬盘LED监控主循环..."

    while true; do
        echo "--- 开始新一轮活跃硬盘ATA ID检查 ---"
        local detected_atas="" # 用于存储当前循环中检测到的所有活跃ATA ID

        # 使用 ls -l /sys/block 结合 grep 和 awk 提取所有活跃的 ataX ID
        local active_ata_ids=$(ls -l /sys/block 2>/dev/null | \
                               grep -i "ata" | \
                               awk -F'ata' '{print "ata"$2}' | \
                               awk '{print $1}' | \
                               cut -d'/' -f1 | \
                               sort -u || true)

        echo "调试：原始检测到的 active_ata_ids 字符串: [${active_ata_ids}]"

        if [ -n "$active_ata_ids" ]; then
            for ata_id_raw in $active_ata_ids; do
                # 确保提取的ata_id只包含"ata"后跟数字，避免非预期字符
                ata_id=$(echo "$ata_id_raw" | grep -o 'ata[0-9]\+' || true)
                
                if [ -n "$ata_id" ]; then
                    echo "调试：处理ATA ID: ${ata_id}"
                    local led_file=$(get_disk_led_file "$ata_id")
                    
                    if [ -n "$led_file" ]; then
                        echo "调试：找到 ${ata_id} 对应的LED文件: ${led_file}"
                        set_led_brightness "$led_file" 1 # 检测到活跃硬盘，点亮对应LED
                        detected_atas="${detected_atas} ${ata_id}" # 记录已检测到的活跃ATA ID
                    else
                        echo "警告：活跃ATA ID ${ata_id} 未映射到任何LED文件，跳过设置。"
                    fi
                else
                    echo "调试：跳过无效或非标准ATA ID: ${ata_id_raw}"
                fi
            done
        else
            echo "未检测到任何活跃的SATA硬盘（/sys/block下无ata相关设备）。"
        fi

        echo "本轮最终检测并点亮的ATA ID列表 (detected_atas): [${detected_atas:-'无'}]"
        echo "--- 检查并关闭未检测到活跃ATA ID的LED ---"

        # 遍历所有可能存在的ATA ID，确保未检测到活跃的硬盘LED熄灭
        # 这个范围应与 get_disk_led_file 函数中的映射范围一致
        # 例如：1 2 3 4 5 6 7 8，根据你的主板SATA接口数量来设置
        for ata_num in 1 2 3; do # 保持与get_disk_led_file映射的示例范围一致
            local ata_id_to_check="ata${ata_num}"
            local led_file_to_check=$(get_disk_led_file "$ata_id_to_check")
            
            if [ -n "$led_file_to_check" ]; then
                # 检查当前的ATA ID是否在本轮 detected_atas 列表中被发现为活跃
                echo "调试：检查是否关闭LED：${ata_id_to_check} 对应的LED文件: ${led_file_to_check}"
                if ! echo "$detected_atas" | grep -q "\b${ata_id_to_check}\b"; then
                    echo "ATA ID ${ata_id_to_check} 未检测到活跃硬盘，关闭对应LED: ${led_file_to_check}"
                    set_led_brightness "$led_file_to_check" 0 # ATA端口不活跃，关闭对应LED
                else
                    echo "调试：ATA ID ${ata_id_to_check} 在 detected_atas 中，LED保持点亮状态。"
                fi
            else
                echo "调试：ATA ID ${ata_id_to_check} 未映射到LED文件，跳过关闭检查。"
            fi
        done
        echo "本轮循环结束，等待3秒后进行下一轮检查..."
        sleep 3 # 每 3 秒检查一次
    done
}

# 启动监控循环
# 注意：此脚本会一直运行，直到手动停止。
# 如需在后台运行，请使用 'nohup ./your_script_name.sh &'
# 如需开机自启动或定期执行，请配置系统服务（如systemd, cron等）。
monitor_disk_leds_loop