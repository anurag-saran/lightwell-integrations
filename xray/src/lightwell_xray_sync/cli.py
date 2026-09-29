"""CLI: lightwell-xray-sync sync|push|self-test."""

from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path

from lightwell_xray_sync import DEFAULT_OSV_URL
from lightwell_xray_sync.sync import load_docs, process_docs, run_self_test, write_summary

LOG = logging.getLogger("lightwell.xray")


def configure_logging(verbose: bool) -> None:
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format="%(asctime)s %(levelname)s %(message)s",
        datefmt="%H:%M:%S",
        stream=sys.stderr,
    )


def _add_common(p: argparse.ArgumentParser) -> None:
    p.add_argument("--timeout", type=float, default=60.0, help="HTTP timeout seconds")
    p.add_argument(
        "--summary",
        default="xray-sync-summary.json",
        help="Write machine-readable summary JSON (default: xray-sync-summary.json)",
    )
    p.add_argument("--no-summary", action="store_true", help="Do not write summary file")
    p.add_argument("-v", "--verbose", action="store_true")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="lightwell-xray-sync",
        description="Sync Red Hat Lightwell OSV advisories into JFrog Xray Custom Issues",
    )
    sub = p.add_subparsers(dest="command", required=True)

    sync = sub.add_parser(
        "sync",
        help="Fetch latest OSV from LIGHTWELL_OSV_URL (or --url) and upsert to Xray",
    )
    sync.add_argument(
        "--url",
        default=None,
        help="OSV index/file URL (default: env LIGHTWELL_OSV_URL or public-demo feed)",
    )
    sync.add_argument(
        "--dry-run",
        action="store_true",
        help="Map payloads only; do not call Xray",
    )
    sync.add_argument(
        "--print-payloads",
        action="store_true",
        help="With --dry-run, print each JSON payload to stdout",
    )
    _add_common(sync)

    push = sub.add_parser("push", help="Push local OSV JSON file(s) to Xray")
    push.add_argument(
        "--input",
        "-i",
        required=True,
        help="OSV JSON file or directory of *.json",
    )
    push.add_argument("--dry-run", action="store_true")
    push.add_argument("--print-payloads", action="store_true")
    _add_common(push)

    dry = sub.add_parser(
        "dry-run",
        help="Alias: sync --dry-run (fetch URL) or push --dry-run with --input",
    )
    dry.add_argument("--input", "-i", help="Local OSV file/dir")
    dry.add_argument("--url", help="OSV URL (default public-demo if no --input)")
    dry.add_argument("--print-payloads", action="store_true")
    _add_common(dry)

    st = sub.add_parser("self-test", help="Offline mapping check; no network")
    st.add_argument("-v", "--verbose", action="store_true")

    return p


def _resolve_osv_url(explicit: str | None) -> str:
    return (
        explicit
        or os.environ.get("LIGHTWELL_OSV_URL")
        or DEFAULT_OSV_URL
    )


def _run_process(
    docs: list,
    *,
    dry_run: bool,
    timeout: float,
    print_payloads: bool,
    summary_path: str | None,
) -> int:
    try:
        summary = process_docs(
            docs,
            dry_run=dry_run,
            timeout=timeout,
            print_payloads=print_payloads,
        )
    except EnvironmentError as exc:
        LOG.error("%s", exc)
        return 2
    except Exception as exc:
        if type(exc).__module__.startswith("requests") or "JFROG" in str(exc):
            LOG.error("%s", exc)
            return 1
        raise

    if summary_path:
        write_summary(summary, Path(summary_path))

    if summary.advisories == 0:
        LOG.error("No OSV advisories found")
        return 1
    return 1 if summary.failed else 0


def main(argv: list[str] | None = None) -> int:
    # Support legacy flat flags by rewriting argv when no subcommand given
    argv = list(argv) if argv is not None else sys.argv[1:]
    if argv and argv[0] not in (
        "sync",
        "push",
        "dry-run",
        "self-test",
        "-h",
        "--help",
    ):
        # Legacy: push_osv_to_xray.py --input X / --url / --self-test / --dry-run
        if "--self-test" in argv:
            argv = ["self-test"] + [a for a in argv if a != "--self-test"]
        elif "--input" in argv or "-i" in argv:
            argv = ["push"] + argv
        elif "--url" in argv:
            argv = ["sync"] + argv
        else:
            argv = ["sync"] + argv

    parser = build_parser()
    args = parser.parse_args(argv)
    configure_logging(getattr(args, "verbose", False))

    if args.command == "self-test":
        return run_self_test()

    dry_run = bool(getattr(args, "dry_run", False) or args.command == "dry-run")
    print_payloads = bool(getattr(args, "print_payloads", False))
    timeout = float(getattr(args, "timeout", 60.0))
    summary_path = None if getattr(args, "no_summary", False) else getattr(args, "summary", None)

    try:
        if args.command == "push" or (
            args.command == "dry-run" and getattr(args, "input", None)
        ):
            docs = load_docs(
                input_path=args.input,
                url=None,
                timeout=timeout,
            )
        else:
            url = _resolve_osv_url(getattr(args, "url", None))
            docs = load_docs(input_path=None, url=url, timeout=timeout)
    except (OSError, ValueError) as exc:
        LOG.error("Failed to load OSV input: %s", exc)
        return 1
    except Exception as exc:
        if type(exc).__module__.startswith("requests"):
            LOG.error("Failed to load OSV input: %s", exc)
            return 1
        raise

    return _run_process(
        docs,
        dry_run=dry_run,
        timeout=timeout,
        print_payloads=print_payloads,
        summary_path=summary_path,
    )


if __name__ == "__main__":
    sys.exit(main())
