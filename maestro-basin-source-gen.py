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

# TODO parse_stdin() supports far less features than parse_interactive()..
def parse_stdin():
    """Parse lines of form:
       CombinedSensorName
       Index
          subname unit [type]
    """
    lines = [l.rstrip() for l in sys.stdin if l.strip()]
    if not lines:
        return None, None, None, None, []
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
    return combined, index, None, None, subs

def parse_interactive():

    combined_name = slugify(input("Enter CombinedSensor type name (empty to finish): ").strip())
    if not combined_name:
        return None, None, None, None, []
    index = input("Enter the CombinedSensor index ('-' to skip, [0000]): ").strip() or "0000"
    combined_type_uuid = input("Enter sourcetype UUID (empty means autogenerate): ").strip()
    combined_source_uuid = input("Enter source UUID (empty means autogenerate): ").strip()
    sub_sensors = []
    while True:
        sub_in = input("Enter sub-sensor name (empty to finish this CombinedSensor): ").strip()
        if not sub_in:
            break
        sub_name = slugify(sub_in)
        sub_type_uuid = input("Enter sourcetype UUID (empty means autogenerate): ").strip()
        sub_source_uuid = input("Enter source UUID (empty means autogenerate): ").strip()
        displ_name = input("Enter display name (empty to skip): ").strip()
        dev_type = input("Enter device-type (empty means autogenerate): ").strip()
        u = guess_unit(sub_name)
        unit = input(f"Enter unit for '{sub_name}' [{u}]: ").strip()
        if not unit:
            unit = u
        stype = input(f"Enter type for '{sub_name}' (default float): ").strip() or "float"
        meta = parse_meta()

        skipit = slugify(input("Please confirm the entry ([Y/n]): ").strip())
        if not skipit.lower() == "n":
            sub_sensors.append((
                sub_name,
                sub_type_uuid,
                sub_source_uuid,
                displ_name,
                dev_type,
                unit,
                stype,
                meta
            ))
    return combined_name, index, combined_type_uuid, combined_source_uuid, sub_sensors

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


def produce_output(
        combined_name,
        index,
        combined_type_uuid,
        combined_source_uuid,
        sub_sensors,
        do_prepend_parent=False
    ):
    sources = []
    sourcetypes = []
    mapping = {}

    # Combined sensor
    if combined_type_uuid:
        st_combined_uuid = combined_type_uuid
    else:
        st_combined_uuid = q(gen_uuid())
    if combined_source_uuid:
        src_combined_uuid = combined_source_uuid
    else:
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
    for (
        sub_name,
        sub_type_uuid,
        sub_uuid,
        displ_name,
        dev_type,
        unit,
        stype,
        meta
    ) in sub_sensors:
        if sub_type_uuid:
            st_uuid = sub_type_uuid
        else:
            st_uuid = q(gen_uuid())
        if sub_uuid:
            src_uuid = sub_uuid
        else:
            src_uuid = q(gen_uuid())
        if do_prepend_parent:
            src_name = f"{combined_name}{indexs}-{sub_name}"
        else:
            src_name = sub_name
        if displ_name:
            # TODO only "en" currently supported and no way to turn the input question off
            meta["displayname"] = { "en": displ_name }
        if dev_type:
            dt = dev_type
        else:
            dt = f"{combined_name}-{sub_name}"

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
            "devicetype": q(dt),
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

    if not sys.stdin.isatty():
        parse = parse_stdin
    else:
        do_prepend_parent = False
        d = slugify(input("Prepend parent name and index to the source sub-name? ([y/N]): ").strip())
        if d.lower() == "y":
            do_prepend_parent = True
        parse = parse_interactive

    sensor_libs = []

    do_continue = True
    while do_continue:
        combined_name, index, tuuid, suuid, sub_sensors = parse()
        if not combined_name:
            do_continue = False
        else:
            sensor_libs.append([ combined_name, index, tuuid, suuid, sub_sensors ])
    print(sensor_libs)

    for s in sensor_libs:
        combined_name = s[0]
        index = s[1]
        tuuid = s[2]
        suuid = s[3]
        sub_sensors = s[4]
        produce_output(combined_name, index, tuuid, suuid, sub_sensors, do_prepend_parent)



if __name__ == "__main__":
    main()

