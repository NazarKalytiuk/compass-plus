// Seeds compass_test.users_large with 200_000 ~5 KB documents.
// Run: mongosh mongodb://localhost:27017 scripts/seed_compass_test.js
//
// Drops the collection first, then bulk-inserts batches of 1000.
// Creates indexes on email, status, createdAt after the load.

const TOTAL = 200_000;
const BATCH = 1000;
const DB_NAME = "compass_test";
const COLL_NAME = "users_large";

const tiers = ["free", "pro", "enterprise", "trial"];
const statuses = ["active", "pending", "inactive", "trialing", "disabled"];
const roles = ["user", "admin", "owner", "viewer", "editor"];
const countries = ["UA", "PL", "DE", "US", "GB", "FR", "IT", "ES", "NL", "PT", "CA", "AU", "BR", "JP"];
const cities = ["Kyiv", "Lviv", "Warsaw", "Krakow", "Berlin", "Munich", "New York", "London", "Paris", "Rome", "Madrid", "Amsterdam", "Lisbon", "Toronto"];
const themes = ["dark", "light", "auto", "midnight", "solarized", "high-contrast"];
const languages = ["en", "uk", "pl", "de", "fr", "es", "it", "pt", "nl", "ja"];
const tagPool = [
    "premium", "verified", "newsletter", "beta", "alpha", "internal", "external",
    "vip", "high-value", "low-risk", "support-priority", "early-adopter", "churn-risk",
    "trial-extended", "cohort-q1", "cohort-q2", "feature-flag-a", "feature-flag-b",
    "experiment-on", "experiment-off", "marketing", "sales-qualified", "product-qualified",
    "expansion-target", "renewal-due", "auto-renew", "manual-renew"
];
const activityTypes = ["login", "logout", "page-view", "search", "purchase", "refund", "settings", "export", "import", "share"];
const browsers = ["Chrome/124.0", "Firefox/126.0", "Safari/17.5", "Edge/124.0"];
const platforms = ["macOS 14.5", "Windows 11", "Ubuntu 22.04", "iOS 17.5", "Android 14"];
const planNames = ["Starter", "Growth", "Business", "Scale", "Enterprise"];

// Bigger pool of words to stuff into "notes" so documents push ~5KB without
// being a single repeating literal that compresses too well.
const wordPool = (
    "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod " +
    "tempor incididunt ut labore et dolore magna aliqua enim ad minim veniam " +
    "quis nostrud exercitation ullamco laboris nisi aliquip ex ea commodo " +
    "consequat duis aute irure dolor reprehenderit voluptate velit esse cillum " +
    "fugiat nulla pariatur excepteur sint occaecat cupidatat non proident sunt " +
    "in culpa qui officia deserunt mollit anim id est laborum"
).split(" ");

function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }
function pickN(arr, n) {
    const out = [];
    const used = new Set();
    while (out.length < n) {
        const idx = Math.floor(Math.random() * arr.length);
        if (used.has(idx)) continue;
        used.add(idx);
        out.push(arr[idx]);
    }
    return out;
}
function randInt(min, max) { return Math.floor(Math.random() * (max - min + 1)) + min; }
function randFloat(min, max, d = 2) {
    return Number((Math.random() * (max - min) + min).toFixed(d));
}
function randomWords(count) {
    const out = [];
    for (let i = 0; i < count; i++) out.push(pick(wordPool));
    return out.join(" ");
}
function randomDateInPast(days) {
    const now = Date.now();
    return new Date(now - Math.floor(Math.random() * days * 24 * 3600 * 1000));
}
function randomDateInFuture(days) {
    const now = Date.now();
    return new Date(now + Math.floor(Math.random() * days * 24 * 3600 * 1000));
}

function makeDoc(i) {
    const created = randomDateInPast(900);
    const updated = new Date(created.getTime() + randInt(0, 30 * 24 * 3600 * 1000));
    const lastLogin = new Date(updated.getTime() + randInt(0, 60 * 24 * 3600 * 1000));
    const trialEnds = Math.random() < 0.3 ? randomDateInFuture(60) : randomDateInPast(120);

    const tier = pick(tiers);
    const status = pick(statuses);
    const role = pick(roles);

    const recentActivity = [];
    const activityCount = randInt(8, 14);
    for (let k = 0; k < activityCount; k++) {
        recentActivity.push({
            at: randomDateInPast(60),
            type: pick(activityTypes),
            ip: `${randInt(10, 250)}.${randInt(0, 255)}.${randInt(0, 255)}.${randInt(0, 255)}`,
            ua: `${pick(browsers)} on ${pick(platforms)}`,
            durationMs: randInt(50, 12000),
            success: Math.random() > 0.05,
            referrer: `https://example-${randInt(1, 50)}.test/page-${randInt(1, 999)}`
        });
    }

    const sessionHistory = [];
    const sessionCount = randInt(6, 12);
    for (let k = 0; k < sessionCount; k++) {
        const sStart = randomDateInPast(180);
        const sEnd = new Date(sStart.getTime() + randInt(60, 7200) * 1000);
        sessionHistory.push({
            id: `sess_${i}_${k}_${randInt(1000, 9999)}`,
            started: sStart,
            ended: sEnd,
            durationSec: Math.floor((sEnd - sStart) / 1000),
            ipAddress: `${randInt(10, 250)}.${randInt(0, 255)}.${randInt(0, 255)}.${randInt(0, 255)}`,
            ua: `${pick(browsers)} on ${pick(platforms)}`,
            ended_clean: Math.random() > 0.1
        });
    }

    const experience = [];
    const expCount = randInt(3, 6);
    for (let k = 0; k < expCount; k++) {
        experience.push({
            company: `Company ${randInt(1, 500)} Ltd`,
            role: pick(["Engineer", "Manager", "Designer", "Analyst", "Lead", "Director"]),
            from: randInt(2008, 2020),
            to: randInt(2020, 2025),
            location: pick(cities),
            summary: randomWords(randInt(15, 30))
        });
    }

    const education = [];
    const eduCount = randInt(1, 3);
    for (let k = 0; k < eduCount; k++) {
        education.push({
            school: `${pick(["State", "National", "City", "Tech", "Open"])} University of ${pick(cities)}`,
            degree: pick(["BSc", "MSc", "PhD", "BA", "MA", "MBA"]),
            field: pick(["Computer Science", "Economics", "Physics", "Mathematics", "Business", "Design", "Linguistics"]),
            graduated: randInt(2005, 2024)
        });
    }

    return {
        email: `user${i}+${randInt(100, 999)}@example-${randInt(1, 80)}.test`,
        firstName: pick(["Alex", "Maria", "John", "Olha", "Ivan", "Anna", "Petro", "Kate", "Mike", "Yulia", "Dmytro", "Olena", "Pavlo", "Tetiana"]),
        lastName: pick(["Smith", "Kovalenko", "Shevchenko", "Brown", "Lee", "Petrov", "Müller", "Garcia", "Nowak", "Kuznetsov", "Bondar", "Hrytsenko"]),
        tier,
        status,
        role,
        verified: Math.random() > 0.25,
        createdAt: created,
        updatedAt: updated,
        lastLoginAt: lastLogin,
        trialEndsAt: trialEnds,
        index: i,
        address: {
            country: pick(countries),
            city: pick(cities),
            region: `Region ${randInt(1, 30)}`,
            street: `${randInt(1, 999)} ${pick(["Main", "Maple", "Oak", "Pine", "Khreshchatyk", "Park", "Lake", "Hill"])} ${pick(["St", "Ave", "Blvd", "Rd", "Ln"])}`,
            zip: `${randInt(10000, 99999)}`,
            lat: randFloat(-90, 90, 5),
            lng: randFloat(-180, 180, 5)
        },
        preferences: {
            language: pick(languages),
            theme: pick(themes),
            notifications: {
                email: Math.random() > 0.3,
                push: Math.random() > 0.5,
                sms: Math.random() > 0.7,
                inApp: Math.random() > 0.2,
                digest: pick(["daily", "weekly", "monthly", "never"])
            },
            timezone: pick(["Europe/Kyiv", "Europe/Warsaw", "Europe/Berlin", "Europe/London", "America/New_York", "America/Los_Angeles"]),
            currency: pick(["UAH", "PLN", "EUR", "USD", "GBP"]),
            dateFormat: pick(["YYYY-MM-DD", "DD.MM.YYYY", "MM/DD/YYYY"]),
            twoFactor: Math.random() > 0.4,
            marketing_emails: Math.random() > 0.5
        },
        metrics: {
            logins: randInt(0, 5000),
            purchases: randInt(0, 200),
            refunds: randInt(0, 10),
            avgSessionMinutes: randFloat(1, 90, 1),
            totalSpentUsd: randFloat(0, 12500, 2),
            supportTickets: randInt(0, 40),
            documentsCreated: randInt(0, 1500),
            documentsShared: randInt(0, 300),
            apiCallsLast30d: randInt(0, 50000),
            featureFlagsEnabled: randInt(0, 15)
        },
        tags: pickN(tagPool, randInt(4, 10)),
        recentActivity,
        sessionHistory,
        profile: {
            bio: randomWords(randInt(30, 60)),
            avatarUrl: `https://cdn.example.test/avatars/${i}.png`,
            links: {
                website: `https://example-${randInt(1, 500)}.test`,
                twitter: `https://twitter.com/user${i}`,
                github: `https://github.com/user${i}`,
                linkedin: `https://linkedin.com/in/user${i}`
            },
            experience,
            education,
            skills: pickN(["Swift", "Kotlin", "Python", "Go", "Rust", "TypeScript", "SQL", "MongoDB", "PostgreSQL", "Redis", "Kafka", "React", "Vue", "SwiftUI"], randInt(4, 8))
        },
        subscription: {
            plan: pick(planNames),
            startedAt: created,
            renewsAt: randomDateInFuture(365),
            paymentMethod: pick(["card", "paypal", "wire", "crypto"]),
            currency: pick(["USD", "EUR", "UAH", "GBP"]),
            mrrUsd: randFloat(0, 1200, 2),
            seats: randInt(1, 25),
            autoRenew: Math.random() > 0.2
        },
        notes: randomWords(randInt(150, 220))
    };
}

const coll = db.getSiblingDB(DB_NAME).getCollection(COLL_NAME);

print(`>> dropping ${DB_NAME}.${COLL_NAME} (if exists)`);
coll.drop();

print(`>> seeding ${TOTAL} docs into ${DB_NAME}.${COLL_NAME} in batches of ${BATCH}`);
const t0 = Date.now();
let inserted = 0;
for (let batch = 0; batch < TOTAL / BATCH; batch++) {
    const docs = [];
    const base = batch * BATCH;
    for (let i = 0; i < BATCH; i++) docs.push(makeDoc(base + i));
    coll.insertMany(docs, { ordered: false });
    inserted += docs.length;
    if ((batch + 1) % 10 === 0 || inserted === TOTAL) {
        const elapsed = ((Date.now() - t0) / 1000).toFixed(1);
        print(`  inserted ${inserted} / ${TOTAL}  (${elapsed}s elapsed)`);
    }
}

print(`>> creating indexes`);
coll.createIndex({ email: 1 });
coll.createIndex({ status: 1 });
coll.createIndex({ createdAt: -1 });

const stats = coll.stats();
print(`>> done: count=${coll.countDocuments({})}  size=${(stats.size / 1024 / 1024).toFixed(1)} MB  avgObjSize=${stats.avgObjSize} bytes`);
