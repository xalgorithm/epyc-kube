#Add bulk insert tool for Users into addresses table

#!/usr/bin/env python3

from typing import Any, Dict


def process(filename: str, db) -> None:
    file = open(filename, "r")

    keys = []
    records: Dict[str, Any] = dict()

    for line in file.read().splitlines():
        parts = line.split("|")
        key = parts[1] + "," + parts[0]
        keys.append(key)
        records[key] = dict(
            firstName=parts[0],
            lastName=parts[1],
            address=parts[2],
        )

    ids = []
    for key in sorted(keys):
        record = records[key]
        values = [
            record["firstName"],
            record["lastName"],
            record["address"],
        ]
        db.query(
            "INSERT INTO addresses VALUES("
            + ",".join(values)
            + "); SELECT LAST_INSERT_ID(addresses)"
        )
        ids.append(db.fetchall()[0])

    