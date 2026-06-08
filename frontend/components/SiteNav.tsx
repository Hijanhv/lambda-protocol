"use client";

import * as React from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { Wordmark } from "@/components/Brand";
import { Button } from "@/components/ui/button";
import { Sheet, SheetClose, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet";
import { cn } from "@/lib/utils";

export type NavLink = { href: string; label: string };

interface Props {
  /** Wordmark subtitle ("Yield-protected liquidity", "LP Dashboard", "Docs"). */
  sub?: string;
  /** Top-bar links shown in the desktop nav. */
  links: NavLink[];
  /** Right-side CTA (a `<Button asChild>…<Link/></Button>`, the `<Connect />`, etc.). */
  rightSlot?: React.ReactNode;
}

/**
 * Shared site navigation: sticky, hairline-bordered, with active-link
 * highlighting from the route and a mobile drawer via shadcn Sheet.
 */
export function SiteNav({ sub, links, rightSlot }: Props) {
  const pathname = usePathname();
  const isActive = (href: string) =>
    href.startsWith("/") && !href.startsWith("/#") && (href === "/" ? pathname === "/" : pathname?.startsWith(href));

  return (
    <header className="sticky top-0 z-30 border-b border-edge bg-background/90 backdrop-blur-md">
      <div className="mx-auto flex h-16 max-w-content items-center justify-between px-5 md:px-8">
        <Wordmark sub={sub} />

        {/* Desktop nav */}
        <nav className="hidden items-center gap-1 md:flex" aria-label="Primary">
          {links.map((l) => (
            <NavItem key={l.href} link={l} active={isActive(l.href)} />
          ))}
        </nav>

        <div className="flex items-center gap-2">
          {rightSlot && <div className="hidden md:flex">{rightSlot}</div>}

          {/* Mobile menu trigger */}
          <Sheet>
            <SheetTrigger asChild>
              <Button variant="ghost" size="icon" className="md:hidden" aria-label="Open menu">
                <Hamburger />
              </Button>
            </SheetTrigger>
            <SheetContent side="right" className="flex flex-col gap-6 pt-12">
              <SheetHeader>
                <SheetTitle>Menu</SheetTitle>
              </SheetHeader>
              <nav className="flex flex-col gap-1" aria-label="Mobile">
                {links.map((l) => (
                  <SheetClose asChild key={l.href}>
                    <Link
                      href={l.href}
                      className={cn(
                        "rounded-md px-3 py-2.5 font-sans text-[15px] transition-colors hover:bg-secondary",
                        isActive(l.href) ? "bg-secondary font-semibold text-ink" : "text-ink-soft",
                      )}
                    >
                      {l.label}
                    </Link>
                  </SheetClose>
                ))}
              </nav>
              {rightSlot && <div className="mt-auto flex flex-col gap-2">{rightSlot}</div>}
            </SheetContent>
          </Sheet>
        </div>
      </div>
    </header>
  );
}

function NavItem({ link, active }: { link: NavLink; active: boolean | undefined }) {
  const isInPage = link.href.startsWith("#");
  const cls = cn(
    "rounded-md px-3 py-1.5 font-sans text-[14px] transition-colors",
    active
      ? "bg-secondary font-semibold text-ink"
      : "text-ink-soft hover:bg-secondary hover:text-ink",
  );
  return isInPage ? (
    <a href={link.href} className={cls}>
      {link.label}
    </a>
  ) : (
    <Link href={link.href} className={cls} aria-current={active ? "page" : undefined}>
      {link.label}
    </Link>
  );
}

function Hamburger() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden>
      <line x1="4" y1="7" x2="20" y2="7" />
      <line x1="4" y1="12" x2="20" y2="12" />
      <line x1="4" y1="17" x2="20" y2="17" />
    </svg>
  );
}
