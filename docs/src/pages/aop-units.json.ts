import type { APIRoute } from 'astro';
import { getCollection } from 'astro:content';
import { bySections } from '../lib/aop-units';

export const GET: APIRoute = async () => {
    const units = await getCollection('units');
    const groups = await getCollection('groups');
    const body = {
        units: units.map((entry) => entry.data).sort(bySections),
        groups: groups.map((entry) => entry.data).sort(bySections),
    };
    return new Response(JSON.stringify(body), {
        headers: { 'Content-Type': 'application/json' },
    });
};
