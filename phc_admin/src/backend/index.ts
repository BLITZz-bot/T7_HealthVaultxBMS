import { env } from '@/config/env';
import { mockRepository } from './mockRepository';
import type { PhcRepository } from './repository';
import { supabaseRepository } from './supabaseRepository';

export const repository: PhcRepository = env.backend === 'supabase' ? supabaseRepository : mockRepository;

export type * from './types';
