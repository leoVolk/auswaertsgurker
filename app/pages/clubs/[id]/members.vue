<script setup lang="ts">
import type { DropdownMenuItem } from '@nuxt/ui'
import type { ClubRole } from '~/composables/useClubs'
import type { ClubMember } from '~/composables/useClubMembers'

const route = useRoute()
const clubId = computed(() => String(route.params.id))
const userId = useCurrentUserId()
const toast = useToast()
const showError = useErrorToast()

const { club, isOrganizer, refresh: refreshClub } = await useClub(clubId)
const { members, setRole, removeMember } = await useClubMembers(clubId)

useHead({ title: () => (club.value ? `Mitglieder · ${club.value.name}` : 'Mitglieder') })

async function changeRole(member: ClubMember, role: ClubRole) {
  try {
    await setRole(member.userId, role)
    // Eigene Rolle geändert: Rechte auf der Seite neu bestimmen
    if (member.userId === userId.value) await refreshClub()
    toast.add({
      title: `${member.displayName} ist jetzt ${ROLE_LABELS[role]}.`,
      color: 'success',
      icon: 'i-lucide-check'
    })
  } catch (error) {
    showError(error)
  }
}

const memberToRemove = ref<ClubMember | null>(null)
const removeOpen = computed({
  get: () => memberToRemove.value !== null,
  set: (open) => {
    if (!open) memberToRemove.value = null
  }
})

async function confirmRemove() {
  const member = memberToRemove.value
  if (!member) return
  try {
    await removeMember(member.userId)
    memberToRemove.value = null
    toast.add({ title: `${member.displayName} wurde entfernt.`, color: 'success', icon: 'i-lucide-check' })
  } catch (error) {
    showError(error)
  }
}

function memberActions(member: ClubMember): DropdownMenuItem[][] {
  const isSelf = member.userId === userId.value

  const roleAction: DropdownMenuItem = member.role === 'organizer'
    ? {
        label: isSelf ? 'Organisator-Rolle abgeben' : 'Zum Mitglied machen',
        icon: 'i-lucide-shield-off',
        onSelect: () => changeRole(member, 'member')
      }
    : {
        label: 'Zum Organisator machen',
        icon: 'i-lucide-shield-check',
        onSelect: () => changeRole(member, 'organizer')
      }

  if (isSelf) return [[roleAction]]

  return [
    [roleAction],
    [{
      label: 'Aus dem Fanclub entfernen',
      icon: 'i-lucide-user-x',
      color: 'error',
      onSelect: () => {
        memberToRemove.value = member
      }
    }]
  ]
}
</script>

<template>
  <UEmpty
    v-if="!club"
    icon="i-lucide-search-x"
    title="Fanclub nicht gefunden"
    description="Entweder stimmt der Link nicht oder du bist kein Mitglied dieses Fanclubs."
    :actions="[{ label: 'Zu meinen Fanclubs', to: '/' }]"
  />

  <div
    v-else
    class="space-y-6"
  >
    <ClubHeader
      :club="club"
      :back="{ label: 'Zurück zum Fanclub', to: `/clubs/${club.id}` }"
    />

    <ClubInviteCard
      v-if="isOrganizer"
      :club-id="club.id"
      :club-name="club.name"
    />

    <UCard
      :title="`Mitglieder (${members.length})`"
      :ui="{ body: 'p-0 sm:p-0' }"
    >
      <ul class="divide-y divide-default">
        <li
          v-for="member in members"
          :key="member.userId"
          class="flex items-center justify-between gap-3 px-4 py-3 sm:px-6"
        >
          <UUser
            :name="member.userId === userId ? `${member.displayName} (Du)` : member.displayName"
            :description="ROLE_LABELS[member.role]"
            :avatar="{ alt: member.displayName }"
          />

          <UDropdownMenu
            v-if="isOrganizer"
            :items="memberActions(member)"
            :content="{ align: 'end' }"
          >
            <UButton
              icon="i-lucide-ellipsis-vertical"
              color="neutral"
              variant="ghost"
              :aria-label="`Aktionen für ${member.displayName}`"
            />
          </UDropdownMenu>
        </li>
      </ul>
    </UCard>

    <UModal
      v-model:open="removeOpen"
      title="Mitglied entfernen?"
      :description="memberToRemove
        ? `${memberToRemove.displayName} verliert den Zugriff auf den Fanclub, Anmeldungen für Fahrten werden storniert. Solange der Einladungslink gültig ist, ist ein erneuter Beitritt möglich – erstelle bei Bedarf einen neuen Link.`
        : undefined"
    >
      <template #footer>
        <div class="flex w-full justify-end gap-2">
          <UButton
            label="Abbrechen"
            color="neutral"
            variant="ghost"
            @click="removeOpen = false"
          />
          <UButton
            label="Entfernen"
            color="error"
            loading-auto
            @click="confirmRemove"
          />
        </div>
      </template>
    </UModal>
  </div>
</template>
