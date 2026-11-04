use std::fs::File;
use std::io::{BufReader, Cursor, Read, Seek};
use std::num::NonZero;

use calamine::{open_workbook, Data, ExcelDateTime, Ods, Range, Reader, Sheets, Xls, Xlsb, Xlsx};
use magnus::{
    function, prelude::*, value::Lazy, Error, ExceptionClass, RArray, RClass, RModule, RString,
    Ruby, Value,
};

// Defined in lib/fast_sheet.rb before this extension loads.
static ERROR: Lazy<ExceptionClass> = Lazy::new(|ruby| {
    ruby.class_object()
        .const_get::<_, RModule>("FastSheet")
        .and_then(|m| m.const_get("Error"))
        .unwrap()
});
// lib/fast_sheet.rb requires "date".
static DATE: Lazy<RClass> = Lazy::new(|ruby| ruby.class_object().const_get("Date").unwrap());

fn error(ruby: &Ruby, msg: impl std::fmt::Display) -> Error {
    Error::new(ruby.get_inner(&ERROR), msg.to_string())
}

// ---------- CSV ----------

fn csv_error(ruby: &Ruby, e: csv::Error) -> Error {
    match e.kind() {
        csv::ErrorKind::Utf8 { .. } => error(
            ruby,
            format!("{e}; pass the file's encoding, for example encoding: \"Big5\""),
        ),
        _ => error(ruby, e),
    }
}

fn yield_csv<R: Read>(ruby: &Ruby, input: R, col_sep: u8) -> Result<(), Error> {
    let mut rdr = csv::ReaderBuilder::new()
        .has_headers(false)
        .flexible(true)
        .delimiter(col_sep)
        .from_reader(input);
    let mut rec = csv::StringRecord::new();
    while rdr.read_record(&mut rec).map_err(|e| csv_error(ruby, e))? {
        let row = ruby.ary_new_capa(rec.len());
        for field in rec.iter() {
            row.push(ruby.str_new(field))?;
        }
        let _: Value = ruby.yield_value(row)?;
    }
    Ok(())
}

// Reads `path`, or `data` (a String already transcoded to UTF-8) when given.
fn each_csv_row(
    ruby: &Ruby,
    path: String,
    data: Option<RString>,
    col_sep: u8,
) -> Result<(), Error> {
    match data {
        // Copied: the block may run Ruby code that changes or frees the String.
        Some(s) => yield_csv(ruby, Cursor::new(unsafe { s.as_slice() }.to_vec()), col_sep),
        None => {
            let file = File::open(&path).map_err(|e| error(ruby, format!("{path}: {e}")))?;
            yield_csv(ruby, BufReader::new(file), col_sep)
        }
    }
}

// ---------- Workbooks (xlsx, xlsm, xlsb, xls, ods) ----------

fn open(ruby: &Ruby, path: &str, format: &str) -> Result<Sheets<BufReader<File>>, Error> {
    let err = |e: &dyn std::fmt::Display| error(ruby, format!("{path}: {e}"));
    Ok(match format {
        "xlsx" | "xlsm" => Sheets::Xlsx(open_workbook::<Xlsx<_>, _>(path).map_err(|e| err(&e))?),
        "xlsb" => Sheets::Xlsb(open_workbook::<Xlsb<_>, _>(path).map_err(|e| err(&e))?),
        "xls" => Sheets::Xls(open_workbook::<Xls<_>, _>(path).map_err(|e| err(&e))?),
        "ods" => Sheets::Ods(open_workbook::<Ods<_>, _>(path).map_err(|e| err(&e))?),
        _ => {
            return Err(Error::new(
                ruby.exception_arg_error(),
                format!("unknown format {format:?}"),
            ))
        }
    })
}

fn sheet_names(ruby: &Ruby, path: String, format: String) -> Result<Vec<String>, Error> {
    Ok(open(ruby, &path, &format)?.sheet_names())
}

fn range<RS: Read + Seek>(
    ruby: &Ruby,
    book: &mut Sheets<RS>,
    index: Option<usize>,
    name: Option<String>,
) -> Result<Range<Data>, Error> {
    let names = book.sheet_names();
    let name = match name {
        Some(name) if names.contains(&name) => name,
        Some(name) => {
            return Err(Error::new(
                ruby.exception_arg_error(),
                format!("no sheet named {name:?} (sheets: {})", names.join(", ")),
            ))
        }
        None => {
            let i = index.unwrap_or(0);
            names.get(i).cloned().ok_or_else(|| {
                Error::new(
                    ruby.exception_index_error(),
                    format!("sheet index {i} outside 0...{}", names.len()),
                )
            })?
        }
    };
    book.worksheet_range(&name).map_err(|e| error(ruby, e))
}

fn date_time(ruby: &Ruby, dt: &ExcelDateTime) -> Result<Value, Error> {
    // Durations ([h]:mm formats) stay the number of days Excel stores.
    if dt.is_duration() {
        return Ok(ruby.float_from_f64(dt.as_f64()).as_value());
    }
    let (y, mo, d, h, mi, s, ms) = dt.to_ymd_hms_milli();
    if (h, mi, s, ms) == (0, 0, 0, 0) {
        return ruby.get_inner(&DATE).funcall("new", (y, mo, d));
    }
    // Excel stores wall-clock time with no zone: read it as local time.
    let sec = if ms == 0 {
        ruby.integer_from_i64(i64::from(s)).as_value()
    } else {
        let num = i64::from(s) * 1000 + i64::from(ms);
        ruby.rational_new(num, NonZero::new(1000).unwrap()).as_value()
    };
    ruby.class_time().funcall("new", (y, mo, d, h, mi, sec))
}

fn cell(ruby: &Ruby, data: &Data) -> Result<Value, Error> {
    Ok(match data {
        Data::Empty => ruby.qnil().as_value(),
        Data::String(s) | Data::DurationIso(s) => ruby.str_new(s).as_value(),
        // ods: "2021-01-01" or "2021-01-01T10:10:10"; kept as text if Ruby can't parse it.
        Data::DateTimeIso(s) => {
            let class = if s.len() == 10 { ruby.get_inner(&DATE) } else { ruby.class_time() };
            class
                .funcall("iso8601", (s.as_str(),))
                .unwrap_or_else(|_| ruby.str_new(s).as_value())
        }
        Data::Int(i) => ruby.integer_from_i64(*i).as_value(),
        // xlsx stores every number as a float: 42 is written "42".
        Data::Float(f) if f.fract() == 0.0 && f.abs() < 9_007_199_254_740_992.0 => {
            ruby.integer_from_i64(*f as i64).as_value()
        }
        Data::Float(f) => ruby.float_from_f64(*f).as_value(),
        Data::Bool(true) => ruby.qtrue().as_value(),
        Data::Bool(false) => ruby.qfalse().as_value(),
        Data::Error(e) => ruby.str_new(&e.to_string()).as_value(),
        Data::DateTime(dt) => date_time(ruby, dt)?,
    })
}

// Yields rows from A1 on: rows above the first used one come as [], and
// cells left of the first used column as nil, so row[0] is always column A.
fn each_workbook_row(
    ruby: &Ruby,
    path: String,
    format: String,
    index: Option<usize>,
    name: Option<String>,
) -> Result<(), Error> {
    let mut book = open(ruby, &path, &format)?;
    // shortcut: worksheet_range loads the whole sheet; switch to
    // worksheet_cells_reader if huge sheets need flat memory.
    let range = range(ruby, &mut book, index, name)?;
    let Some((first_row, first_col)) = range.start() else {
        return Ok(());
    };
    for _ in 0..first_row {
        let _: Value = ruby.yield_value(ruby.ary_new())?;
    }
    for cells in range.rows() {
        let row: RArray = ruby.ary_new_capa(first_col as usize + cells.len());
        for _ in 0..first_col {
            row.push(ruby.qnil())?;
        }
        for data in cells {
            row.push(cell(ruby, data)?)?;
        }
        let _: Value = ruby.yield_value(row)?;
    }
    Ok(())
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let m = ruby.define_module("FastSheet")?;
    m.define_singleton_method("_each_csv_row", function!(each_csv_row, 3))?;
    m.define_singleton_method("_each_workbook_row", function!(each_workbook_row, 4))?;
    m.define_singleton_method("_sheet_names", function!(sheet_names, 2))?;
    Ok(())
}
