use anyhow::{Context, Result, bail};
use canboat::schema::PacketType;
use canboat::{
    Database, DecodedPgn, FieldValue, Frame, FramePacketType, Reassembled, Reassembler, Units,
};
use flate2::read::GzDecoder;
use std::collections::HashMap;
use std::env;
use std::fs::{self, File};
use std::io::{BufRead, BufReader, BufWriter, Read, Write};
use std::path::{Path, PathBuf};

const PINNED_CANBOAT_RS_REV: &str = "d0f7f24a41b1274f63b71f08703539554523858f";

#[derive(Debug)]
struct Args {
    raw_file: PathBuf,
    log_file_id: i64,
    frames_tsv: PathBuf,
    fields_tsv: PathBuf,
    typed_dir: PathBuf,
    sample_lines: Option<usize>,
}

fn usage() -> &'static str {
    "Usage: n2k-rust-importer --raw-file PATH --log-file-id ID --frames-tsv PATH --fields-tsv PATH --typed-dir DIR [--sample-lines N]\n\
     Emits disposable frame-summary TSV and direct-provenance typed TSV. Research output is currently always empty."
}

fn parse_args() -> Result<Args> {
    let argv: Vec<String> = env::args().skip(1).collect();
    if argv.iter().any(|a| a == "--help" || a == "-h") {
        println!(
            "{}\ncanboat-rs revision: {}",
            usage(),
            PINNED_CANBOAT_RS_REV
        );
        std::process::exit(0);
    }
    let value = |name: &str| -> Result<String> {
        let i = argv
            .iter()
            .position(|a| a == name)
            .with_context(|| format!("missing {name}"))?;
        argv.get(i + 1)
            .cloned()
            .with_context(|| format!("missing value for {name}"))
    };
    Ok(Args {
        raw_file: value("--raw-file")?.into(),
        log_file_id: value("--log-file-id")?
            .parse()
            .context("invalid --log-file-id")?,
        frames_tsv: value("--frames-tsv")?.into(),
        fields_tsv: value("--fields-tsv")?.into(),
        typed_dir: value("--typed-dir")?.into(),
        sample_lines: argv
            .iter()
            .position(|a| a == "--sample-lines")
            .map(|i| {
                argv.get(i + 1)
                    .context("missing --sample-lines value")?
                    .parse()
                    .context("invalid --sample-lines")
            })
            .transpose()?,
    })
}

#[derive(Debug)]
struct CandumpFrame {
    source_line: usize,
    timestamp: String,
    can_id: u32,
    frame: Frame,
}

fn parse_can_id(id: u32) -> (u8, u32, u8, u8) {
    let prio = ((id >> 26) & 0x7) as u8;
    let dp = (id >> 24) & 0x1;
    let pf = (id >> 16) & 0xff;
    let ps = (id >> 8) & 0xff;
    let src = (id & 0xff) as u8;
    let (pgn, dst) = if pf < 240 {
        ((dp << 16) | (pf << 8), ps as u8)
    } else {
        ((dp << 16) | (pf << 8) | ps, 255)
    };
    (prio, pgn, src, dst)
}

fn iso_timestamp(epoch: f64) -> Result<String> {
    if !epoch.is_finite() || epoch < 0.0 {
        bail!("invalid epoch timestamp");
    }
    let epoch_micros = (epoch * 1_000_000.0).round() as i64;
    let secs = epoch_micros.div_euclid(1_000_000);
    let micros = epoch_micros.rem_euclid(1_000_000);
    // Civil date conversion, Howard Hinnant's algorithm.
    let days = secs.div_euclid(86400);
    let sod = secs.rem_euclid(86400);
    let z = days + 719468;
    let era = if z >= 0 { z } else { z - 146096 }.div_euclid(146097);
    let doe = z - era * 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let mut y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = mp + if mp < 10 { 3 } else { -9 };
    y += if m <= 2 { 1 } else { 0 };
    Ok(format!(
        "{y:04}-{m:02}-{d:02}T{:02}:{:02}:{:02}.{:06}Z",
        sod / 3600,
        (sod % 3600) / 60,
        sod % 60,
        micros
    ))
}

fn parse_candump(line: &str, source_line: usize) -> Result<Option<CandumpFrame>> {
    let Some(close) = line.find(')') else {
        return Ok(None);
    };
    if !line.starts_with('(') {
        return Ok(None);
    }
    let epoch: f64 = line[1..close]
        .parse()
        .context("invalid candump timestamp")?;
    let rest = line[close + 1..].trim();
    let mut parts = rest.split_whitespace();
    let _iface = parts.next().context("missing candump interface")?;
    let frame_text = parts.next().context("missing candump frame")?;
    let (id_text, data_text) = frame_text
        .split_once('#')
        .context("missing candump # separator")?;
    let can_id = u32::from_str_radix(id_text, 16).context("invalid CAN id")?;
    if data_text.len() % 2 != 0 {
        bail!("odd CAN payload length");
    }
    let mut data = Vec::with_capacity(data_text.len() / 2);
    for i in (0..data_text.len()).step_by(2) {
        data.push(u8::from_str_radix(&data_text[i..i + 2], 16).context("invalid CAN payload")?);
    }
    let timestamp = iso_timestamp(epoch)?;
    let (prio, pgn, src, dst) = parse_can_id(can_id);
    Ok(Some(CandumpFrame {
        source_line,
        timestamp: timestamp.clone(),
        can_id,
        frame: Frame {
            timestamp: Some(timestamp),
            prio,
            pgn,
            src,
            dst,
            data: data.into_iter().collect(),
        },
    }))
}

fn packet_type(db: &Database, pgn: u32) -> FramePacketType {
    match db.first_pgn(pgn).map(|p| p.packet_type) {
        Some(PacketType::Fast) => FramePacketType::Fast,
        Some(PacketType::Single) => FramePacketType::Single,
        _ => FramePacketType::Other,
    }
}

fn tsv(value: Option<String>) -> String {
    match value {
        None => "\\N".into(),
        Some(v) => v
            .replace('\\', "\\\\")
            .replace('\t', " ")
            .replace(['\r', '\n'], " "),
    }
}
fn n(v: Option<f64>) -> Option<String> {
    v.filter(|x| x.is_finite()).map(|x| x.to_string())
}
fn i(v: Option<i64>) -> Option<String> {
    v.map(|x| x.to_string())
}

fn field<'a>(p: &'a DecodedPgn, names: &[&str]) -> Option<&'a canboat::DecodedField> {
    names.iter().find_map(|name| p.field_by_name(name))
}
fn number(p: &DecodedPgn, names: &[&str]) -> Option<f64> {
    field(p, names).and_then(|f| f.value.as_f64())
}
fn integer(p: &DecodedPgn, names: &[&str]) -> Option<i64> {
    field(p, names).and_then(|f| f.value.as_i64())
}
fn text_value(v: &FieldValue) -> Option<String> {
    match v {
        FieldValue::Lookup { value, name } => Some(
            name.map(str::to_string)
                .unwrap_or_else(|| value.to_string()),
        ),
        FieldValue::String(v) => Some(v.clone()),
        FieldValue::Date(v) => Some(v.to_string()),
        FieldValue::Time { seconds, .. } => Some(seconds.to_string()),
        FieldValue::Mmsi(v) => Some(v.to_string()),
        FieldValue::Pgn { value, description } => Some(
            description
                .map(str::to_string)
                .unwrap_or_else(|| value.to_string()),
        ),
        FieldValue::Integer(v) => Some(v.to_string()),
        FieldValue::Number(v) | FieldValue::Float(v) => Some(v.to_string()),
        _ => None,
    }
}
fn text(p: &DecodedPgn, names: &[&str]) -> Option<String> {
    field(p, names).and_then(|f| text_value(&f.value))
}

struct Outputs {
    dir: PathBuf,
    files: HashMap<&'static str, BufWriter<File>>,
    typed: usize,
}
impl Outputs {
    fn new(dir: PathBuf) -> Result<Self> {
        fs::create_dir_all(&dir)?;
        Ok(Self {
            dir,
            files: HashMap::new(),
            typed: 0,
        })
    }
    fn row(&mut self, file: &'static str, row: Vec<Option<String>>) -> Result<()> {
        if !self.files.contains_key(file) {
            self.files
                .insert(file, BufWriter::new(File::create(self.dir.join(file))?));
        }
        let out = self.files.get_mut(file).unwrap();
        writeln!(
            out,
            "{}",
            row.into_iter().map(tsv).collect::<Vec<_>>().join("\t")
        )?;
        self.typed += 1;
        Ok(())
    }
}

fn base(log_id: i64, line: usize, p: &DecodedPgn, timestamp: &str) -> Vec<Option<String>> {
    vec![
        Some(log_id.to_string()),
        Some(line.to_string()),
        Some(timestamp.into()),
        Some(p.src.to_string()),
    ]
}

fn emit_typed(
    out: &mut Outputs,
    log_id: i64,
    line: usize,
    p: &DecodedPgn,
    timestamp: &str,
) -> Result<bool> {
    let mut r = base(log_id, line, p, timestamp);
    let file = match p.pgn {
        127245 => {
            r.extend([
                i(integer(p, &["Instance"])),
                text(p, &["Direction Order"]),
                n(number(p, &["Angle Order"])),
                n(number(p, &["Position"])),
            ]);
            "n2k_rudder_127245_stage_v2.tsv"
        }
        127250 => {
            r.extend([
                i(integer(p, &["SID"])),
                n(number(p, &["Heading"])),
                n(number(p, &["Deviation"])),
                n(number(p, &["Variation"])),
                text(p, &["Reference"]),
            ]);
            "n2k_heading_127250_stage_v2.tsv"
        }
        128259 => {
            r.extend([
                n(number(p, &["Speed Water Referenced"])),
                n(number(p, &["Speed Ground Referenced"])),
                text(p, &["Speed Water Referenced Type"]),
            ]);
            "n2k_water_speed_128259_stage_v2.tsv"
        }
        128267 => {
            r.extend([
                i(integer(p, &["SID"])),
                n(number(p, &["Depth"])),
                n(number(p, &["Offset"])),
                n(number(p, &["Range"])),
            ]);
            "n2k_water_depth_128267_stage_v2.tsv"
        }
        129025 => {
            r.extend([n(number(p, &["Latitude"])), n(number(p, &["Longitude"]))]);
            "n2k_position_rapid_129025_stage_v2.tsv"
        }
        129026 => {
            r.extend([
                i(integer(p, &["SID"])),
                text(p, &["COG Reference", "Reference"]),
                n(number(p, &["COG"])),
                n(number(p, &["SOG"])),
            ]);
            "n2k_cog_sog_129026_stage_v2.tsv"
        }
        130306 => {
            r.extend([
                i(integer(p, &["SID"])),
                n(number(p, &["Wind Speed"])),
                n(number(p, &["Wind Angle"])),
                text(p, &["Reference"]),
            ]);
            "n2k_wind_130306_stage_v2.tsv"
        }
        _ => return Ok(false),
    };
    out.row(file, r)?;
    Ok(true)
}

fn reader(path: &Path) -> Result<Box<dyn BufRead>> {
    let file = File::open(path).with_context(|| format!("open {}", path.display()))?;
    let input: Box<dyn Read> = if path.extension().is_some_and(|x| x == "gz") {
        Box::new(GzDecoder::new(file))
    } else {
        Box::new(file)
    };
    Ok(Box::new(BufReader::new(input)))
}

fn main() -> Result<()> {
    let args = parse_args()?;
    if args.log_file_id <= 0 {
        bail!("--log-file-id must be positive");
    }
    if let Some(parent) = args.frames_tsv.parent() {
        fs::create_dir_all(parent)?;
    }
    if let Some(parent) = args.fields_tsv.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut frames = BufWriter::new(File::create(&args.frames_tsv)?);
    File::create(&args.fields_tsv)?; // Research remains explicitly empty.
    let mut typed = Outputs::new(args.typed_dir)?;
    let db = Database::embedded(Units::Si);
    let mut reassembler = Reassembler::new();
    let mut first_lines: HashMap<(u32, u8, u8), (usize, String, u32)> = HashMap::new();
    let mut decoded = 0usize;
    let mut malformed = 0usize;

    for (zero, line) in reader(&args.raw_file)?.lines().enumerate() {
        let source_line = zero + 1;
        if args.sample_lines.is_some_and(|limit| source_line > limit) {
            break;
        }
        let line = line?;
        let Some(raw) = (match parse_candump(&line, source_line) {
            Ok(v) => v,
            Err(_) => {
                malformed += 1;
                continue;
            }
        }) else {
            continue;
        };
        let kind = packet_type(db, raw.frame.pgn);
        let fast_key = if kind == FramePacketType::Fast && !raw.frame.data.is_empty() {
            Some((raw.frame.pgn, raw.frame.src, raw.frame.data[0] >> 5))
        } else {
            None
        };
        if let Some(key) = fast_key
            && raw.frame.data[0] & 0x1f == 0
        {
            first_lines.insert(key, (raw.source_line, raw.timestamp.clone(), raw.can_id));
        }
        let event = reassembler.push(raw.frame, kind);
        let frame = match event {
            Reassembled::PassThrough(f) => Some((f, raw.source_line, raw.timestamp, raw.can_id)),
            Reassembled::Complete(f) => {
                let provenance = fast_key.and_then(|k| first_lines.remove(&k)).unwrap_or((
                    raw.source_line,
                    raw.timestamp,
                    raw.can_id,
                ));
                Some((f, provenance.0, provenance.1, provenance.2))
            }
            Reassembled::Partial | Reassembled::Error(_) => None,
        };
        let Some((frame, message_line, timestamp, can_id)) = frame else {
            continue;
        };
        let Ok(pgn) = db.decode(&frame) else { continue };
        writeln!(
            frames,
            "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
            args.log_file_id, message_line, timestamp, pgn.pgn, pgn.src, pgn.dst, pgn.prio, can_id
        )?;
        decoded += 1;
        let _ = emit_typed(&mut typed, args.log_file_id, message_line, &pgn, &timestamp)?;
    }
    frames.flush()?;
    for file in typed.files.values_mut() {
        file.flush()?;
    }
    eprintln!(
        "{{\"decoder\":\"canboat-rs\",\"revision\":\"{}\",\"schema\":\"{}\",\"framesWritten\":{},\"typedWritten\":{},\"researchWritten\":0,\"malformed\":{}}}",
        PINNED_CANBOAT_RS_REV,
        canboat::CANBOAT_VERSION,
        decoded,
        typed.typed,
        malformed
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn parses_extended_can_id() {
        let (prio, pgn, src, dst) = parse_can_id(0x1df80123);
        assert_eq!((prio, pgn, src, dst), (7, 129025, 35, 255));
    }
    #[test]
    fn parses_real_candump_line_with_source_provenance() {
        let f = parse_candump("(1784595590.772000) can0 19F10D0D#00FF7F00FF7FFF7F", 42)
            .unwrap()
            .unwrap();
        assert_eq!(f.source_line, 42);
        assert_eq!(f.frame.pgn, 127245);
        assert_eq!(f.frame.src, 13);
        assert_eq!(f.timestamp, "2026-07-21T00:59:50.772000Z");
    }
}
