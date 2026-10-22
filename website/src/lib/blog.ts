import { getCollection, type CollectionEntry } from 'astro:content';

export type Lang = 'ja' | 'en';
export type BlogEntry = CollectionEntry<'blog'>;

// id は "ja/hello-world" 形式。言語とスラッグに分解する。
export function splitId(id: string): { lang: Lang; slug: string } {
  const [lang, ...rest] = id.split('/');
  return { lang: lang as Lang, slug: rest.join('/') };
}

export async function getPosts(lang: Lang): Promise<BlogEntry[]> {
  const all = await getCollection('blog', ({ id, data }) => {
    return splitId(id).lang === lang && (import.meta.env.DEV || !data.draft);
  });
  return all.sort((a, b) => b.data.date.valueOf() - a.data.date.valueOf());
}

export async function hasTranslation(lang: Lang, slug: string): Promise<boolean> {
  const posts = await getPosts(lang);
  return posts.some((p) => splitId(p.id).slug === slug);
}
