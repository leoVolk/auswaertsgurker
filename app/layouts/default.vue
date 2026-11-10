<template>
  <div>
    <UHeader
      to="/"
      :toggle="false"
      :ui="{ container: 'max-w-4xl' }"
    >
      <template #title>
        <span class="flex items-center gap-2">
          <UIcon
            name="i-lucide-bus"
            class="size-5 text-primary"
          />
          Auswärtsgurker
        </span>
      </template>

      <template #right>
        <UColorModeButton />
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
