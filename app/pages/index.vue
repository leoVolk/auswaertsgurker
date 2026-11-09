<script setup lang="ts">
useHead({ title: 'Meine Fanclubs' })

const { clubs, error } = await useMyClubs()

// Die meisten sind nur in einem Fanclub: direkt dorthin
const [onlyClub] = clubs.value
if (clubs.value.length === 1 && onlyClub) {
  await navigateTo(`/clubs/${onlyClub.id}`, { replace: true })
}
</script>

<template>
  <div class="space-y-6">
    <h1 class="text-2xl font-bold text-highlighted">
      Meine Fanclubs
    </h1>

    <UAlert
      v-if="error"
      color="error"
      variant="subtle"
      icon="i-lucide-circle-alert"
      title="Deine Fanclubs konnten nicht geladen werden."
    />

    <UEmpty
      v-else-if="!clubs.length"
      icon="i-lucide-flag"
      title="Noch kein Fanclub"
      description="Öffne den Einladungslink aus deiner WhatsApp-Gruppe oder gründe selbst einen Fanclub."
      :actions="[{ label: 'Fanclub gründen', icon: 'i-lucide-plus', to: '/clubs/new' }]"
    />

    <template v-else>
      <ul class="space-y-3">
        <li
          v-for="club in clubs"
          :key="club.id"
        >
          <NuxtLink
            :to="`/clubs/${club.id}`"
            class="block rounded-lg focus-visible:outline-2 focus-visible:outline-primary"
          >
            <UCard
              class="transition-colors hover:bg-elevated/50"
              :ui="{ body: 'flex items-center justify-between gap-3' }"
            >
              <span class="font-medium text-highlighted">{{ club.name }}</span>
              <span class="flex shrink-0 items-center gap-2">
                <UBadge
                  v-if="club.role === 'organizer'"
                  :label="ROLE_LABELS.organizer"
                  variant="subtle"
                />
                <UIcon
                  name="i-lucide-chevron-right"
                  class="size-5 text-dimmed"
                />
              </span>
            </UCard>
          </NuxtLink>
        </li>
      </ul>

      <UButton
        to="/clubs/new"
        label="Weiteren Fanclub gründen"
        icon="i-lucide-plus"
        color="neutral"
        variant="outline"
        block
      />
    </template>
  </div>
</template>
