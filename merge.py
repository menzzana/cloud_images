#!/usr/bin/env python3
#-----------------------------------------------------------------------
import yaml
import os
#-----------------------------------------------------------------------
IMAGES="images"
CONFIGURATION="configuration.yaml"
CATALOG="catalog.yaml"
#-----------------------------------------------------------------------
catalog={}
for dir in os.listdir(IMAGES):
    with open(os.path.join(IMAGES, dir,CONFIGURATION)) as fp:
        cfg = yaml.safe_load(fp)
    general = cfg["general"]
    category=cfg["general"]["category"].capitalize()
    if category not in catalog:
        catalog[category]=[]
    del cfg["general"]["category"]
    general = {
        k.lower(): v
        for k, v in cfg["general"].items()
        }
    cfg={os.path.join(IMAGES, dir,CONFIGURATION):cfg}
    catalog[category].append({
        "dir": dir,
        **general
        })
    catalog = {
        category: sorted(
            entries,
            key=lambda x: x["title"].lower()
            )
        for category, entries in sorted(catalog.items())
        }
with open(CATALOG, "w") as fp:
    yaml.dump(catalog, fp, sort_keys=False)
#-----------------------------------------------------------------------
