export function useErrorToast() {
  const toast = useToast()

  return (error: unknown, fallback?: string) => {
    console.error(error)
    toast.add({
      title: errorMessage(error, fallback),
      color: 'error',
      icon: 'i-lucide-circle-alert'
    })
  }
}
