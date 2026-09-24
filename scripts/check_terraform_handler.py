#!/usr/bin/env python3
"""Check that the Terraform module's handler matches the template's.

The Lambda handler is defined inline in the CloudFormation template, and
the template is its source of truth.  The Terraform module cannot read it
from there -- Terraform's yamldecode() rejects CloudFormation tags such as
!GetAtt -- so it carries its own copy in terraform/handler.py.  This
script fails if the two copies differ, so a change to one cannot ship
without the other.

To bring the copy back in line after editing the template:

    python3 scripts/check_terraform_handler.py --fix

Usage: python3 scripts/check_terraform_handler.py [--fix]
"""

import difflib
import pathlib
import sys

from check_handler import extract_handler

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
TEMPLATE = REPO_ROOT / "cfn-template.yml"
TERRAFORM_HANDLER = REPO_ROOT / "terraform" / "handler.py"


def main(argv):
    expected = extract_handler(TEMPLATE)

    if "--fix" in argv[1:]:
        TERRAFORM_HANDLER.write_text(expected)
        print("Wrote {}".format(TERRAFORM_HANDLER.relative_to(REPO_ROOT)))
        return 0

    actual = TERRAFORM_HANDLER.read_text() if TERRAFORM_HANDLER.is_file() else ""
    if actual == expected:
        print("OK: terraform/handler.py matches the handler in cfn-template.yml")
        return 0

    diff = difflib.unified_diff(
        expected.splitlines(keepends=True),
        actual.splitlines(keepends=True),
        fromfile="cfn-template.yml:ZipFile",
        tofile="terraform/handler.py",
    )
    sys.stderr.write(
        "FAIL: terraform/handler.py differs from the handler in cfn-template.yml.\n"
        "Run `python3 scripts/check_terraform_handler.py --fix` to update it.\n\n"
    )
    sys.stderr.writelines(diff)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
