//! The vector extension is linked into the engine: an HNSW index is made and
//! searched with nothing installed or loaded at run time.

// Through the harness crate, not `lbug` directly: the harness links the
// extension's archive (build.rs), and a crate the test does not name is left
// out of the link, its native libraries with it.
use lbug_harness::lbug::{Connection, Database, LogicalType, SystemConfig, Value};

fn floats(v: &[f32]) -> Value {
    Value::Array(LogicalType::Float, v.iter().map(|x| Value::Float(*x)).collect())
}

#[test]
fn a_vector_index_is_made_and_searched() {
    let dir = std::env::temp_dir().join(format!("lbug-harness-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    let db = Database::new(&dir, SystemConfig::default().max_db_size(1 << 30)).expect("the database opens");
    let conn = Connection::new(&db).expect("a connection");
    conn.query("CREATE NODE TABLE Chunk(id STRING, emb FLOAT[3], PRIMARY KEY(id));")
        .expect("the table");
    let mut insert = conn
        .prepare("CREATE (:Chunk {id: $id, emb: $emb});")
        .expect("the insert");
    for (id, v) in [("north", [0.0, 1.0, 0.0]), ("east", [1.0, 0.0, 0.0]), ("east-ish", [0.9, 0.1, 0.0])] {
        conn.execute(&mut insert, vec![("id", Value::String(id.into())), ("emb", floats(&v))])
            .expect("a row");
    }
    conn.query("CALL CREATE_VECTOR_INDEX('Chunk', 'chunk_emb', 'emb', metric := 'cosine');")
        .expect("the vector extension makes an index");
    let mut query = conn
        .prepare("CALL QUERY_VECTOR_INDEX('Chunk', 'chunk_emb', $q, 2) RETURN node.id ORDER BY distance;")
        .expect("the search");
    let found: Vec<String> = conn
        .execute(&mut query, vec![("q", floats(&[1.0, 0.0, 0.0]))])
        .expect("the vector extension searches")
        .filter_map(|row| match row.first() {
            Some(Value::String(id)) => Some(id.clone()),
            _ => None,
        })
        .collect();
    drop(conn);
    drop(db);
    let _ = std::fs::remove_dir_all(&dir);
    assert_eq!(found, ["east", "east-ish"]);
}
