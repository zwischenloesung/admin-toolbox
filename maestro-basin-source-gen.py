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
def parse_stdin(do_override_uuids=False):
    """Parse lines of form:
       CombinedSensorName
       Index
          subname unit [type]
    """
    if do_override_uuids:
        print("Not implemented in this context yet.")
    lines = [l.rstrip() for l in sys.stdin if l.strip()]
    if not lines:
        return None, None, None, None, None, None, []
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
    return combined, index, None, None, None, None, subs

def parse_interactive(do_override_uuids):

    combined_name = slugify(input("Enter CombinedSensor type name (empty to finish): ").strip())
    if not combined_name:
        return None, None, None, None, None, None, []
    index = input("Enter the source index ('-' to skip, [0000]): ").strip() or "0000"
    type_displname = input(
        "Enter type display name (empty to skip all display names): "
    ).strip()
    if type_displname:
        i = f"{type_displname} {index}" if index else type_displname
        tmp = input(f"Enter source display name ([{i}]): ").strip()
        source_displname = tmp if tmp else i
    else:
        type_displname = None
        source_displname = None
    if do_override_uuids:
        combined_type_uuid = input(
            "Enter sourcetype UUID (empty means autogenerate): "
        ).strip()
        combined_source_uuid = input("Enter source UUID (empty means autogenerate): ").strip()
    else:
        combined_type_uuid = None
        combined_source_uuid = None
    sub_sensors = []
    while True:
        sub_in = input("Enter sub-sensor name (empty to finish this CombinedSensor): ").strip()
        if not sub_in:
            break
        sub_name = slugify(sub_in)
        if do_override_uuids:
            sub_type_uuid = input("Enter sourcetype UUID (empty means autogenerate): ").strip()
            sub_source_uuid = input("Enter source UUID (empty means autogenerate): ").strip()
        else:
            sub_type_uuid = None
            sub_source_uuid = None
        if type_displname:
            sub_type_displname = input(
                f"Enter sourcetype display name ([{sub_in}] if empty): "
            ).strip()
            sub_type_displname = sub_type_displname if sub_type_displname else sub_in
            i = f"{sub_type_displname} {index}" if index else type_displname
            sub_source_displname = input(
                f"Enter source display name ([{i}]): "
            ).strip()
            sub_source_displname = sub_source_displname if sub_source_displname else i
        else:
            sub_type_displname = None
            sub_source_displname = None
        dev_type = input("Enter device-type (empty means autogenerate): ").strip()
        u = guess_unit(sub_name)
        unit = input(f"Enter unit for '{sub_name}' [{u}]: ").strip()
        if not unit:
            unit = u
        stype = input(f"Enter type for '{sub_name}' (default float): ").strip() or "float"
        sub_meta = parse_meta()

        skipit = input("Please confirm the entry ([Y/n]): ").strip()
        if not skipit.lower() == "n":
            sub_sensors.append((
                sub_name,
                sub_type_uuid,
                sub_source_uuid,
                sub_type_displname,
                sub_source_displname,
                dev_type,
                unit,
                stype,
                sub_meta
            ))
    return (
        combined_name,
        index,
        combined_type_uuid,
        combined_source_uuid,
        type_displname,
        source_displname,
        sub_sensors
    )

# Quoted string wrapper
class Quoted(str): pass
def quoted_presenter(dumper, data):
    return dumper.represent_scalar("tag:yaml.org,2002:str", data, style="'")
yaml.add_representer(Quoted, quoted_presenter)

def q(s): return Quoted(str(s))

def parse_meta():
    meta = {}
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
            meta[m] = input(f"Now enter the value for '{m}': ").strip()
    return meta

def guess_unit(name):
    for k, v in units.items():
        if k in name.lower():
            return v
    return None

# limitting depth is not really needed, but might be interesting later for non-interactive
def quote_textlike(obj, depth=None):
    # stop and return None if obj is empty
    if not obj:
        return None

    # stop descending if depth is a non-None or negative
    if depth is not None and depth < 0:
        return obj

    # dict: descend into values
    if isinstance(obj, dict):
        if depth == 0:
            return {k: q(v) if isinstance(v, str) else v for k, v in obj.items()}
        next_depth = None if depth is None else depth - 1
        return {k: quote_textlike(v, next_depth) for k, v in obj.items()}

    # list/tuple: same logic
    if isinstance(obj, (list, tuple)):
        if depth == 0:
            return [q(v) if isinstance(v, str) else v for v in obj]
        next_depth = None if depth is None else depth - 1
        seq = [quote_textlike(v, next_depth) for v in obj]
        return type(obj)(seq)

    # leaf: quote strings, leave everything else
    if isinstance(obj, str):
        return q(obj)
    return obj


def produce_output(
        combined_name,
        index,
        combined_type_uuid,
        combined_source_uuid,
        type_displname,
        source_displname,
        sub_sensors,
        do_prepend_parent=False
    ):
    sources = []
    sourcetypes = []
    mapping = {}

    # Combined sensor
    st_combined_uuid = combined_type_uuid if combined_type_uuid else gen_uuid()
    src_combined_uuid = combined_source_uuid if combined_source_uuid else gen_uuid()

    indexs = "" if index == "-" else f"-{index}"
    tmp = {
        "uuid": q(src_combined_uuid),
        "name": q(f"{combined_name}{indexs}"),
        "parentname": q(""),
        "parentuuid": q(""),
        "typeuuid": q(st_combined_uuid),
    }
    if source_displname:
        tmp["meta"] = { "displayname": { "en": quote_textlike(source_displname) } }
    sources.append(tmp)
    tmp = {
        "uuid": q(st_combined_uuid),
        "name": q(combined_name),
        "class": q("CombinedSensor"),
        "devicetype": q(combined_name),
        "type": None,
        "unit": None,
    }
    if type_displname:
        tmp["meta"] = { "displayname": { "en": quote_textlike(type_displname) } }
    sourcetypes.append(tmp)

    # Sub-sensors
    for (
        sub_name,
        sub_type_uuid,
        sub_uuid,
        sub_type_displname,
        sub_source_displname,
        dev_type,
        unit,
        stype,
        sub_source_meta
    ) in sub_sensors:
        st_uuid = sub_type_uuid if sub_type_uuid else gen_uuid()
        src_uuid = sub_uuid if sub_uuid else gen_uuid()
        src_name = f"{combined_name}{indexs}-{sub_name}" if do_prepend_parent else sub_name
        sub_type_meta = {}

        if sub_type_displname:
            # TODO only "en" currently supported and no way to turn the input question off
            sub_source_meta["displayname"] = { "en": sub_source_displname }
            sub_type_meta["displayname"] = { "en": sub_type_displname }
        dt = dev_type if dev_type else f"{combined_name}-{sub_name}"

        #TODO: in non-interacte we might want to limit the depth of quote_textlike()..!?
        tmp = {
            "uuid": q(src_uuid),
            "name": q(src_name),
            "parentname": q(f"{combined_name}{indexs}"),
            "parentuuid": q(src_combined_uuid),
            "typeuuid": q(st_uuid),
        }
        if sub_source_meta:
            tmp["meta"] = quote_textlike(sub_source_meta),
        sources.append(tmp)
        tmp = {
            "uuid": q(st_uuid),
            "name": q(f"{combined_name}-{sub_name}"),
            "class": q("Sensor"),
            "devicetype": q(dt),
            "type": stype,  # bare literal
            "unit": q(unit),
        }
        if sub_type_meta:
            tmp["meta"] = quote_textlike(sub_type_meta)
        sourcetypes.append(tmp)
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
        o = input("Autogenerate all UUIDs? ([Y/n]): ").strip()
        if o.lower() == "n":
            do_override_uuids = True
        else:
            do_override_uuids = False
        d = input("Prepend parent name and index to the source sub-name? ([y/N]): ").strip()
        if d.lower() == "y":
            do_prepend_parent = True
        parse = parse_interactive

    sensor_libs = []

    do_continue = True
    while do_continue:
        combined_name, index, tuuid, suuid, tdname, sdname, sub_sensors = parse(
            do_override_uuids
        )
        if not combined_name:
            do_continue = False
        else:
            sensor_libs.append([
                combined_name,
                index,
                tuuid,
                suuid,
                tdname,
                sdname,
                sub_sensors
            ])
    print(sensor_libs)

    for s in sensor_libs:
        combined_name = s[0]
        index = s[1]
        tuuid = s[2]
        suuid = s[3]
        tdname = s[4]
        sdname = s[5]
        sub_sensors = s[6]
        produce_output(
            combined_name,
            index,
            tuuid,
            suuid,
            tdname,
            sdname,
            sub_sensors, do_prepend_parent)



if __name__ == "__main__":
    main()

