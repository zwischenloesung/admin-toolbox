#!/usr/bin/env python3
import sys
import uuid
import yaml
import re

def gen_uuid():
    return str(uuid.uuid4())

def slugify(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]", "_", name.strip().replace(" ", "_"))

def parse_stdin():
    """Parse lines of form 'CombinedSensor' and '   subname unit'"""
    lines = [l.rstrip() for l in sys.stdin if l.strip()]
    if not lines:
        return None, []
    combined = slugify(lines[0])
    subs = []
    for line in lines[1:]:
        parts = line.strip().split(None, 1)
        if not parts:
            continue
        subname = slugify(parts[0])
        unit = parts[1].strip() if len(parts) > 1 else ""
        subs.append((subname, unit))
    return combined, subs

def main():
    # Either parse stdin or fall back to interactive
    if not sys.stdin.isatty():
        combined_name, sub_sensors = parse_stdin()
    else:
        combined_name = slugify(input("Enter CombinedSensor name: ").strip())
        sub_sensors = []
        while True:
            sub_in = input("Enter sub-sensor name (empty to finish): ").strip()
            if not sub_in:
                break
            sub_name = slugify(sub_in)
            unit = input(f"Enter unit for '{sub_name}': ").strip()
            sub_sensors.append((sub_name, unit))

    sources = []
    sourcetypes = []
    mapping = {}

    # Combined sensor sourcetype + source
    st_combined_uuid = gen_uuid()
    src_combined_uuid = gen_uuid()

    sources.append({
        "uuid": src_combined_uuid,
        "name": f"{combined_name}-0000",
        "parentname": "",
        "parentuuid": "",
        "typeuuid": st_combined_uuid,
    })
    sourcetypes.append({
        "uuid": st_combined_uuid,
        "name": combined_name,
        "class": "CombinedSensor",
        "devicetype": combined_name,
        "type": None,
        "unit": None,
    })

    # Sub sensors
    for sub_name, unit in sub_sensors:
        st_uuid = gen_uuid()
        src_uuid = gen_uuid()
        src_name = f"{combined_name}-{sub_name}-0000"

        sources.append({
            "uuid": src_uuid,
            "name": src_name,
            "parentname": f"{combined_name}-0000",
            "parentuuid": src_combined_uuid,
            "typeuuid": st_uuid,
        })
        sourcetypes.append({
            "uuid": st_uuid,
            "name": f"{combined_name}-{sub_name}",
            "class": "Sensor",
            "devicetype": f"{combined_name}-{sub_name}",
            "type": "float",
            "unit": unit,
        })
        mapping[sub_name] = src_uuid

    data = {
        "sources": sources,
        "sourcetypes": sourcetypes,
    }

    print("\n--- YAML output ---")
    print(yaml.dump(data, sort_keys=False, default_flow_style=False, allow_unicode=True, width=80, Dumper=yaml.SafeDumper))

    print("\n--- Mapping (Python dict) ---")
    print("uuid_map = {")
    for k, v in mapping.items():
        print(f"    '{k}': '{v}',")
    print("}")
    
if __name__ == "__main__":
    main()

