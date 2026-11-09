import { z } from 'zod'

const querySchema = z.object({
  league: z.enum(LEAGUE_SHORTCUTS),
  teamId: z.coerce.number().int().positive()
})

export default defineEventHandler(async (event) => {
  const { league, teamId } = await getValidatedQuery(event, querySchema.parse)

  try {
    return await getUpcomingAwayMatches(league, currentSeason(), teamId)
  } catch (error) {
    console.error('OpenLigaDB matches', error)
    throw createError({ statusCode: 502, statusMessage: 'OpenLigaDB ist gerade nicht erreichbar.' })
  }
})
