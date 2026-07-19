import Foundation
import os.log
import SQLite3

/// Same unsafeBitCast idiom as `VectorStore.sqliteTransient` (that property is
/// private, so we replicate it locally — both resolve to the same SQLITE_TRANSIENT
/// constant: `-1` cast to `sqlite3_destructor_type`).
private let graphSqliteTransient = unsafeBitCast(
    -1 as Int,
    to: sqlite3_destructor_type.self
)

// MARK: - Graph schema + accessors for VectorStore

extension VectorStore {
    // MARK: - Schema bootstrap

    /// Creates the four graph tables if they don't already exist. Must be called
    /// before any graph read/write. `EntityExtractor` calls this on first use.
    func createGraphSchema() {
        guard let db else { return }
        let sql = """
        CREATE TABLE IF NOT EXISTS graph_entities (
            name TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            source_namespaces TEXT NOT NULL DEFAULT '',
            source_item_ids   TEXT NOT NULL DEFAULT ''
        );
        CREATE TABLE IF NOT EXISTS graph_relationships (
            source_name  TEXT NOT NULL,
            target_name  TEXT NOT NULL,
            relationship TEXT NOT NULL,
            source_item_id TEXT NOT NULL,
            PRIMARY KEY(source_name, target_name, source_item_id)
        );
        CREATE INDEX IF NOT EXISTS idx_rel_source ON graph_relationships(source_name);
        CREATE INDEX IF NOT EXISTS idx_rel_target ON graph_relationships(target_name);
        CREATE TABLE IF NOT EXISTS graph_communities (
            id      TEXT PRIMARY KEY,
            level   INTEGER NOT NULL DEFAULT 1,
            title   TEXT NOT NULL,
            summary TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS graph_community_members (
            community_id TEXT NOT NULL,
            entity_name  TEXT NOT NULL,
            PRIMARY KEY(community_id, entity_name)
        );
        CREATE INDEX IF NOT EXISTS idx_cm_entity ON graph_community_members(entity_name);
        """
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            let logger = Logger(subsystem: AppConstants.bundleID, category: "VectorStore+Graph")
            logger.error("Graph schema creation failed: \(msg, privacy: .public)")
            sqlite3_free(errMsg)
        }
    }

    // MARK: - Entity write

    /// Upserts a single entity. Merges namespaces and item IDs with any existing row.
    func upsertEntity(_ entity: GraphEntity) {
        guard let db else { return }

        // Read existing row to merge sets.
        let selectSQL = "SELECT source_namespaces, source_item_ids FROM graph_entities WHERE name = ?"
        var sel: OpaquePointer?
        var existingNS: Set<String> = []
        var existingItems: Set<String> = []
        if sqlite3_prepare_v2(db, selectSQL, -1, &sel, nil) == SQLITE_OK {
            sqlite3_bind_text(sel, 1, entity.name, -1, graphSqliteTransient)
            if sqlite3_step(sel) == SQLITE_ROW {
                if let nsPtr = sqlite3_column_text(sel, 0) {
                    existingNS = decodeSet(String(cString: nsPtr))
                }
                if let idPtr = sqlite3_column_text(sel, 1) {
                    existingItems = decodeSet(String(cString: idPtr))
                }
            }
        }
        sqlite3_finalize(sel)

        let mergedNS = existingNS.union(entity.sourceNamespaces)
        let mergedItems = existingItems.union(entity.sourceItemIDs)

        let upsertSQL = """
        INSERT INTO graph_entities(name, type, source_namespaces, source_item_ids)
        VALUES(?, ?, ?, ?)
        ON CONFLICT(name) DO UPDATE SET
            type = excluded.type,
            source_namespaces = excluded.source_namespaces,
            source_item_ids   = excluded.source_item_ids
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, upsertSQL, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, entity.name, -1, graphSqliteTransient)
        sqlite3_bind_text(stmt, 2, entity.type, -1, graphSqliteTransient)
        let nsStr = encodeSet(mergedNS)
        let itemStr = encodeSet(mergedItems)
        sqlite3_bind_text(stmt, 3, nsStr, -1, graphSqliteTransient)
        sqlite3_bind_text(stmt, 4, itemStr, -1, graphSqliteTransient)
        sqlite3_step(stmt)
    }

    // MARK: - Relationship write

    func upsertRelationship(_ rel: GraphRelationship) {
        guard let db else { return }
        let sql = """
        INSERT OR REPLACE INTO graph_relationships(source_name, target_name, relationship, source_item_id)
        VALUES(?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, rel.sourceName, -1, graphSqliteTransient)
        sqlite3_bind_text(stmt, 2, rel.targetName, -1, graphSqliteTransient)
        sqlite3_bind_text(stmt, 3, rel.relationship, -1, graphSqliteTransient)
        sqlite3_bind_text(stmt, 4, rel.sourceItemID, -1, graphSqliteTransient)
        sqlite3_step(stmt)
    }

    // MARK: - Community write

    func upsertCommunity(_ community: GraphCommunity) {
        guard let db else { return }
        sqlite3_exec(db, "BEGIN TRANSACTION", nil, nil, nil)
        defer { sqlite3_exec(db, "COMMIT", nil, nil, nil) }

        let commSQL = """
        INSERT OR REPLACE INTO graph_communities(id, level, title, summary)
        VALUES(?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, commSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, community.id, -1, graphSqliteTransient)
            sqlite3_bind_int(stmt, 2, Int32(community.level))
            sqlite3_bind_text(stmt, 3, community.title, -1, graphSqliteTransient)
            sqlite3_bind_text(stmt, 4, community.summary, -1, graphSqliteTransient)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)

        // Delete old membership, re-insert.
        var del: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM graph_community_members WHERE community_id = ?", -1, &del, nil) == SQLITE_OK {
            sqlite3_bind_text(del, 1, community.id, -1, graphSqliteTransient)
            sqlite3_step(del)
        }
        sqlite3_finalize(del)

        let memberSQL = "INSERT OR IGNORE INTO graph_community_members(community_id, entity_name) VALUES(?, ?)"
        var mstmt: OpaquePointer?
        if sqlite3_prepare_v2(db, memberSQL, -1, &mstmt, nil) == SQLITE_OK {
            for name in community.memberNames {
                sqlite3_reset(mstmt)
                sqlite3_clear_bindings(mstmt)
                sqlite3_bind_text(mstmt, 1, community.id, -1, graphSqliteTransient)
                sqlite3_bind_text(mstmt, 2, name, -1, graphSqliteTransient)
                sqlite3_step(mstmt)
            }
        }
        sqlite3_finalize(mstmt)
    }

    // MARK: - Entity read

    /// Returns all stored entities (used by `CommunityDetector`).
    func allGraphEntities() -> [GraphEntity] {
        guard let db else { return [] }
        let sql = "SELECT name, type, source_namespaces, source_item_ids FROM graph_entities"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var results: [GraphEntity] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let namePtr = sqlite3_column_text(stmt, 0),
                  let typePtr = sqlite3_column_text(stmt, 1)
            else { continue }
            let name = String(cString: namePtr)
            let type = String(cString: typePtr)
            let ns = sqlite3_column_text(stmt, 2).map { decodeSet(String(cString: $0)) } ?? []
            let items = sqlite3_column_text(stmt, 3).map { decodeSet(String(cString: $0)) } ?? []
            var entity = GraphEntity(
                name: name, type: type,
                namespace: ns.first ?? "", itemID: items.first ?? ""
            )
            entity.sourceNamespaces = ns
            entity.sourceItemIDs = items
            results.append(entity)
        }
        return results
    }

    /// Returns all relationships (used by `CommunityDetector`).
    func allGraphRelationships() -> [GraphRelationship] {
        guard let db else { return [] }
        let sql = "SELECT source_name, target_name, relationship, source_item_id FROM graph_relationships"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var results: [GraphRelationship] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let srcPtr = sqlite3_column_text(stmt, 0),
                  let tgtPtr = sqlite3_column_text(stmt, 1),
                  let relPtr = sqlite3_column_text(stmt, 2),
                  let itemPtr = sqlite3_column_text(stmt, 3)
            else { continue }
            results.append(GraphRelationship(
                sourceName: String(cString: srcPtr),
                targetName: String(cString: tgtPtr),
                relationship: String(cString: relPtr),
                sourceItemID: String(cString: itemPtr)
            ))
        }
        return results
    }

    /// Returns the names of entities that appear in the given item IDs.
    func entityNames(inItemIDs itemIDs: Set<String>) -> [String] {
        guard let db, !itemIDs.isEmpty else { return [] }
        var results: [String] = []
        let sql = "SELECT name, source_item_ids FROM graph_entities"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let namePtr = sqlite3_column_text(stmt, 0),
                  let idsPtr = sqlite3_column_text(stmt, 1)
            else { continue }
            let entityItems = decodeSet(String(cString: idsPtr))
            if !entityItems.isDisjoint(with: itemIDs) {
                results.append(String(cString: namePtr))
            }
        }
        return results
    }

    /// Returns the names of all entities connected to any of the given entity names (1-hop).
    func neighbors(ofEntities names: [String]) -> [String] {
        guard let db, !names.isEmpty else { return [] }
        var results = Set<String>()
        let sql = """
        SELECT target_name FROM graph_relationships WHERE source_name = ?
        UNION
        SELECT source_name FROM graph_relationships WHERE target_name = ?
        """
        for name in names {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, name, -1, graphSqliteTransient)
            sqlite3_bind_text(stmt, 2, name, -1, graphSqliteTransient)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let ptr = sqlite3_column_text(stmt, 0) {
                    results.insert(String(cString: ptr))
                }
            }
        }
        return Array(results).filter { !names.contains($0) }
    }

    /// Returns item IDs associated with the given entity names.
    func itemIDs(forEntityNames names: [String]) -> Set<String> {
        guard let db, !names.isEmpty else { return [] }
        var results = Set<String>()
        let sql = "SELECT source_item_ids FROM graph_entities WHERE name = ?"
        for name in names {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, name, -1, graphSqliteTransient)
            if sqlite3_step(stmt) == SQLITE_ROW,
               let ptr = sqlite3_column_text(stmt, 0)
            {
                results.formUnion(decodeSet(String(cString: ptr)))
            }
        }
        return results
    }

    /// Returns communities that contain any of the given entity names.
    func communities(containingAnyOf names: [String]) -> [GraphCommunity] {
        guard let db, !names.isEmpty else { return [] }
        var communityIDs = Set<String>()
        let memberSQL = "SELECT community_id FROM graph_community_members WHERE entity_name = ?"
        for name in names {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, memberSQL, -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, name, -1, graphSqliteTransient)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let ptr = sqlite3_column_text(stmt, 0) {
                    communityIDs.insert(String(cString: ptr))
                }
            }
        }
        guard !communityIDs.isEmpty else { return [] }

        var communities: [GraphCommunity] = []
        for cid in communityIDs {
            let commSQL = "SELECT level, title, summary FROM graph_communities WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, commSQL, -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, cid, -1, graphSqliteTransient)
            if sqlite3_step(stmt) == SQLITE_ROW,
               let titlePtr = sqlite3_column_text(stmt, 1),
               let summaryPtr = sqlite3_column_text(stmt, 2)
            {
                let level = Int(sqlite3_column_int(stmt, 0))
                let memberSQL2 = "SELECT entity_name FROM graph_community_members WHERE community_id = ?"
                var members: [String] = []
                var mstmt: OpaquePointer?
                if sqlite3_prepare_v2(db, memberSQL2, -1, &mstmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(mstmt, 1, cid, -1, graphSqliteTransient)
                    while sqlite3_step(mstmt) == SQLITE_ROW {
                        if let ptr = sqlite3_column_text(mstmt, 0) {
                            members.append(String(cString: ptr))
                        }
                    }
                }
                sqlite3_finalize(mstmt)
                communities.append(GraphCommunity(
                    id: cid, level: level,
                    title: String(cString: titlePtr),
                    summary: String(cString: summaryPtr),
                    memberNames: members
                ))
            }
        }
        return communities
    }

    // MARK: - Item-scoped chunk fetch (used by GraphRetriever)

    /// Returns the first `limit` chunks stored for (namespace, itemID) — no embedding needed.
    /// Used by the graph retriever to pull neighbour-entity chunks.
    func fetchChunks(namespace: String, itemID: String, limit: Int) -> [VectorHit] {
        guard let db else { return [] }
        let sql = """
        SELECT chunk_idx, chunk_text, metadata FROM vectors
        WHERE namespace = ? AND item_id = ?
        ORDER BY chunk_idx LIMIT ?
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, namespace, -1, graphSqliteTransient)
        sqlite3_bind_text(stmt, 2, itemID, -1, graphSqliteTransient)
        sqlite3_bind_int(stmt, 3, Int32(limit))
        var results: [VectorHit] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let idx = Int(sqlite3_column_int(stmt, 0))
            let text = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
            let metaStr = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            var meta: [String: String]?
            if let metaJSON = metaStr, let data = metaJSON.data(using: .utf8) {
                meta = try? JSONDecoder().decode([String: String].self, from: data)
            }
            results.append(VectorHit(
                namespace: namespace,
                itemID: itemID,
                chunkIdx: idx,
                chunkText: text,
                metadata: meta,
                score: 0.5 // neutral score; graph retriever will re-rank
            ))
        }
        return results
    }

    // MARK: - Helpers

    private func encodeSet(_ set: Set<String>) -> String {
        set.sorted().joined(separator: "|")
    }

    private func decodeSet(_ str: String) -> Set<String> {
        Set(str.split(separator: "|").map(String.init).filter { !$0.isEmpty })
    }
}
