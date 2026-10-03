"""Validate the hash-pinned standalone archive before extracting any member."""
import sys
import tarfile


def validate_archive(path, arch):
    with tarfile.open(path, 'r:gz') as archive:
        members = archive.getmembers()
        if (len(members) != 1 or members[0].name != 'opencode'
                or not members[0].isfile() or not members[0].mode & 0o111):
            raise ValueError('Invalid standalone archive layout')
        with archive.extractfile(members[0]) as binary:
            header = binary.read(20)
        if (header[:6] != b'\x7fELF\x02\x01'
                or int.from_bytes(header[18:20], 'little') != {'amd64': 62, 'arm64': 183}[arch]):
            raise ValueError('Invalid standalone ELF architecture')


if __name__ == '__main__':
    validate_archive(*sys.argv[1:])
