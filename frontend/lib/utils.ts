import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

/** Merge Tailwind classes safely (clsx + tailwind-merge). shadcn's standard helper. */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
