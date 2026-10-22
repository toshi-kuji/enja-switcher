import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';
import { z } from 'astro/zod';

// 記事は src/content/blog/{ja,en}/<slug>.md に置く。
// 同じ <slug> のファイルが ja / en の両方にあれば、言語切替リンクが翻訳記事に繋がる。
const blog = defineCollection({
  loader: glob({ pattern: '{ja,en}/*.md', base: './src/content/blog' }),
  schema: z.object({
    title: z.string(),
    description: z.string(),
    date: z.coerce.date(),
    draft: z.boolean().default(false),
  }),
});

export const collections = { blog };
