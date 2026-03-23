import { Link } from 'react-router'
import { FileQuestion } from 'lucide-react'

// ---------------------------------------------------------------------------
// NotFoundScreen — 404 for unknown slugs
// ---------------------------------------------------------------------------

interface NotFoundScreenProps {
  slug?: string
}

export function NotFoundScreen({ slug }: NotFoundScreenProps) {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-4 bg-background p-4">
      <FileQuestion className="size-12 text-muted-foreground" />
      <h1 className="text-2xl font-bold">App Not Found</h1>
      <p className="text-muted-foreground">
        {slug ? (
          <>
            No app exists at <code className="rounded bg-muted px-1.5 py-0.5">/{slug}</code>.
          </>
        ) : (
          'The requested app could not be found.'
        )}
      </p>
      <Link to="/admin" className="inline-flex items-center justify-center rounded-md border border-input bg-background px-4 py-2 text-sm font-medium hover:bg-accent">Back to Admin</Link>
    </div>
  )
}
