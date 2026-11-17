import { defineCollection } from 'astro:content';
import { file } from 'astro/loaders';
import { z } from 'astro/zod';
import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';
import { BOXES, MAX_SPAN, STATUSES } from './lib/aop-units';

const UNIT_ID = z.string().regex(/^[a-z0-9]+(-[a-z0-9A-Z]+)*$/);

const units = defineCollection({
    loader: file('src/data/aop-units.yml'),
    schema: z.strictObject({
        id: UNIT_ID,
        nature: z.string(),
        sections: z.string(),
        status: z.enum(STATUSES),
        box: z.enum(BOXES),
        parent: UNIT_ID.optional(),
        group: z.string().optional(),
        note: z.string().optional(),
    }),
});

const groups = defineCollection({
    loader: file('src/data/aop-groups.yml'),
    schema: z.strictObject({
        id: z.string(),
        label: z.string(),
        sections: z.string(),
        box: z.enum(BOXES),
        span: z.number().int().min(1).max(MAX_SPAN).optional(),
    }),
});

export const collections = {
    docs: defineCollection({ loader: docsLoader(), schema: docsSchema() }),
    units,
    groups,
};
