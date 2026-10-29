"""Print the local administrative secret without writing it to server logs."""
import os
from pathlib import Path

if __name__ == '__main__':
    print((Path(os.getenv('DATA_DIR', '/data')) / 'admin-secret').read_text().strip())
