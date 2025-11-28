#!/usr/bin/env python3

# usage: interactive mode - or short cut:
#
# echo "WittBoy_GW2000A
# 0000
#    humidityin %RH float
#    baromrelin hPa float" | ./$0
#

import sys
import uuid
import yaml
import json
import re

# Configurable indent prefix
leading_spaces = "      "  # 6 spaces

units = {
    'temp': '°C',
    'humid': '%',
    'ph': 'pH',
}

def gen_uuid():
    return str(uuid.uuid4())

def slugify(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]", "_", name.strip().replace(" ", "_"))

def parse_stdin():
    """Parse lines of form:
       CombinedSensorName
       Index
          subname unit [type]
    """
    lines = [l.rstrip() for l in sys.stdin if l.strip()]
    if not lines:
        return None, None, []
    combined = slugify(lines[0])
    index = lines[1].strip() if len(lines) > 1 else "0000"
    subs = []
    for line in lines[2:]:
        parts = line.strip().split(None, 3)
        if not parts:
            continue
        subname = slugify(parts[0])
        unit = parts[1].strip() if len(parts) > 1 else ""
        stype = parts[2].strip() if len(parts) > 2 else "float"
        subs.append((subname, unit, stype))
    return combined, index, subs

def parse_interactive():

    combined_name = slugify(input("Enter CombinedSensor type name (empty to finish): ").strip())
    if not combined_name:
        return None, None, None
    index = input("Enter the CombinedSensor index ('-' to skip, [0000]): ").strip() or "0000"
    sub_sensors = []
    while True:
        sub_in = input("Enter sub-sensor name (empty to finish this CombinedSensor): ").strip()
        if not sub_in:
            break
        sub_name = slugify(sub_in)
        u = guess_unit(sub_name)
        unit = input(f"Enter unit for '{sub_name}' [{u}]: ").strip()
        if not unit:
            unit = u
        stype = input(f"Enter type for '{sub_name}' (default float): ").strip() or "float"
        meta = parse_meta()

        sub_sensors.append((sub_name, unit, stype, meta))
    return combined_name, index, sub_sensors

# Quoted string wrapper
class Quoted(str): pass
def quoted_presenter(dumper, data):
    return dumper.represent_scalar("tag:yaml.org,2002:str", data, style="'")
yaml.add_representer(Quoted, quoted_presenter)

def q(s): return Quoted(str(s))

def parse_meta():
    meta = None
    hasMeta = True
    while hasMeta:
        if not meta:
            m = input("Enter meta JSON (empty to skip, a key or JSON): ").strip()
        else:
            m = input("Enter meta JSON (empty to skip or the next key): ").strip()
        if not m:
            return meta
        elif m.startswith("{") or m.startswith("["):
            if not meta:
                try:
                    m = json.loads(m)
                except:
                    input("WARNING/ERROR: Unable to parse JSON, please try again..")
                return m
            else:
                input("WARNING/ERROR: JSON found but meta not empty, please try again..")
        else:
            if not meta:
                meta = {}
            meta[m] = input(f"Now enter the value for '{m}': ").strip()
    return meta

def guess_unit(name):
    for k, v in units.items():
        if k in name.lower():
            return v
    return None

def parse_input():
    if not sys.stdin.isatty():
        combined_name, index, sub_sensors = parse_stdin()
    else:
        combined_name, index, sub_sensors = parse_interactive()
    return combined_name, index, sub_sensors


def produce_output(combined_name, index, sub_sensors):
    sources = []
    sourcetypes = []
    mapping = {}

    # Combined sensor
    st_combined_uuid = q(gen_uuid())
    src_combined_uuid = q(gen_uuid())
    combined_name_q = q(combined_name)

    if index == "-":
        indexs = ""
    else:
        indexs = f"-{index}"
    sources.append({
        "uuid": src_combined_uuid,
        "name": q(f"{combined_name}{indexs}"),
        "parentname": q(""),
        "parentuuid": q(""),
        "typeuuid": st_combined_uuid,
    })
    sourcetypes.append({
        "uuid": st_combined_uuid,
        "name": combined_name_q,
        "class": q("CombinedSensor"),
        "devicetype": combined_name_q,
        "type": None,
        "unit": None,
    })

    # Sub-sensors
    for sub_name, unit, stype, meta in sub_sensors:
        st_uuid = q(gen_uuid())
        src_uuid = q(gen_uuid())
        src_name = f"{combined_name}{indexs}-{sub_name}"

        sources.append({
            "uuid": src_uuid,
            "name": q(src_name),
            "parentname": q(f"{combined_name}{indexs}"),
            "parentuuid": src_combined_uuid,
            "typeuuid": st_uuid,
            "meta": meta,
        })
        sourcetypes.append({
            "uuid": st_uuid,
            "name": q(f"{combined_name}-{sub_name}"),
            "class": q("Sensor"),
            "devicetype": q(f"{combined_name}-{sub_name}"),
            "type": stype,  # bare literal
            "unit": q(unit),
        })
        mapping[sub_name] = src_uuid

    data = {"sources": sources, "sourcetypes": sourcetypes}

    print("\n--- YAML output ---")
    raw_yaml = yaml.dump(
        data,
        sort_keys=False,
        default_flow_style=False,
        allow_unicode=True,
        width=80,
    )
    print("".join(leading_spaces + line for line in raw_yaml.splitlines(True)))

#    print("\n--- Mapping (Python dict) ---")
#    print("uuid_map = {")
#    for k, v in mapping.items():
#        print(f"    '{k}': '{v}',")
#    print("}")

def main():

    sensor_libs = []

    do_continue = True
    while do_continue:
        combined_name, index, sub_sensors = parse_input()
        if not combined_name:
            do_continue = False
        else:
            sensor_libs.append([ combined_name, index, sub_sensors ])
    print(sensor_libs)

    for s in sensor_libs:
        combined_name = s[0]
        index = s[1]
        sub_sensors = s[2]
        produce_output(combined_name, index, sub_sensors)



if __name__ == "__main__":
    main()

