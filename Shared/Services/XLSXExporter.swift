import Foundation

struct UsageExportRow {
    let start: Date
    let scope: String
    let appIdentifier: String?
    let networkName: String?
    let download: UInt64
    let upload: UInt64
}

enum XLSXExporter {
    static func export(rows: [UsageExportRow], total: AppBytePair, start: Date, end: Date, includeSummary: Bool, destination: URL) throws {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .current
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short

        let dataRows = rows.enumerated().map { index, rowValue in
            let row = index + 2
            let app = rowValue.appIdentifier ?? ""
            let network = rowValue.networkName ?? ""
            return "<row r=\"\(row)\"><c r=\"A\(row)\" t=\"inlineStr\"><is><t>\(xml(dateFormatter.string(from: rowValue.start)))</t></is></c><c r=\"B\(row)\" t=\"inlineStr\"><is><t>\(xml(rowValue.scope))</t></is></c><c r=\"C\(row)\" t=\"inlineStr\"><is><t>\(xml(app))</t></is></c><c r=\"D\(row)\" t=\"inlineStr\"><is><t>\(xml(network))</t></is></c><c r=\"E\(row)\"><v>\(rowValue.download)</v></c><c r=\"F\(row)\"><v>\(rowValue.upload)</v></c><c r=\"G\(row)\"><v>\(rowValue.download + rowValue.upload)</v></c></row>"
        }.joined()

        var appTotals: [String: AppBytePair] = [:]
        for row in rows where row.scope == "app" {
            guard let id = row.appIdentifier else { continue }
            var value = appTotals[id] ?? AppBytePair()
            value.download &+= row.download
            value.upload &+= row.upload
            appTotals[id] = value
        }
        let sortedApps = appTotals.sorted { lhs, rhs in
            let l = lhs.value.download &+ lhs.value.upload
            let r = rhs.value.download &+ rhs.value.upload
            return l == r ? lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending : l > r
        }
        let appSummaryRows = sortedApps.enumerated().map { index, entry in
            let row = index + 10
            return "<row r=\"\(row)\"><c r=\"A\(row)\" t=\"inlineStr\"><is><t>\(xml(entry.key))</t></is></c><c r=\"B\(row)\"><v>\(entry.value.download)</v></c><c r=\"C\(row)\"><v>\(entry.value.upload)</v></c><c r=\"D\(row)\"><v>\(entry.value.download + entry.value.upload)</v></c></row>"
        }.joined()

        let dataSheet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <cols><col min="1" max="1" width="22" customWidth="1"/><col min="2" max="2" width="10" customWidth="1"/><col min="3" max="4" width="30" customWidth="1"/><col min="5" max="7" width="18" customWidth="1"/></cols>
        <sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Time</t></is></c><c r="B1" t="inlineStr"><is><t>Scope</t></is></c><c r="C1" t="inlineStr"><is><t>App identifier</t></is></c><c r="D1" t="inlineStr"><is><t>Network</t></is></c><c r="E1" t="inlineStr"><is><t>Download bytes</t></is></c><c r="F1" t="inlineStr"><is><t>Upload bytes</t></is></c><c r="G1" t="inlineStr"><is><t>Total bytes</t></is></c></row>\(dataRows)</sheetData>
        </worksheet>
        """

        let summarySheet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>
        <row r="1"><c r="A1" t="inlineStr"><is><t>NeManeem Usage Summary</t></is></c></row>
        <row r="2"><c r="A2" t="inlineStr"><is><t>Start</t></is></c><c r="B2" t="inlineStr"><is><t>\(xml(dateFormatter.string(from: start)))</t></is></c></row>
        <row r="3"><c r="A3" t="inlineStr"><is><t>End</t></is></c><c r="B3" t="inlineStr"><is><t>\(xml(dateFormatter.string(from: end)))</t></is></c></row>
        <row r="5"><c r="A5" t="inlineStr"><is><t>Download bytes</t></is></c><c r="B5"><v>\(total.download)</v></c></row>
        <row r="6"><c r="A6" t="inlineStr"><is><t>Upload bytes</t></is></c><c r="B6"><v>\(total.upload)</v></c></row>
        <row r="7"><c r="A7" t="inlineStr"><is><t>Total bytes</t></is></c><c r="B7"><v>\(total.download + total.upload)</v></c></row>
        <row r="9"><c r="A9" t="inlineStr"><is><t>App identifier</t></is></c><c r="B9" t="inlineStr"><is><t>Download bytes</t></is></c><c r="C9" t="inlineStr"><is><t>Upload bytes</t></is></c><c r="D9" t="inlineStr"><is><t>Total bytes</t></is></c></row>
        \(appSummaryRows)
        </sheetData></worksheet>
        """

        let sheetDeclarations = includeSummary
            ? #"<sheet name="Summary" sheetId="1" r:id="rId1"/><sheet name="Data" sheetId="2" r:id="rId2"/>"#
            : #"<sheet name="Data" sheetId="1" r:id="rId1"/>"#
        let workbookRels = includeSummary
            ? #"<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/><Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>"#
            : #"<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>"#
        let overrides = includeSummary
            ? #"<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#
            : #"<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#

        var files: [(String, Data)] = [
            ("[Content_Types].xml", data("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>\(overrides)<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/></Types>")),
            ("_rels/.rels", data(#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>"#)),
            ("xl/workbook.xml", data("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets>\(sheetDeclarations)</sheets></workbook>")),
            ("xl/_rels/workbook.xml.rels", data("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">\(workbookRels)</Relationships>")),
            ("xl/styles.xml", data(#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font><sz val="11"/><name val="Aptos"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>"#))
        ]
        if includeSummary {
            files.append(("xl/worksheets/sheet1.xml", data(summarySheet)))
            files.append(("xl/worksheets/sheet2.xml", data(dataSheet)))
        } else {
            files.append(("xl/worksheets/sheet1.xml", data(dataSheet)))
        }
        try StoredZipWriter.write(files: files, to: destination)
    }



    static func exportCSVBundle(rows: [UsageExportRow], total: AppBytePair, start: Date, end: Date, destination: URL) throws {
        let iso = ISO8601DateFormatter()

        var dataCSV = "timestamp,scope,app_identifier,network,download_bytes,upload_bytes,total_bytes\n"
        for row in rows {
            let fields = [iso.string(from: row.start), row.scope, row.appIdentifier ?? "", row.networkName ?? ""]
                .map(csvField).joined(separator: ",")
            dataCSV += "\(fields),\(row.download),\(row.upload),\(row.download + row.upload)\n"
        }

        var appTotals: [String: AppBytePair] = [:]
        for row in rows where row.scope == "app" {
            guard let id = row.appIdentifier else { continue }
            var value = appTotals[id] ?? AppBytePair()
            value.download &+= row.download
            value.upload &+= row.upload
            appTotals[id] = value
        }

        var summaryCSV = "item,value,download_bytes,upload_bytes,total_bytes\n"
        summaryCSV += "start,\(csvField(iso.string(from: start))),,,\n"
        summaryCSV += "end,\(csvField(iso.string(from: end))),,,\n"
        summaryCSV += "overall,,\(total.download),\(total.upload),\(total.download + total.upload)\n"
        summaryCSV += "\napp_identifier,,download_bytes,upload_bytes,total_bytes\n"
        for entry in appTotals.sorted(by: {
            let lhs = $0.value.download &+ $0.value.upload
            let rhs = $1.value.download &+ $1.value.upload
            return lhs == rhs ? $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending : lhs > rhs
        }) {
            summaryCSV += "\(csvField(entry.key)),,\(entry.value.download),\(entry.value.upload),\(entry.value.download + entry.value.upload)\n"
        }

        try StoredZipWriter.write(files: [
            ("summary.csv", Data(summaryCSV.utf8)),
            ("usage-records.csv", Data(dataCSV.utf8))
        ], to: destination)
    }

    private static func csvField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    static func exportDataUsageRecords(records: [DataUsageRecord], destination: URL) throws {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = .current
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short

        let rows = records.enumerated().map { index, record in
            let row = index + 2
            let percent = record.limitBytes > 0 ? (Double(record.total) / Double(record.limitBytes)) * 100.0 : 0
            let reached = record.limitBytes > 0 && record.total >= record.limitBytes ? "true" : "false"
            return "<row r=\"\(row)\">" +
                "<c r=\"A\(row)\" t=\"inlineStr\"><is><t>\(xml(dateFormatter.string(from: record.start)))</t></is></c>" +
                "<c r=\"B\(row)\" t=\"inlineStr\"><is><t>\(xml(dateFormatter.string(from: record.end)))</t></is></c>" +
                "<c r=\"C\(row)\"><v>\(record.download)</v></c>" +
                "<c r=\"D\(row)\"><v>\(record.upload)</v></c>" +
                "<c r=\"E\(row)\"><v>\(record.total)</v></c>" +
                "<c r=\"F\(row)\"><v>\(record.limitBytes)</v></c>" +
                "<c r=\"G\(row)\"><v>\(String(format: "%.2f", percent))</v></c>" +
                "<c r=\"H\(row)\" t=\"inlineStr\"><is><t>\(xml(record.networkDisplayName ?? ""))</t></is></c>" +
                "<c r=\"I\(row)\" t=\"inlineStr\"><is><t>\(xml(record.label ?? ""))</t></is></c>" +
                "<c r=\"J\(row)\" t=\"inlineStr\"><is><t>\(reached)</t></is></c></row>"
        }.joined()

        let sheet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <cols><col min="1" max="2" width="22" customWidth="1"/><col min="3" max="7" width="18" customWidth="1"/><col min="8" max="9" width="26" customWidth="1"/><col min="10" max="10" width="14" customWidth="1"/></cols>
        <sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Start</t></is></c><c r="B1" t="inlineStr"><is><t>End</t></is></c><c r="C1" t="inlineStr"><is><t>Download bytes</t></is></c><c r="D1" t="inlineStr"><is><t>Upload bytes</t></is></c><c r="E1" t="inlineStr"><is><t>Total bytes</t></is></c><c r="F1" t="inlineStr"><is><t>Limit bytes</t></is></c><c r="G1" t="inlineStr"><is><t>Usage percent</t></is></c><c r="H1" t="inlineStr"><is><t>Network</t></is></c><c r="I1" t="inlineStr"><is><t>Label</t></is></c><c r="J1" t="inlineStr"><is><t>Limit reached</t></is></c></row>\(rows)</sheetData>
        </worksheet>
        """

        let files: [(String, Data)] = [
            ("[Content_Types].xml", data(#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>"#)),
            ("_rels/.rels", data(#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>"#)),
            ("xl/workbook.xml", data(#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Data usage records" sheetId="1" r:id="rId1"/></sheets></workbook>"#)),
            ("xl/_rels/workbook.xml.rels", data(#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>"#)),
            ("xl/styles.xml", data(#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font><sz val="11"/><name val="Aptos"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>"#)),
            ("xl/worksheets/sheet1.xml", data(sheet))
        ]
        try StoredZipWriter.write(files: files, to: destination)
    }

    static func exportSessionRecords(records: [UsageSessionRecord], destination: URL) throws {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        let rows = records.enumerated().map { index, record in
            let row = index + 2
            let name = xml(record.name ?? "")
            let duration = String(format: "%.3f", record.duration)
            return "<row r=\"\(row)\">" +
                "<c r=\"A\(row)\" t=\"inlineStr\"><is><t>\(name)</t></is></c>" +
                "<c r=\"B\(row)\" t=\"inlineStr\"><is><t>\(xml(formatter.string(from: record.start)))</t></is></c>" +
                "<c r=\"C\(row)\" t=\"inlineStr\"><is><t>\(xml(formatter.string(from: record.end)))</t></is></c>" +
                "<c r=\"D\(row)\"><v>\(duration)</v></c>" +
                "<c r=\"E\(row)\"><v>\(record.download)</v></c>" +
                "<c r=\"F\(row)\"><v>\(record.upload)</v></c>" +
                "<c r=\"G\(row)\"><v>\(record.total)</v></c></row>"
        }.joined()
        let sheet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <cols><col min="1" max="3" width="24" customWidth="1"/><col min="4" max="7" width="18" customWidth="1"/></cols>
        <sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Name</t></is></c><c r="B1" t="inlineStr"><is><t>Start</t></is></c><c r="C1" t="inlineStr"><is><t>End</t></is></c><c r="D1" t="inlineStr"><is><t>Duration seconds</t></is></c><c r="E1" t="inlineStr"><is><t>Download bytes</t></is></c><c r="F1" t="inlineStr"><is><t>Upload bytes</t></is></c><c r="G1" t="inlineStr"><is><t>Total bytes</t></is></c></row>\(rows)</sheetData>
        </worksheet>
        """
        let files: [(String, Data)] = [
            ("[Content_Types].xml", data(#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>"#)),
            ("_rels/.rels", data(#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>"#)),
            ("xl/workbook.xml", data(#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Session records" sheetId="1" r:id="rId1"/></sheets></workbook>"#)),
            ("xl/_rels/workbook.xml.rels", data(#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>"#)),
            ("xl/styles.xml", data(#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="1"><font><sz val="11"/><name val="Aptos"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>"#)),
            ("xl/worksheets/sheet1.xml", data(sheet))
        ]
        try StoredZipWriter.write(files: files, to: destination)
    }

    private static func data(_ string: String) -> Data { Data(string.utf8) }
    private static func xml(_ string: String) -> String {
        string.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private enum StoredZipWriter {
    private struct Entry { let name: Data; let data: Data; let crc: UInt32; let offset: UInt32 }

    static func write(files: [(String, Data)], to url: URL) throws {
        var output = Data()
        var entries: [Entry] = []
        for (nameString, payload) in files {
            let name = Data(nameString.utf8)
            let crc = CRC32.checksum(payload)
            let offset = UInt32(output.count)
            output.appendLE(UInt32(0x04034b50)); output.appendLE(UInt16(20)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(crc); output.appendLE(UInt32(payload.count)); output.appendLE(UInt32(payload.count)); output.appendLE(UInt16(name.count)); output.appendLE(UInt16(0)); output.append(name); output.append(payload)
            entries.append(Entry(name: name, data: payload, crc: crc, offset: offset))
        }
        let centralOffset = UInt32(output.count)
        for e in entries {
            output.appendLE(UInt32(0x02014b50)); output.appendLE(UInt16(20)); output.appendLE(UInt16(20)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(e.crc); output.appendLE(UInt32(e.data.count)); output.appendLE(UInt32(e.data.count)); output.appendLE(UInt16(e.name.count)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt32(0)); output.appendLE(e.offset); output.append(e.name)
        }
        let centralSize = UInt32(output.count) - centralOffset
        output.appendLE(UInt32(0x06054b50)); output.appendLE(UInt16(0)); output.appendLE(UInt16(0)); output.appendLE(UInt16(entries.count)); output.appendLE(UInt16(entries.count)); output.appendLE(centralSize); output.appendLE(centralOffset); output.appendLE(UInt16(0))
        try output.write(to: url, options: .atomic)
    }
}

private enum CRC32 {
    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            var x = (crc ^ UInt32(byte)) & 0xFF
            for _ in 0..<8 { x = (x & 1) != 0 ? (x >> 1) ^ 0xEDB88320 : x >> 1 }
            crc = (crc >> 8) ^ x
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) { var v = value.littleEndian; Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) } }
    mutating func appendLE(_ value: UInt32) { var v = value.littleEndian; Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) } }
}
