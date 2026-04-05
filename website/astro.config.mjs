// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// https://astro.build/config
export default defineConfig({
  site: 'https://toshi-kuji.github.io',
  base: '/enja-switcher/',
  trailingSlash: 'always',
  output: 'static',
  integrations: [sitemap()],
});
