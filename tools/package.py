#!/usr/bin/env python3
"""Build the .deb and the apt repo index without dpkg on the Mac.

  package.py deb ROOT DEBIAN_DIR VERSION OUT.deb
      ROOT is the staged filesystem; DEBIAN_DIR holds control (without
      Version), postinst and postrm.  Files are owned by root:wheel.
  package.py index REPO_DIR
      Writes Packages, Packages.gz and Packages.bz2 for every .deb there, for a
      flat repo: deb http://host/path/ ./

The Apple TV's dpkg 1.18 and apt 0.7 are old: the archive uses gzip and
plain ustar, which they read.
"""
import bz2
import gzip
import hashlib
import io
import os
import sys
import tarfile

AR_MAGIC = b"!<arch>\n"


def ar_member(name, data):
    head = "%-16s%-12d%-6d%-6d%-8s%-10d`\n" % (name, 0, 0, 0, "100644", len(data))
    return head.encode() + data + (b"\n" if len(data) % 2 else b"")


def ar_members(blob):
    assert blob.startswith(AR_MAGIC), "not an ar archive"
    pos = len(AR_MAGIC)
    while pos < len(blob):
        head = blob[pos:pos + 60]
        name = head[:16].decode().strip().rstrip("/")
        size = int(head[48:58])
        yield name, blob[pos + 60:pos + 60 + size]
        pos += 60 + size + (size % 2)


def tar_gz(entries):
    """entries: (arcname, path or None for a directory, mode)."""
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb", mtime=0) as gz:
        with tarfile.open(fileobj=gz, mode="w", format=tarfile.USTAR_FORMAT) as tar:
            for arcname, path, mode in entries:
                info = tarfile.TarInfo(arcname)
                info.uid = info.gid = 0
                info.uname, info.gname = "root", "wheel"
                info.mode = mode
                if path is None:
                    info.type = tarfile.DIRTYPE
                    tar.addfile(info)
                else:
                    info.size = os.path.getsize(path)
                    with open(path, "rb") as f:
                        tar.addfile(info, f)
    return buf.getvalue()


def build_deb(root, debian, version, out):
    data, size = [("./", None, 0o755)], 0
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        rel = os.path.relpath(dirpath, root)
        for d in dirnames:
            data.append(("./" + os.path.normpath(os.path.join(rel, d)) + "/", None, 0o755))
        for name in sorted(filenames):
            if name == ".DS_Store":
                continue
            path = os.path.join(dirpath, name)
            mode = 0o755 if os.access(path, os.X_OK) else 0o644
            data.append(("./" + os.path.normpath(os.path.join(rel, name)), path, mode))
            size += os.path.getsize(path)

    with open(os.path.join(debian, "control")) as f:
        control = f.read().rstrip("\n")
    control += "\nVersion: %s\nInstalled-Size: %d\n" % (version, (size + 1023) // 1024)
    ctl = os.path.join(os.path.dirname(out), "control.generated")
    with open(ctl, "w") as f:
        f.write(control)
    entries = [("./", None, 0o755), ("./control", ctl, 0o644)]
    for script in ("preinst", "postinst", "prerm", "postrm"):
        path = os.path.join(debian, script)
        if os.path.exists(path):
            entries.append(("./" + script, path, 0o755))

    with open(out, "wb") as f:
        f.write(AR_MAGIC)
        f.write(ar_member("debian-binary", b"2.0\n"))
        f.write(ar_member("control.tar.gz", tar_gz(entries)))
        f.write(ar_member("data.tar.gz", tar_gz(data)))
    os.remove(ctl)
    print("wrote %s (%s)" % (out, version))


def deb_control(path):
    with open(path, "rb") as f:
        members = dict(ar_members(f.read()))
    with tarfile.open(fileobj=io.BytesIO(members["control.tar.gz"]), mode="r:gz") as tar:
        return tar.extractfile("./control").read().decode().rstrip("\n")


def build_index(repo):
    stanzas = []
    for name in sorted(os.listdir(repo)):
        if not name.endswith(".deb"):
            continue
        path = os.path.join(repo, name)
        with open(path, "rb") as f:
            blob = f.read()
        stanzas.append("%s\nFilename: ./%s\nSize: %d\nMD5sum: %s\nSHA1: %s\nSHA256: %s\n" % (
            deb_control(path), name, len(blob), hashlib.md5(blob).hexdigest(),
            hashlib.sha1(blob).hexdigest(), hashlib.sha256(blob).hexdigest()))
    text = "\n".join(stanzas).encode()
    with open(os.path.join(repo, "Packages"), "wb") as f:
        f.write(text)
    with gzip.GzipFile(os.path.join(repo, "Packages.gz"), "wb", mtime=0) as f:
        f.write(text)
    with bz2.open(os.path.join(repo, "Packages.bz2"), "wb") as f:
        f.write(text)
    print("indexed %d package(s) in %s" % (len(stanzas), repo))


if __name__ == "__main__":
    if len(sys.argv) == 6 and sys.argv[1] == "deb":
        build_deb(*sys.argv[2:])
    elif len(sys.argv) == 3 and sys.argv[1] == "index":
        build_index(sys.argv[2])
    else:
        sys.exit(__doc__)
