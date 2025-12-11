#!/usr/bin/env python3

# usage: interactive mode - or short cut:
#
# echo "WittBoy_GW2000A
# 0000
#    humidityin %RH float
#    baromrelin hPa float" | ./$0
#

import os
import sys
import uuid
import yaml
import json
import re

from units_registry_loader import get_units_registry

# Prepare tiny global singleton helper copy
ucum_registry = None

# Define a new Class to be represented and ..
class Quoted(str): pass
#a global function to mark resp. strings
def q(s): return Quoted(str(s))


class SourceType():
    # Configurable indent prefix
    LEADING_SPACES = "    "  # 4 spaces

    # Some defaults
    DEFAULT_SUPER_TYPE = "CombinedSensor"
    DEFAULT_SUB_TYPE = "Sensor"

    def __init__(self):
        self.uuid = None
        self.name = None
        self.classname = None
        self.devicetype = None
        self.datatype = None
        self.dataunit = None
        self.dataunitencoding = 'meta:quantity_kind'
        self.meta = {
            'uncertainty': None,
            'quantity_kind': None,
            'displayname': {
                'en': ""
            },
            'tooltip': {
                'en': ""
            },
        }

    def auto_fill(self):
        if not self.uuid:
            self.uuid = str(uuid.uuid4())

    def serialize(self):
        self.auto_fill()
        o = {
            "name": self.name,
            "uuid": self.uuid,
            "classname": self.classname,
            "devicetype": self.devicetype,
            "type": self.datatype,
            "unit": self.dataunit,
            "unitencoding": self.dataunitencoding,
            "meta": self.meta,
        }
        return o



class Source():
    # Configurable indent prefix
    LEADING_SPACES = "      "  # 6 spaces

    def __init__(self, sourcetype: SourceType, parentsource=None):
        self.uuid = None
        self.name = None
        self.index = '0000'

        self.sourcetype = sourcetype
        self.parentsource = parentsource
        self.sub_sources = []

        self.meta = {
            'displayname': {
                'en': ""
            },
            'tooltip': {
                'en': ""
            },
        }

    def set_names(
        self,
        sourcetype_name,
        index=None,
        disable_index=False,
        devicetype=None,
    ):
        sourcetype_name = slugify(sourcetype_name)
        self.sourcetype.name = sourcetype_name
        if disable_index == True:
            self.index = None
            self.name = sourcetype_name
        elif not index and not self.index: 
            self.name = sourcetype_name
        elif not index:
            self.name = sourcetype_name + "_" + self.index
        else:
            self.index = index
            self.name = sourcetype_name + "_" + index

        if devicetype:
            self.sourcetype.devicetype = devicetype
        else:
            self.sourcetype.devicetype = sourcetype_name


    def set_displayname(self, name, lang="en"):
        self.meta["displayname"] = { lang: name }

    def set_displaynames(
        self,
        sourcetype_displayname=None,
        source_displayname=None,
        disable_displaynames=False,
        lang="en",
    ):
        if disable_displaynames:
            self.meta["displayname"] = { lang: "" }
            self.sourcetype.meta["displayname"] = { lang: "" }
        else:
            if sourcetype_displayname:
                self.sourcetype.meta["displayname"] = {
                    lang: sourcetype_displayname
                }
            if source_displayname:
                self.meta["displayname"] = {
                    lang: source_displayname
                }


    def parturate(self):
        s = Source(SourceType(), self)
        self.sub_sources.append(s)
        return s

    # shortcut for now..
    def create_sub(
        self,
        sub_name,
        sub_class,
        sub_type_uuid,
        sub_source_uuid,
        sub_type_displayname,
        sub_source_displayname,
        sub_dev_type,
        dataunit,
        datatype,
        sub_type_meta,
        sub_source_meta
    ):
        s = self.parturate()
        s.name = sub_name
        s.sourcetype.name = sub_name
        s.sourcetype.classname = sub_class
        s.sourcetype.uuid = sub_type_uuid
        s.uuid = sub_source_uuid
        s.sourcetype.meta["displayname"]["en"] = sub_type_displayname
        s.meta["displayname"]["en"] = sub_source_displayname
        s.sourcetype.devicetype = sub_dev_type
        s.sourcetype.dataunit = dataunit
        s.sourcetype.datatype = datatype
        s.meta = sub_source_meta
        return s

    def auto_fill(self):
        if not self.uuid:
            self.uuid = str(uuid.uuid4())
        if not self.sourcetype:
            raise Exception(f"ERROR: Source without SourceType: {self.uuid}")
        else:
            self.sourcetype.auto_fill()
        # NOT handling self.parentsource.uuid, see serialize_deep(..)

    def serialize_parameters(self):
        self.auto_fill()
        o = {
            "name": self.name,
            "uuid": self.uuid,
            "typeuuid": self.sourcetype.uuid if self.sourcetype else None,
            "parentuuid": self.parentsource.uuid if self.parentsource else None,
            "meta": self.meta,
        }
        return o

    def serialize_deep(self, container=None, depth=None):
        if depth == None:
            pass
        elif depth > 0:
            depth -= 1
        else:
            return container

        if not container:
            container = {
                "sources": {},
                "sourcetypes": {}, 
            }

        if (
            "sources" not in container or
            "sourcetypes" not in container
        ):
            raise Exception("Container corrupt.")

        if self.uuid in container["sources"]:
            print("WARNING: Duplicate Source entry found, last one takes precedence: {self.uuid}")
        container["sources"][self.uuid] = self.serialize_parameters()
        if not self.sourcetype.uuid in container["sourcetypes"]:
            container["sourcetypes"][self.sourcetype.uuid] = self.sourcetype.serialize()

        for s in self.sub_sources:
            s.serialize_deep(container, depth)
        return container



def slugify(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_-]", "_", name.strip().replace(" ", "_"))

def search_ucum(query, type_query=None, limit=8):
    while True:
        q = ucum_registry.lookup_quantity_kinds(query=query, limit=limit)
        if len(q) < 1:
            q = ucum_registry.lookup_quantity_kinds(query=type_query, limit=limit)

        u = 0 ; i = 0
        if len(q) > 0:
            print("  One of the following quantity-kinds:units could match:")
            for key, score in q:
                qk = ucum_registry.quantity_kinds[key]
                print(
                    f"    {i}: {key} {qk.label} [{qk.symbol}] (unit={qk.default_unit}) " +
                    f"score={score}"
                )
                i += 1
            r = input(f"Enter the index that fits best (or new search terms: ").strip()
            try:
                j = int(r)
                if j > len(q):
                    print(
                        f"There are only {len(q)} number of items to choose from... " +
                        "Please try again."
                    )
                else:
                    qk = ucum_registry.quantity_kinds[q[j][0]]
                    return qk.__dict__
            except Exception as e:
                print(e)
                query = r
        else:
            query = input("No results found, please add new search terms: ").strip()


# TODO parse_stdin() supports far less features than parse_interactive()..
def parse_stdin():
    """Parse lines of form:
       CombinedSensorName
       Index
          subname unit [type]
    """
    the_source = Source()
    lines = [l.rstrip() for l in sys.stdin if l.strip()]
    if not lines:
        return None
    the_source.sourcetype.name = slugify(lines[0])
    the_source.index = lines[1].strip() if len(lines) > 1 else the_source.index
    for line in lines[2:]:
        parts = line.strip().split(None, 3)
        if not parts:
            continue
        sub_source = the_source.parturate()
        sub_source.name = slugify(parts[0])
        sub_source.sourcetype.dateunit = parts[1].strip() if len(parts) > 1 else ""
        sub_source.sourcetype.datatype = parts[2].strip() if len(parts) > 2 else "float"
    return the_source

def parse_interactive():

    print("################################################################################")
    name = input(
        f"Enter {SourceType.DEFAULT_SUPER_TYPE} type name (empty to finish): "
    ).strip()
    if not name:
        return None

    # still here?
    the_source = Source(SourceType())

    disable_index = False
    index = input(
        f"Enter the source index ('-' to skip, [{the_source.index}]): "
    ).strip()
    if index == "-":
        index = ""
        disable_index = True
    devtype = input(
        "Enter device-type (empty means autogenerate): "
    ).strip()
    the_source.set_names(
        name,
        index,
        disable_index,
        devtype,
    )

    typedispln = input(
        "Enter type display name (empty to skip all display names): "
    ).strip()
    if typedispln:
        disable_dn = False
        if the_source.index:
            tmp = f"{typedispln} {the_source.index}"
        tmpi = input(
            f"Enter source display name ([{tmp}]): "
        ).strip()
        srcdispln = tmpi if tmpi else tmp
    else:
        disable_dn = True
        typedispln = None
        srcdispln = None
    the_source.set_displaynames(
        typedispln,
        srcdispln,
        disable_dn,
        lang="en",
    )

    tmpuuid = str(uuid.uuid4())
    the_source.sourcetype.uuid = input(
        f"Enter sourcetype UUID (['{tmpuuid}']): "
    ).strip() or tmpuuid
    tmpuuid = str(uuid.uuid4())
    the_source.uuid = input(
        f"Enter source UUID (['{tmpuuid}']): "
    ).strip() or tmpuuid

    subcount = 0
    while True:
        print(f"================= {name}::{subcount} ======================")
        sub_in = input(
            f"Enter sub-sensor name (empty to end this {SourceType.DEFAULT_SUPER_TYPE}): "
        ).strip()
        if not sub_in:
            break
        sub_name = slugify(sub_in)
        sc = input(f"Enter a class name (['{SourceType.DEFAULT_SUB_TYPE}']): ").strip()
        sub_class = sc if sc else SourceType.DEFAULT_SUB_TYPE
        sub_dev_type = input("Enter device-type (empty means autogenerate): ").strip()
        tmpuuid = str(uuid.uuid4())
        sub_type_uuid = input(
            f"Enter sourcetype UUID (['{tmpuuid}']): "
        ).strip()
        tmpuuid = str(uuid.uuid4())
        sub_source_uuid = input(
            f"Enter source UUID (['{tmpuuid}']): "
        ).strip()

        if not disable_dn:
            sub_type_displname = input(
                f"Enter sourcetype display name ([{sub_in}] if empty): "
            ).strip()
            sub_type_displname = sub_type_displname if sub_type_displname else sub_in
            i = f"{sub_type_displname} {the_source.index}" if the_source.index else type_displname
            sub_source_displname = input(
                f"Enter source display name ([{i}]): "
            ).strip()
            sub_source_displname = sub_source_displname if sub_source_displname else i
        else:
            sub_type_displname = None
            sub_source_displname = None
        print("---")
        if ucum_registry:
            qk = search_ucum(sub_name, sub_dev_type)
            unit = qk["default_unit"]
            sub_type_meta = {}
            sub_type_meta["quantity_kind"] = qk
            sub_type_meta["uncertainty"] = {}
        else:
            unit = input(f"Enter unit for '{sub_name}' ['m']: ").strip()
        print("---")
        stype = input(f"Enter type for '{sub_name}' (default float): ").strip() or "float"
        print("---")
        sub_source_meta = parse_meta()
        print("===")
        t = (
            sub_name,
            sub_class,
            sub_type_uuid,
            sub_source_uuid,
            sub_type_displname,
            sub_source_displname,
            sub_dev_type,
            unit,
            stype,
            sub_type_meta,
            sub_source_meta
        )
        print(yaml.dump(
            list(t),
            sort_keys=False,
            default_flow_style=False,
            allow_unicode=True,
            width=80,
        ))
        print("===")
        skipit = input("Please confirm the entry ([Y/n]): ").strip()
        if not skipit.lower() == "n":
            sub_sensor = the_source.create_sub(*t)
            subcount += 1
    return the_source


def parse_meta(level=0):
    meta = {}
    hasMeta = True
    while hasMeta:
        if not meta:
            m = input(
                f"Enter meta JSON Level{level} (empty to skip, a key or JSON): "
            ).strip()
        else:
            m = input(
                f"Enter meta JSON Level{level} (empty to skip or the next key): "
            ).strip()
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
            v = input(
                f"Now enter the value for '{m}' or leave empty to add sub-dict: "
            ).strip()
            if v:
                meta[m] = v
            else:
                meta[m] = parse_meta(level + 1)
    return meta

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
        dev_type,
        index,
        combined_type_uuid,
        combined_source_uuid,
        type_displname,
        source_displname,
        sub_sensors,
#        do_prepend_parent=False
    ):
    sources = []
    sourcetypes = []
#    mapping = {}

    # Combined sensor
    st_combined_uuid = combined_type_uuid #if combined_type_uuid else gen_uuid()
    src_combined_uuid = combined_source_uuid #if combined_source_uuid else gen_uuid()

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
        "class": q(SourceType.DEFAULT_SUPER_TYPE),
        "devicetype": q(dev_type),
        "type": None,
        "unit": None,
    }
    if type_displname:
        tmp["meta"] = { "displayname": { "en": quote_textlike(type_displname) } }
    sourcetypes.append(tmp)

    # Sub-sensors
    for (
        sub_name,
        sub_class,
        sub_type_uuid,
        sub_uuid,
        sub_type_displname,
        sub_source_displname,
        sub_dev_type,
        unit,
        stype,
        sub_type_meta,
        sub_source_meta
    ) in sub_sensors:
        st_uuid = sub_type_uuid # if sub_type_uuid else gen_uuid()
        src_uuid = sub_uuid # if sub_uuid else gen_uuid()
#        src_name = f"{combined_name}{indexs}-{sub_name}" if do_prepend_parent else sub_name
        src_name = sub_name

        if sub_type_displname:
            # TODO only "en" currently supported and no way to turn the input question off
            sub_source_meta["displayname"] = { "en": sub_source_displname }
            sub_type_meta["displayname"] = { "en": sub_type_displname }
        dt = sub_dev_type if sub_dev_type else f"{combined_name}-{sub_name}"

        #TODO: in non-interacte we might want to limit the depth of quote_textlike()..!?
        tmp = {
            "uuid": q(src_uuid),
            "name": q(src_name),
            "parentname": q(f"{combined_name}{indexs}"),
            "parentuuid": q(src_combined_uuid),
            "typeuuid": q(st_uuid),
        }
        if sub_source_meta:
            tmp["meta"] = quote_textlike(sub_source_meta)
        sources.append(tmp)
        tmp = {
            "uuid": q(st_uuid),
            "name": q(f"{combined_name}-{sub_name}"),
            "class": q(sub_class),
            "devicetype": q(dt),
            "type": stype,  # bare literal
            "unit": q(unit),
            "unitencoding": q("meta:quantity_kind")
        }
        if sub_type_meta:
            tmp["meta"] = quote_textlike(sub_type_meta)
        sourcetypes.append(tmp)
#        mapping[sub_name] = src_uuid

    print("\n--- YAML output for 'Sources' ---")
    source_yaml = yaml.dump(
        sources,
        sort_keys=False,
        default_flow_style=False,
        allow_unicode=True,
        width=80,
    )
    print("".join(Source.LEADING_SPACES + line for line in source_yaml.splitlines(True)))
    print("\n--- YAML output for 'SourceTypes' ---")
    sourcetypes_yaml = yaml.dump(
        sourcetypes,
        sort_keys=False,
        default_flow_style=False,
        allow_unicode=True,
        width=80,
    )
    print(
        "".join(SourceType.LEADING_SPACES +
        line for line in sourcetypes_yaml.splitlines(True))
    )


def main():

    if not sys.stdin.isatty():
        parse = parse_stdin
    else:
        p = os.path.dirname(os.path.realpath(__file__)) + '/maestro-basin-source-gen.ucum.yaml'
        pi = input(f"Enter path to units/meta file ([{p}]): ").strip()
        p = pi if pi else p
        global ucum_registry
        ucum_registry = get_units_registry()

#        do_prepend_parent = False
#        o = input("Autogenerate all UUIDs? ([Y/n]): ").strip()
#        if o.lower() == "n":
#            do_override_uuids = True
#        else:
#            do_override_uuids = False
#        d = input("Prepend parent name and index to the source sub-name? ([y/N]): ").strip()
#        if d.lower() == "y":
#            do_prepend_parent = True
        parse = parse_interactive

    sensor_libs = []

    # quote stringlike
    def quoted_representer(dumper, data):
        return dumper.represent_scalar("tag:yaml.org,2002:str", data, style="'")
    yaml.add_representer(Quoted, quoted_representer)

    do_continue = True
    while do_continue:
        a_source = parse()
        if not a_source:
            do_continue = False
        else:
            sensor_libs.append(a_source)

    # from here on, replace `None` resp. `null` with ``
    def none_representer(dumper, _):
        return dumper.represent_scalar('tag:yaml.org,2002:null', '', style=None)
    yaml.add_representer(type(None), none_representer)

    container = {
        "sources": {},
        "sourcetypes": {},
    }

    for l in sensor_libs:
#        print(l.name)
#        for m in l.sub_sources:
#            print(m.name)
        l.serialize_deep(container)

    #print(container)

    if "sources" in container and "sourcetypes" in container:

        print("\n--- YAML output for 'Sources' ---")
        source_yaml = yaml.dump(
            list(container["sources"].values()),
            sort_keys=False,
            default_flow_style=False,
            allow_unicode=True,
            width=80,
        )
        print("".join(Source.LEADING_SPACES + line for line in source_yaml.splitlines(True)))
        print("\n--- YAML output for 'SourceTypes' ---")
        sourcetypes_yaml = yaml.dump(
            list(container["sourcetypes"].values()),
            sort_keys=False,
            default_flow_style=False,
            allow_unicode=True,
            width=80,
        )
        print(
            "".join(SourceType.LEADING_SPACES +
            line for line in sourcetypes_yaml.splitlines(True))
        )

    sys.exit(0)

    for s in sensor_libs:
        combined_name = s[0]
        dev_type = s[1]
        index = s[2]
        tuuid = s[3]
        suuid = s[4]
        tdname = s[5]
        sdname = s[6]
        sub_sensors = s[7]
        produce_output(
            combined_name,
            dev_type,
            index,
            tuuid,
            suuid,
            tdname,
            sdname,
            sub_sensors,
#            do_prepend_parent
        )



if __name__ == "__main__":
    main()

