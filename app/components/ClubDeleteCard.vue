<script setup lang="ts">
import type { ClubDeletionSummary, ClubMembership } from '~/composables/useClubs'

const props = defineProps<{
  club: ClubMembership
}>()

const { fetchDeletionSummary, deleteClub } = useClubMembershipEnd()
const toast = useToast()
const showError = useErrorToast()

const open = ref(false)
const summary = ref<ClubDeletionSummary | null>(null)
const confirmName = ref('')

const nameMatches = computed(() => confirmName.value.trim() === props.club.name.trim())

watch(open, async (isOpen) => {
  if (!isOpen) return
  confirmName.value = ''
  summary.value = null
  try {
    summary.value = await fetchDeletionSummary(props.club.id)
  } catch (error) {
    showError(error)
  }
})

const summaryLines = computed(() => {
  const s = summary.value
  if (!s) return []
  return [
    `${s.members} ${s.members === 1 ? 'Mitglied' : 'Mitglieder'}`,
    `${s.trips} ${s.trips === 1 ? 'Fahrt' : 'Fahrten'} mit allen Anmeldungen`,
    `${s.ticketRounds} ${s.ticketRounds === 1 ? 'Ticketabfrage' : 'Ticketabfragen'} mit allen Anfragen`,
    ...(s.ticketFiles ? [`${s.ticketFiles} hochgeladene Ticket-PDFs`] : [])
  ]
})

async function onDelete() {
  if (!nameMatches.value) return
  try {
    await deleteClub(props.club.id)
    open.value = false
    clearNuxtData()
    toast.add({ title: `${props.club.name} wurde gelöscht`, color: 'success', icon: 'i-lucide-check' })
    await navigateTo('/', { replace: true })
  } catch (error) {
    showError(error)
  }
}
</script>

<template>
  <UCard
    title="Fanclub löschen"
    description="Löscht den Fanclub mit allen Fahrten, Tickets und Mitgliedschaften endgültig."
    :ui="{ root: 'ring-error/40' }"
  >
    <UModal
      v-model:open="open"
      title="Fanclub endgültig löschen?"
      description="Das lässt sich nicht rückgängig machen."
    >
      <UButton
        label="Fanclub löschen"
        icon="i-lucide-trash-2"
        color="error"
        variant="outline"
        size="lg"
        block
      />

      <template #body>
        <div class="space-y-4">
          <div
            v-if="summary"
            class="space-y-2 text-sm"
          >
            <p class="text-highlighted">
              Mit {{ club.name }} verschwinden:
            </p>
            <ul class="list-inside list-disc text-muted">
              <li
                v-for="line in summaryLines"
                :key="line"
              >
                {{ line }}
              </li>
            </ul>
          </div>
          <UEmpty
            v-else
            loading
            variant="naked"
            size="sm"
          />

          <UAlert
            v-if="summary?.openPayments"
            color="warning"
            variant="subtle"
            icon="i-lucide-triangle-alert"
            :title="summary.openPayments === 1
              ? 'Es gibt 1 bestätigte Zahlung für ein kommendes Spiel.'
              : `Es gibt ${summary.openPayments} bestätigte Zahlungen für kommende Spiele.`"
            description="Erstatte sie, bevor du den Fanclub löschst. Danach sind alle Zahlungsdaten weg."
          />

          <UFormField :label="`Zur Bestätigung „${club.name}“ eintippen`">
            <UInput
              v-model="confirmName"
              autocomplete="off"
              size="lg"
              class="w-full"
            />
          </UFormField>
        </div>
      </template>

      <template #footer>
        <div class="flex w-full justify-end gap-2">
          <UButton
            label="Abbrechen"
            color="neutral"
            variant="ghost"
            @click="open = false"
          />
          <UButton
            label="Endgültig löschen"
            color="error"
            :disabled="!nameMatches || !summary"
            loading-auto
            @click="onDelete"
          />
        </div>
      </template>
    </UModal>
  </UCard>
</template>
