from __future__ import annotations

from pathlib import Path
import logging


def setup_logger(base_dir: Path | str = ".") -> logging.Logger:
    base = Path(base_dir)
    (base / "logs").mkdir(exist_ok=True)
    logger = logging.getLogger("shorts_blogger")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    fmt = logging.Formatter("%(asctime)s %(levelname)s %(name)s - %(message)s")
    file_handler = logging.FileHandler(base / "logs" / "automation.log", encoding="utf-8")
    file_handler.setFormatter(fmt)
    console = logging.StreamHandler()
    console.setFormatter(fmt)
    logger.addHandler(file_handler)
    logger.addHandler(console)
    return logger
