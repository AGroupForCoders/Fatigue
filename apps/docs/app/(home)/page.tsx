import { redirect } from 'next/navigation';
import { docsRoute } from '@/lib/shared';

// The docs are the whole site for now, so the home page sends you straight there.
export default function HomePage() {
  redirect(docsRoute);
}
