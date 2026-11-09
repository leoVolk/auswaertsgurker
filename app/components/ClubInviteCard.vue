<script setup lang="ts">
const props = defineProps<{
  clubId: string
  clubName: string
}>()

const { link, regenerate } = await useClubInvite(() => props.clubId)
const toast = useToast()
const showError = useErrorToast()

// Teilen-Dialog des Handys gibt es nur im Browser und nicht überall
const canShare = ref(false)
onMounted(() => {
  canShare.value = typeof navigator.share === 'function'
})

const shareText = computed(() => `Komm in unseren Fanclub „${props.clubName}“ bei Auswärtsfahrt:`)
const whatsappUrl = computed(() =>
  `https://wa.me/?text=${encodeURIComponent(`${shareText.value} ${link.value}`)}`
)

async function copyLink() {
  if (!link.value) return
  try {
    await navigator.clipboard.writeText(link.value)
    toast.add({ title: 'Link kopiert', color: 'success', icon: 'i-lucide-check' })
  } catch (error) {
    showError(error, 'Kopieren hat nicht geklappt. Markiere den Link und kopiere ihn von Hand.')
  }
}

async function shareLink() {
  if (!link.value) return
  try {
    await navigator.share({ title: props.clubName, text: shareText.value, url: link.value })
  } catch (error) {
    // Schließen des Teilen-Dialogs ist kein Fehler
    if (error instanceof DOMException && error.name === 'AbortError') return
    showError(error)
  }
}

const confirmOpen = ref(false)

async function onRegenerate() {
  try {
    await regenerate()
    confirmOpen.value = false
    toast.add({
      title: 'Neuer Link erstellt',
      description: 'Der alte Link funktioniert ab sofort nicht mehr.',
      color: 'success',
      icon: 'i-lucide-check'
    })
  } catch (error) {
    showError(error)
  }
}
</script>

<template>
  <UCard
    title="Mitglieder einladen"
    description="Teile den Link in eurer WhatsApp-Gruppe. Wer ihn öffnet, kann dem Fanclub beitreten."
  >
    <div
      v-if="link"
      class="space-y-3"
    >
      <UFieldGroup class="w-full">
        <UInput
          :model-value="link"
          readonly
          aria-label="Einladungslink"
          class="w-full"
          @focus="($event.target as HTMLInputElement).select()"
        />
        <UButton
          icon="i-lucide-copy"
          color="neutral"
          variant="subtle"
          aria-label="Link kopieren"
          @click="copyLink"
        />
      </UFieldGroup>

      <UButton
        v-if="canShare"
        label="Link teilen"
        icon="i-lucide-share-2"
        size="lg"
        block
        @click="shareLink"
      />
      <UButton
        v-else
        :to="whatsappUrl"
        target="_blank"
        label="In WhatsApp teilen"
        icon="i-simple-icons-whatsapp"
        size="lg"
        block
      />
    </div>

    <UButton
      v-else
      label="Einladungslink erstellen"
      icon="i-lucide-link"
      size="lg"
      block
      loading-auto
      @click="onRegenerate"
    />

    <template
      v-if="link"
      #footer
    >
      <UModal
        v-model:open="confirmOpen"
        title="Neuen Link erstellen?"
        description="Der bisherige Link funktioniert danach nicht mehr. Wer schon Mitglied ist, bleibt Mitglied."
      >
        <UButton
          label="Neuen Link erstellen"
          icon="i-lucide-refresh-cw"
          color="neutral"
          variant="link"
          class="-ms-2.5"
        />

        <template #footer>
          <div class="flex w-full justify-end gap-2">
            <UButton
              label="Abbrechen"
              color="neutral"
              variant="ghost"
              @click="confirmOpen = false"
            />
            <UButton
              label="Neuen Link erstellen"
              loading-auto
              @click="onRegenerate"
            />
          </div>
        </template>
      </UModal>
    </template>
  </UCard>
</template>
