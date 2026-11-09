import { z } from 'zod'

const querySchema = z.object({
  league: z.enum(LEAGUE_SHORTCUTS)
})

export default defineEventHandler(async (event) => {
  const { league } = await getValidatedQuery(event, querySchema.parse)

  try {
    return await getLeagueTeams(league, currentSeason())
  } catch (error) {
    console.error('OpenLigaDB teams', error)
    throw createError({ statusCode: 502, statusMessage: 'OpenLigaDB ist gerade nicht erreichbar.' })
  }
})
