--[[----------------------------------------------------------------------------
LibRavenExport-1.0
Shared record schema + local SavedVariables persistence for the RavenMark suite.

NO NETWORKING OF ANY KIND. WoW's addon sandbox has no sockets and no HTTP;
"export" means appending structured records to the owning addon's own
SavedVariables table. An external reader parses the SavedVariables .lua file
from disk after logout/reload.

Because LibStub guarantees only the newest loaded copy of this file runs, the
library table itself doubles as the login-session shared state: the current
raidId lives in Export._session, so every module loaded this session agrees on
the same id without needing to communicate directly.

Note: Init takes an explicit source name as its second argument
(Export:Init(RavenMarkRosterDB, "RavenMarkRoster")). The library is a single
shared instance across all five addons, so each addon's SavedVariables table
is registered under its source name and Emit routes each record type to the
addon that owns it.
------------------------------------------------------------------------------]]

local MAJOR, MINOR = "LibRavenExport-1.0", 1
assert(LibStub, MAJOR .. " requires LibStub.")
local Export = LibStub:NewLibrary(MAJOR, MINOR)
if not Export then return end

Export._session  = Export._session  or {}  -- in-memory, per login session (raidId)
Export._registry = Export._registry or {}  -- source name -> SavedVariables table

local SCHEMA_VERSION = 1

-- Which addon owns which record type; Emit routes on this when the caller
-- doesn't pass an explicit source.
local RECORD_SOURCE = {
    roster_snapshot  = "RavenMarkRoster",
    encounter        = "RavenMarkAttendance",
    loot_event       = "RavenMarkLoot",
    bench_assignment = "RavenMarkBench",
    readiness_check  = "RavenMarkReady",
}

---------------------------------------------------------------- helpers -----

local function iso8601()
    return date("!%Y-%m-%dT%H:%M:%SZ")
end

local function sanitizeInstanceName(name)
    name = tostring(name or "unknown"):lower():gsub("[^%w]+", "")
    if name == "" then name = "unknown" end
    return name
end

local function characterRealm()
    local name  = (UnitName and UnitName("player")) or "Unknown"
    local realm = (GetRealmName and GetRealmName()) or "Unknown"
    return name .. "-" .. (realm:gsub("%s+", ""))
end

-------------------------------------------------------------------- API -----

-- Called once per addon at load time. `db` is that addon's SavedVariables
-- table; `source` is the addon name records from it will carry.
function Export:Init(db, source)
    if type(db) ~= "table" or type(source) ~= "string" then return end
    db.schemaVersion = db.schemaVersion or SCHEMA_VERSION
    db.records = db.records or {}
    self._registry[source] = db
end

-- Mint (or return) the raidId shared by every module this login session.
-- Format: ISO8601 mint time + "-" + sanitized current instance name.
function Export:GetOrCreateRaidId()
    if not self._session.raidId then
        local instanceName = GetInstanceInfo and GetInstanceInfo() or nil
        self._session.raidId = iso8601() .. "-" .. sanitizeInstanceName(instanceName)
    end
    return self._session.raidId
end

function Export:GetCurrentRaidId()
    return self._session.raidId
end

-- Wrap `payload` in the shared envelope and append it to the owning addon's
-- records table. Gracefully no-ops (never errors) if that addon never called
-- Init -- load order across five separate addons isn't guaranteed.
function Export:Emit(recordType, payload, source)
    source = source or RECORD_SOURCE[recordType]
    local db = source and self._registry[source]
    if not db or not db.records then return end

    local record = {
        schemaVersion  = SCHEMA_VERSION,
        source         = source,
        recordType     = recordType,
        raidId         = self:GetCurrentRaidId(),
        characterRealm = characterRealm(),
        timestamp      = iso8601(),
        payload        = payload or {},
    }
    db.records[#db.records + 1] = record
    return record
end
