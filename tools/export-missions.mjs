// export-missions.mjs
//
// One-shot extractor: reads the companion web app's js/missions.js, evaluates
// just the top-of-file data declarations (everything before `class MissionManager`),
// and writes the result out as Missions.json bundled into the iOS app.
//
// Run with:  node tools/export-missions.mjs
//
// The web file imports a handful of modules (three, sceneBuilder, orbitalMechanics,
// solarSystemData, textureGenerator) — none of which are touched by the raw data
// declarations at the top of the file, so we stub them to empty objects before
// evaluating the extracted source.

import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const here = dirname(fileURLToPath(import.meta.url));
const webMissionsPath = resolve(here, '../../solarsystem-web/js/missions.js');
const outputPath = resolve(here, '../SolarSystem/Resources/Missions.json');

const source = readFileSync(webMissionsPath, 'utf8');

// Slice off everything from `class MissionManager` onward — we only want the
// data declarations (ALL_MISSIONS plus the individual mission constants).
const marker = source.indexOf('\nexport class MissionManager');
if (marker === -1) {
    console.error('Could not locate MissionManager class in', webMissionsPath);
    process.exit(1);
}
let dataSource = source.slice(0, marker);

// Drop the `import` statements (replaced by stubs in the sandbox).
dataSource = dataSource.replace(/^import [^;]+;\s*$/gm, '');

// Add a line that surfaces ALL_MISSIONS to the sandbox.
dataSource += '\nthis.ALL_MISSIONS = ALL_MISSIONS;\n';

// Set up a stubbed sandbox: Date comes from the host, everything the web file
// "imports" is a no-op object (the raw data doesn't call into these helpers).
const sandbox = {
    Date, Math, Number, Array, Object, String, Boolean, JSON,
    THREE: {}, sceneRadius: () => 0, eclipticToScene: () => ({ x: 0, y: 0, z: 0 }),
    MOON_DIST_EXPONENT: 0.6, MOON_DIST_SCALE: 1.5,
    moonPosition: () => ({ x: 0, y: 0, z: 0 }), heliocentricPosition: () => ({ x: 0, y: 0, z: 0 }),
    earthMoon: {}, BodyType: {}, allPlanets: [],
    generateGlowTexture: () => null,
    console,
};
vm.createContext(sandbox);
vm.runInContext(dataSource, sandbox);

const missions = sandbox.ALL_MISSIONS;
if (!Array.isArray(missions)) {
    console.error('ALL_MISSIONS not extracted');
    process.exit(1);
}

// Normalise the JS shape for Swift's Codable layer.
//   - Convert launchDate (Date) to ISO-8601 string.
//   - Drop `description` / `subtitle` defaults when missing.
//   - Default `referenceFrame` to "geocentric" (matches web default).
const normalised = missions.map((m) => ({
    id: m.id,
    name: m.name,
    subtitle: m.subtitle ?? '',
    launchDate: new Date(m.launchDate).toISOString(),
    durationHours: m.durationHours,
    flybyTimeHours: m.flybyTimeHours ?? null,
    referenceFrame: m.referenceFrame ?? 'geocentric',
    autoTrajectory: m.autoTrajectory ?? null,
    events: (m.events ?? []).map((e) => ({
        t: e.t,
        name: e.name,
        detail: e.detail,
        showLabel: e.showLabel !== false,
    })),
    vehicles: (m.vehicles ?? []).map((v) => ({
        id: v.id,
        name: v.name,
        color: v.color,
        primary: v.primary === true,
        autoTrajectory: v.autoTrajectory ?? null,
        moonOrbit: v.moonOrbit ?? null,
        moonLanding: v.moonLanding ?? null,
        moonOrbitReturn: v.moonOrbitReturn ?? null,
        waypoints: (v.waypoints ?? []).map((w) => ({
            t: w.t, x: w.x, y: w.y, z: w.z,
            anchorMoon: w.anchorMoon === true,
            anchorBody: w.anchorBody ?? null,
        })),
    })),
}));

mkdirSync(dirname(outputPath), { recursive: true });
writeFileSync(outputPath, JSON.stringify(normalised, null, 2));
console.log(`Wrote ${normalised.length} missions to ${outputPath}`);
for (const m of normalised) {
    const wpCount = m.vehicles.reduce((n, v) => n + v.waypoints.length, 0);
    console.log(`  - ${m.id}: ${m.vehicles.length} vehicle(s), ${m.events.length} event(s), ${wpCount} waypoint(s)`);
}
