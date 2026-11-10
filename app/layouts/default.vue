<script setup lang="ts">
const userId = useCurrentUserId()
</script>

<template>
  <div>
    <!--
      Menü wie auf ui.nuxt.com: Hamburger öffnet ein Vollbild-Overlay mit eigener Kopfzeile.
      Nuxt UI blendet Toggle und Menü ab lg aus; hier sind sie überall sichtbar, weil es keine
      zweite Navigation für große Bildschirme gibt. Kopfzeile und Inhalt des Menüs haben dieselbe
      Breite wie der Header-Container, damit der Schließen-Knopf genau über dem Hamburger liegt.
    -->
    <UHeader
      to="/"
      title="Auswärtsgurker"
      :toggle="!!userId"
      :ui="{
        container: 'max-w-4xl',
        toggle: 'lg:inline-flex',
        overlay: 'lg:block',
        content: 'lg:flex',
        header: 'mx-auto w-full max-w-4xl lg:px-8',
        body: 'mx-auto w-full max-w-4xl lg:px-8'
      }"
    >
      <template #title>
        <span class="flex items-center gap-2">
          <UIcon
            name="i-lucide-bus"
            class="size-5 text-primary"
          />
          Auswärtsgurker
          <UBadge
            label="Beta"
            variant="subtle"
            size="sm"
          />
        </span>
      </template>

      <template #right>
        <UColorModeButton />
      </template>

      <template #body>
        <UserMenu />
      </template>
    </UHeader>

    <UMain>
      <div class="mx-auto w-full max-w-4xl lg:px-12 px-4 py-6 sm:py-10">
        <slot />
      </div>
    </UMain>
  </div>
</template>
