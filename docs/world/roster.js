/**
 * The six agents of the town: who they are, where they live and what colour
 * their building glows. Pure data — the scene, the HUD and the mission flow
 * all read from here, so an agent is described in exactly one place.
 *
 * `angle` is the building's position around the plaza, in degrees clockwise
 * from north (the far side of the island from the default camera).
 */
export const ROSTER = [
	{
		id: 'planner',
		name: 'Planner',
		building: 'townhall',
		place: 'Town Hall',
		job: 'Splits the mission into assignments',
		color: '#a58bff',
		angle: 0,
	},
	{
		id: 'researcher',
		name: 'Researcher',
		building: 'library',
		place: 'Library',
		job: 'Finds current, sourced facts on the web',
		color: '#5aa9ff',
		angle: 60,
	},
	{
		id: 'analyst',
		name: 'Analyst',
		building: 'observatory',
		place: 'Observatory',
		job: 'Weighs options, numbers and trade-offs',
		color: '#4fd8c4',
		angle: 120,
	},
	{
		id: 'engineer',
		name: 'Engineer',
		building: 'workshop',
		place: 'Workshop',
		job: 'Works out the technical parts',
		color: '#ffa24a',
		angle: 180,
	},
	{
		id: 'writer',
		name: 'Writer',
		building: 'printshop',
		place: 'Print Shop',
		job: 'Assembles the final deliverable',
		color: '#ff7eb6',
		angle: 240,
	},
	{
		id: 'critic',
		name: 'Critic',
		building: 'watchtower',
		place: 'Watchtower',
		job: 'Reviews the draft against the mission',
		color: '#ffd84a',
		angle: 300,
	},
];

/** The specialists the Planner may assign work to. */
export const SPECIALISTS = ['researcher', 'analyst', 'engineer'];

/** Where finished work is delivered; not an agent, but couriers travel to it. */
export const PLAZA = 'plaza';

export function agentById(id) {
	return ROSTER.find((a) => a.id === id) || null;
}
