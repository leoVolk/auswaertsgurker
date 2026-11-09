<script setup lang="ts">
import type { TicketCategory, TicketRequest } from '~/composables/useTickets'

const props = defineProps<{
  clubId: string
  categories: TicketCategory[]
  /** Zugeteilte Tickets, denen PDFs zugeordnet werden können */
  candidates: TicketRequest[]
  /** Gesetzt: genau ein PDF für dieses Ticket; sonst Sammel-Upload mit Zuordnung */
  target?: TicketRequest | null
}>()

const emit = defineEmits<{ uploaded: [] }>()
const open = defineModel<boolean>('open', { required: true })

const { uploadTicketFile } = useTicketDeliveryActions(() => props.clubId)
const toast = useToast()
const showError = useErrorToast()

const NONE = 'none'

const singleFile = ref<File | null>(null)
const files = ref<File[]>([])
const assignments = ref<string[]>([])
const progress = ref<{ done: number, total: number } | null>(null)

watch(open, (isOpen) => {
  if (!isOpen) return
  singleFile.value = null
  files.value = []
  assignments.value = []
  progress.value = null
})

const categoryName = (categoryId: string) => props.categories.find(c => c.id === categoryId)?.name ?? ''

const candidateItems = computed(() => [
  { label: 'Nicht zuordnen', value: NONE },
  ...props.candidates.map(c => ({
    label: `${c.holderName} · ${categoryName(c.categoryId)}${c.ticketFilePath ? ' (ersetzt PDF)' : ''}`,
    value: c.id
  }))
])

function tokens(value: string) {
  return value
    .normalize('NFD')
    .replace(/\p{Diacritic}/gu, '')
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter(token => token.length >= 2)
}

/** Ordnet PDFs vor: zuerst über den Namen im Dateinamen, dann in Reihenfolge der Tickets ohne PDF. */
function suggestAssignments(selected: File[]) {
  const used = new Set<string>()
  const result: (string | null)[] = selected.map((file) => {
    const fileTokens = new Set(tokens(file.name))
    const match = props.candidates.find((candidate) => {
      const nameTokens = tokens(candidate.holderName)
      return !used.has(candidate.id) && nameTokens.length > 0 && nameTokens.every(t => fileTokens.has(t))
    })
    if (match) used.add(match.id)
    return match?.id ?? null
  })

  const queue = [
    ...props.candidates.filter(c => !c.ticketFilePath),
    ...props.candidates.filter(c => c.ticketFilePath)
  ].filter(c => !used.has(c.id))

  return result.map(id => id ?? queue.shift()?.id ?? NONE)
}

watch(files, (selected) => {
  assignments.value = suggestAssignments(selected)
})

const fileProblems = computed(() => files.value.map(file => ticketFileProblem(file)))

const duplicateTarget = computed(() => {
  const chosen = assignments.value.filter(id => id !== NONE)
  return chosen.length !== new Set(chosen).size
})

const uploadCount = computed(() =>
  files.value.filter((_, index) => assignments.value[index] !== NONE && !fileProblems.value[index]).length
)

async function uploadSingle() {
  if (!props.target || !singleFile.value) return
  try {
    await uploadTicketFile(props.target.id, singleFile.value)
    open.value = false
    toast.add({ title: `PDF für ${props.target.holderName} hinterlegt`, color: 'success', icon: 'i-lucide-check' })
    emit('uploaded')
  } catch (error) {
    showError(error)
  }
}

async function uploadAll() {
  if (duplicateTarget.value) return
  const jobs = files.value
    .map((file, index) => ({ file, requestId: assignments.value[index] ?? NONE, problem: fileProblems.value[index] }))
    .filter(job => job.requestId !== NONE && !job.problem)

  progress.value = { done: 0, total: jobs.length }
  const failures: unknown[] = []
  for (const job of jobs) {
    try {
      await uploadTicketFile(job.requestId, job.file)
    } catch (error) {
      failures.push(error)
    }
    progress.value = { done: progress.value.done + 1, total: jobs.length }
  }

  const succeeded = jobs.length - failures.length
  if (succeeded) {
    toast.add({
      title: succeeded === 1 ? '1 PDF hinterlegt' : `${succeeded} PDFs hinterlegt`,
      color: 'success',
      icon: 'i-lucide-check'
    })
    emit('uploaded')
  }
  if (failures.length) {
    showError(failures[0], `${failures.length} PDFs konnten nicht hochgeladen werden.`)
    progress.value = null
    return
  }
  open.value = false
}
</script>

<template>
  <UModal
    v-model:open="open"
    :title="target ? 'PDF hochladen' : 'PDFs hochladen'"
    :description="target
      ? `Ticket von ${target.holderName}. Ein vorhandenes PDF wird ersetzt.`
      : 'Ein PDF pro Ticket, max. 5 MB. Die Zuordnung schlägt die App anhand der Dateinamen vor.'"
  >
    <template #body>
      <div
        v-if="target"
        class="space-y-4"
      >
        <UFileUpload
          v-model="singleFile"
          accept="application/pdf"
          label="PDF hier ablegen"
          description="oder tippen, um eine Datei auszuwählen"
          icon="i-lucide-file-up"
          layout="list"
          class="w-full"
        />
        <UButton
          label="Hochladen"
          icon="i-lucide-upload"
          size="lg"
          block
          :disabled="!singleFile"
          loading-auto
          @click="uploadSingle"
        />
      </div>

      <div
        v-else
        class="space-y-4"
      >
        <UFileUpload
          v-model="files"
          multiple
          accept="application/pdf"
          label="PDFs hier ablegen"
          description="oder tippen, um Dateien auszuwählen"
          icon="i-lucide-file-up"
          layout="list"
          :preview="false"
          class="w-full"
        />

        <ul
          v-if="files.length"
          class="divide-y divide-default rounded-md border border-default"
        >
          <li
            v-for="(file, index) in files"
            :key="`${file.name}-${index}`"
            class="space-y-2 p-3"
          >
            <p class="flex items-center gap-2 text-sm font-medium text-highlighted">
              <UIcon
                name="i-lucide-file-text"
                class="size-4 shrink-0 text-muted"
              />
              <span class="truncate">{{ file.name }}</span>
            </p>
            <p
              v-if="fileProblems[index]"
              class="text-sm text-error"
            >
              {{ fileProblems[index] }}
            </p>
            <USelect
              v-else
              v-model="assignments[index]"
              :items="candidateItems"
              class="w-full"
            />
          </li>
        </ul>

        <UAlert
          v-if="duplicateTarget"
          color="warning"
          variant="subtle"
          icon="i-lucide-triangle-alert"
          title="Ein Ticket ist mehreren PDFs zugeordnet."
        />

        <UButton
          :label="progress ? `Lade hoch … ${progress.done}/${progress.total}` : `${uploadCount} PDFs hochladen`"
          icon="i-lucide-upload"
          size="lg"
          block
          :disabled="!uploadCount || duplicateTarget"
          :loading="!!progress"
          @click="uploadAll"
        />
      </div>
    </template>
  </UModal>
</template>
