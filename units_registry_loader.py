from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import yaml


@dataclass(frozen=True)
class QuantityKindInfo:
    key: str              # dict key from YAML (e.g. "relative_humidity")
    label: str            # human label
    symbol: str           # e.g. "%RH"
    default_unit: str     # e.g. "%"
    uri: str              # QUDT etc.
    aliases: List[str]
    tags: List[str]


class UnitsRegistry:
    def __init__(self, path: Path) -> None:
        self._path = path
        self._units: Dict[str, Dict[str, Any]] = {}
        self._quantity_kinds: Dict[str, QuantityKindInfo] = {}
        self._load()

    # --- public API ---

    @property
    def units(self) -> Dict[str, Dict[str, Any]]:
        return self._units

    @property
    def quantity_kinds(self) -> Dict[str, QuantityKindInfo]:
        return self._quantity_kinds

    def normalize_unit(self, raw: Optional[str]) -> Optional[str]:
        """Map a raw unit string to a canonical key if possible."""
        if raw is None:
            return None
        s = raw.strip()
        if not s:
            return None

        # exact key
        if s in self._units:
            return s

        # match by symbol or alias
        s_lc = s.lower()
        for key, info in self._units.items():
            if info.get("symbol", "").lower() == s_lc:
                return key
            for a in info.get("aliases", []) or []:
                if a.lower() == s_lc:
                    return key
        return None

    def lookup_quantity_kinds(
        self,
        query: str,
        raw_unit: Optional[str] = None,
        limit: int = 10,
    ) -> List[Tuple[str, int]]:
        """
        Return a list of (quantity_kind_key, score), sorted by score DESC.

        Scoring uses:
          - alias matches (strong)
          - tag matches (medium)
          - label/key/symbol substring matches (light)
          - optional unit compatibility bonus
        """
        text = (query or "").lower()
        norm_unit = self.normalize_unit(raw_unit) if raw_unit else None

        results: List[Tuple[str, int]] = []

        for key, qk in self._quantity_kinds.items():
            score = 0

            # 1) unit compatibility bonus
            if norm_unit and norm_unit == (qk.default_unit or "").strip():
                score += 4

            # 2) exact alias match
            for a in qk.aliases:
                a_lc = a.lower()
                if a_lc == text:
                    score += 8
                elif a_lc in text or text in a_lc:
                    score += 4

            # 3) tag matches
            for t in qk.tags:
                t_lc = t.lower()
                if t_lc == text:
                    score += 5
                elif t_lc in text or text in t_lc:
                    score += 2

            # 4) label / key / symbol substrings
            if qk.label.lower() == text:
                score += 5
            elif text and qk.label.lower() in text or text in qk.label.lower():
                score += 2

            if qk.key.lower() == text:
                score += 4
            elif text and (qk.key.lower() in text or text in qk.key.lower()):
                score += 1

            if qk.symbol.lower() == text:
                score += 3
            elif text and (qk.symbol.lower() in text or text in qk.symbol.lower()):
                score += 1

            if score > 0:
                results.append((key, score))

        results.sort(key=lambda kv: kv[1], reverse=True)
        if limit and limit > 0:
            results = results[:limit]
        return results

    # --- loading ---

    def _load(self) -> None:
        with self._path.open("r", encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}

        self._units = data.get("units", {}) or {}

        qk_raw: Dict[str, Any] = data.get("quantity_kinds", {}) or {}
        for key, info in qk_raw.items():
            qk = QuantityKindInfo(
                key=key,
                label=info.get("label", key),
                symbol=info.get("symbol", ""),
                default_unit=str(info.get("default_unit", "") or ""),
                uri=info.get("uri", ""),
                aliases=list(info.get("aliases", []) or []),
                tags=list(info.get("tags", []) or []),
            )
            self._quantity_kinds[key] = qk


# --- tiny singleton helper ---

_registry: Optional[UnitsRegistry] = None


def get_units_registry(path: Optional[Path] = None) -> UnitsRegistry:
    global _registry
    if _registry is None:
        if path is None:
            path = Path(__file__).with_name("maestro-basin-source-gen.ucum.yaml")
        _registry = UnitsRegistry(path)
    return _registry

