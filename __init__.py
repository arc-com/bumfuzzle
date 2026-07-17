import os
import sys


def main() -> None:
    root = os.path.dirname(os.path.abspath(__file__))
    script = os.path.join(root, "scripts", "bumfuzzle.sh")
    os.execvp("bash", ["bash", script, *sys.argv[1:]])
