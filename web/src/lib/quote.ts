import type { Item } from './api'

export interface QuoteSource {
  title: string | null
  author?: string | null
  url?: string | null
}

export function buildQuotePrefill(
  selection: string,
  source: QuoteSource
): string {
  const quote = selection
    .split('\n')
    .map((line) => `> ${line}`)
    .join('\n')

  const title = source.title?.trim() || 'Untitled'
  const titleLink = source.url ? `[${title}](${source.url})` : title
  const attribution = source.author
    ? `— ${source.author}, ${titleLink}`
    : `— ${titleLink}`

  return `${quote}\n\n${attribution}\n\n`
}

export function itemToQuoteSource(item: Item): QuoteSource {
  return {
    title: item.title,
    author: item.author,
    url: item.url,
  }
}
