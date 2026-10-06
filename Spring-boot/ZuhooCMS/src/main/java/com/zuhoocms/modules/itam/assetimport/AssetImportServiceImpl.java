package com.zuhoocms.modules.itam.assetimport;

import com.zuhoocms.modules.hrm.asset.AssetRequest;
import com.zuhoocms.modules.hrm.asset.AssetService;
import com.zuhoocms.modules.hrm.employee.Employee;
import com.zuhoocms.modules.hrm.employee.EmployeeRepository;
import com.zuhoocms.security.SecurityUtil;
import com.zuhoocms.shared.exception.BadRequestException;
import com.zuhoocms.shared.exception.ForbiddenException;
import com.zuhoocms.shared.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.apache.poi.openxml4j.opc.OPCPackage;
import org.apache.poi.ss.usermodel.DataFormatter;
import org.apache.poi.ss.usermodel.DateUtil;
import org.apache.poi.ss.util.CellReference;
import org.apache.poi.util.XMLHelper;
import org.apache.poi.xssf.eventusermodel.ReadOnlySharedStringsTable;
import org.apache.poi.xssf.eventusermodel.XSSFReader;
import org.apache.poi.xssf.eventusermodel.XSSFSheetXMLHandler;
import org.apache.poi.xssf.model.StylesTable;
import org.apache.poi.xssf.usermodel.XSSFComment;
import org.springframework.stereotype.Service;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.multipart.MultipartFile;
import org.xml.sax.InputSource;
import org.xml.sax.XMLReader;

import java.io.IOException;
import java.io.InputStream;
import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Iterator;
import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
public class AssetImportServiceImpl implements AssetImportService {

    private static final long MAX_FILE_SIZE = 5 * 1024 * 1024; // 5 MB
    private static final int MAX_ROWS = 1000;
    private static final String TOO_MANY_ROWS = "The file must not contain more than " + MAX_ROWS + " rows";

    // Column order matches AssetRequest; "employeeNumber" (not a raw DB id) because whoever fills the CSV has the EMP-0001 style number, not a primary key.
    private static final String[] HEADERS = {
        "name", "category", "serialNumber", "description", "purchaseDate", "purchaseCost",
        "employeeNumber", "assetTag", "brand", "model", "ipAddress", "macAddress",
        "processorModel", "ramSize", "storageSize", "operatingSystem", "warrantyExpiry"
    };

    /** A data row plus its 1-based row number in the file (what the user sees in Excel). */
    private record ParsedRow(int rowNumber, String[] cols) { }

    /** Thrown from inside the SAX callback to stop reading as soon as the row limit is passed. */
    private static final class TooManyRowsException extends RuntimeException {
        TooManyRowsException() { super(TOO_MANY_ROWS, null, false, false); }
    }

    private final AssetService assetService;
    private final EmployeeRepository employeeRepository;
    private final SecurityUtil securityUtil;
    private final TransactionTemplate transactionTemplate;

    @Override
    public String getTemplateCsv() {
        return String.join(",", HEADERS) + "\n";
    }

    @Override
    public byte[] getTemplateXlsx() {
        try (var workbook = new org.apache.poi.xssf.usermodel.XSSFWorkbook();
             var out = new java.io.ByteArrayOutputStream()) {
            var sheet = workbook.createSheet("Assets");
            var header = sheet.createRow(0);
            var bold = workbook.createCellStyle();
            var font = workbook.createFont();
            font.setBold(true);
            bold.setFont(font);
            for (int i = 0; i < HEADERS.length; i++) {
                var cell = header.createCell(i);
                cell.setCellValue(HEADERS[i]);
                cell.setCellStyle(bold);
                sheet.setColumnWidth(i, 18 * 256);
            }
            workbook.write(out);
            return out.toByteArray();
        } catch (IOException e) {
            throw new BadRequestException("Could not generate Excel template");
        }
    }

    @Override
    public AssetImportResultResponse importCsv(MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new BadRequestException("A CSV or Excel (.xlsx) file is required");
        }
        if (file.getSize() > MAX_FILE_SIZE) {
            throw new BadRequestException("File size must be less than 5 MB");
        }

        Long companyId = securityUtil.getCurrentCompanyId();
        if (companyId == null) {
            throw new BadRequestException("No company context");
        }

        List<ParsedRow> rows;
        try {
            rows = isXlsx(file)
                    ? parseXlsx(file)
                    : parseCsv(new String(file.getBytes(), StandardCharsets.UTF_8));
        } catch (IOException e) {
            throw new BadRequestException("Could not read the uploaded file");
        }
        if (!rows.isEmpty()) {
            rows = rows.subList(1, rows.size()); // first non-blank row is the header
        }
        if (rows.size() > MAX_ROWS) {
            throw new BadRequestException(TOO_MANY_ROWS);
        }

        int succeeded = 0;
        List<AssetImportRowError> errors = new ArrayList<>();

        for (ParsedRow row : rows) {
            try {
                // One transaction per row, so a bad row doesn't roll back rows already imported and each row's ASSET_ASSIGNED notification fires on its own commit.
                transactionTemplate.executeWithoutResult(status -> importRow(row.cols(), companyId));
                succeeded++;
            } catch (BadRequestException | ResourceNotFoundException | ForbiddenException
                     | IllegalArgumentException e) {
                // Validation failures carry a message written for the user - show it as-is.
                errors.add(new AssetImportRowError(row.rowNumber(), messageOr(e, "Row import failed")));
            } catch (Exception e) {
                // Anything else is an internal failure: log it, don't leak its details.
                log.warn("Asset import row {} failed unexpectedly: {}", row.rowNumber(), e.toString());
                errors.add(new AssetImportRowError(row.rowNumber(), "Row import failed due to an unexpected error"));
            }
        }

        // Blank lines never reach this list, so succeeded + failed == totalRows.
        return new AssetImportResultResponse(rows.size(), succeeded, errors.size(), errors);
    }

    private static String messageOr(Exception e, String fallback) {
        String msg = e.getMessage();
        return msg == null || msg.isBlank() ? fallback : msg;
    }

    /** Goes through AssetService.create() so imported rows get the same uniqueness checks, employee-assignment rule (with row lock), history row and ASSET_ASSIGNED notification as the manual form. */
    private void importRow(String[] cols, Long companyId) {
        String name = col(cols, 0);
        if (name == null) {
            throw new IllegalArgumentException("name is required");
        }
        maxLength(name, 150, "name");
        maxLength(col(cols, 1), 100, "category");
        maxLength(col(cols, 2), 100, "serialNumber");
        maxLength(col(cols, 7), 100, "assetTag");
        maxLength(col(cols, 8), 100, "brand");
        maxLength(col(cols, 9), 100, "model");

        AssetRequest request = new AssetRequest();
        request.setName(name);
        request.setCategory(col(cols, 1));
        request.setSerialNumber(col(cols, 2));
        request.setDescription(col(cols, 3));
        request.setPurchaseDate(parseDate(col(cols, 4), "purchaseDate"));
        request.setPurchaseCost(parseBigDecimal(col(cols, 5), "purchaseCost"));
        request.setAssetTag(col(cols, 7));
        request.setBrand(col(cols, 8));
        request.setModel(col(cols, 9));
        request.setIpAddress(col(cols, 10));
        request.setMacAddress(col(cols, 11));
        request.setProcessorModel(col(cols, 12));
        request.setRamSize(col(cols, 13));
        request.setStorageSize(col(cols, 14));
        request.setOperatingSystem(col(cols, 15));
        request.setWarrantyExpiry(parseDate(col(cols, 16), "warrantyExpiry"));

        String employeeNumber = col(cols, 6);
        if (employeeNumber != null) {
            Employee employee = employeeRepository.findByCompanyIdAndEmployeeNumber(companyId, employeeNumber)
                    .orElseThrow(() -> new IllegalArgumentException(
                            "employeeNumber " + employeeNumber + " not found (or the employee has left)"));
            request.setAssignedToId(employee.getId());
        }

        assetService.create(request);
    }

    private static void maxLength(String value, int max, String field) {
        if (value != null && value.length() > max) {
            throw new IllegalArgumentException(field + " must be at most " + max + " characters");
        }
    }

    private String col(String[] cols, int index) {
        if (index >= cols.length || cols[index] == null) return null;
        String value = cols[index].trim();
        return value.isEmpty() ? null : value;
    }

    private LocalDate parseDate(String value, String fieldName) {
        if (value == null) return null;
        try {
            return LocalDate.parse(value);
        } catch (DateTimeParseException e) {
            throw new IllegalArgumentException(fieldName + " must be a valid date (YYYY-MM-DD): " + value);
        }
    }

    private BigDecimal parseBigDecimal(String value, String fieldName) {
        if (value == null) return null;
        try {
            return new BigDecimal(value);
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException(fieldName + " must be a number: " + value);
        }
    }

    private boolean isXlsx(MultipartFile file) {
        String name = file.getOriginalFilename();
        if (name != null && name.toLowerCase().endsWith(".xlsx")) return true;
        String type = file.getContentType();
        return type != null && type.contains("spreadsheetml");
    }

    private static boolean isBlank(String[] cols) {
        return Arrays.stream(cols).allMatch(c -> c == null || c.isBlank());
    }

    /**
     * Streams the first sheet with POI's SAX API because a 5 MB .xlsx can expand to hundreds of MB as a DOM, and stops once the row limit is exceeded.
     * Formula cells yield their cached result; dates render ISO (YYYY-MM-DD) and whole numbers without ".0", matching the CSV template.
     */
    private List<ParsedRow> parseXlsx(MultipartFile file) throws IOException {
        RowCollector collector = new RowCollector();
        OPCPackage pkg = null;
        try (InputStream in = file.getInputStream()) {
            pkg = OPCPackage.open(in);
            XSSFReader reader = new XSSFReader(pkg);
            ReadOnlySharedStringsTable strings = new ReadOnlySharedStringsTable(pkg);
            StylesTable styles = reader.getStylesTable();
            Iterator<InputStream> sheets = reader.getSheetsData();
            if (!sheets.hasNext()) {
                throw new BadRequestException("The Excel file has no sheets");
            }
            try (InputStream sheet = sheets.next()) {
                XMLReader parser = XMLHelper.newXMLReader();
                parser.setContentHandler(new XSSFSheetXMLHandler(
                        styles, null, strings, collector, new PlainValueFormatter(), false));
                parser.parse(new InputSource(sheet));
            }
        } catch (TooManyRowsException e) {
            throw new BadRequestException(TOO_MANY_ROWS);
        } catch (BadRequestException e) {
            throw e;
        } catch (Exception e) {
            // SAX wraps exceptions thrown from the handler
            if (e.getCause() instanceof TooManyRowsException) throw new BadRequestException(TOO_MANY_ROWS);
            throw new BadRequestException("Could not read the Excel file - make sure it is a valid .xlsx workbook");
        } finally {
            if (pkg != null) pkg.revert(); // read-only use: discard, never write back
        }
        return collector.rows;
    }

    /** Collects non-blank rows; aborts once more than MAX_ROWS data rows (+1 header) are seen. */
    private static final class RowCollector implements XSSFSheetXMLHandler.SheetContentsHandler {
        final List<ParsedRow> rows = new ArrayList<>();
        private String[] current;
        private int nextCol;

        @Override
        public void startRow(int rowNum) {
            current = new String[HEADERS.length];
            nextCol = 0;
        }

        @Override
        public void endRow(int rowNum) {
            if (current != null && !isBlank(current)) {
                rows.add(new ParsedRow(rowNum + 1, current));
                if (rows.size() > MAX_ROWS + 1) throw new TooManyRowsException();
            }
            current = null;
        }

        @Override
        public void cell(String cellReference, String formattedValue, XSSFComment comment) {
            if (current == null) return;
            int col = cellReference != null ? new CellReference(cellReference).getCol() : nextCol;
            nextCol = col + 1;
            if (col >= current.length) {
                if (col > 255) return; // far outside the template - ignore
                current = Arrays.copyOf(current, col + 1);
            }
            current[col] = formattedValue != null ? formattedValue : "";
        }
    }

    /** Numbers as plain values (no locale/format decoration), date-formatted numbers as ISO dates. */
    private static final class PlainValueFormatter extends DataFormatter {
        @Override
        public String formatRawCellContents(double value, int formatIndex, String formatString, boolean use1904Windowing) {
            if (DateUtil.isADateFormat(formatIndex, formatString) && DateUtil.isValidExcelDate(value)) {
                return DateUtil.getLocalDateTime(value, use1904Windowing).toLocalDate().toString();
            }
            if (!Double.isInfinite(value) && value == Math.rint(value) && Math.abs(value) < 1e15) {
                return String.valueOf((long) value);
            }
            return BigDecimal.valueOf(value).stripTrailingZeros().toPlainString();
        }
    }

    private List<ParsedRow> parseCsv(String content) {
        List<ParsedRow> rows = new ArrayList<>();
        List<String> currentRow = new ArrayList<>();
        StringBuilder current = new StringBuilder();
        boolean inQuotes = false;
        int line = 1;          // physical line the parser is on
        int rowStartLine = 1;  // line the current record started on

        for (int i = 0; i < content.length(); i++) {
            char c = content.charAt(i);
            if (inQuotes) {
                if (c == '"') {
                    if (i + 1 < content.length() && content.charAt(i + 1) == '"') {
                        current.append('"');
                        i++;
                    } else {
                        inQuotes = false;
                    }
                } else {
                    if (c == '\n') line++;
                    current.append(c);
                }
            } else {
                if (c == '"') {
                    inQuotes = true;
                } else if (c == ',') {
                    currentRow.add(current.toString());
                    current.setLength(0);
                } else if (c == '\n') {
                    currentRow.add(current.toString());
                    current.setLength(0);
                    addCsvRow(rows, currentRow, rowStartLine);
                    currentRow = new ArrayList<>();
                    line++;
                    rowStartLine = line;
                } else if (c == '\r') {
                    // ignore carriage return
                } else {
                    current.append(c);
                }
            }
        }
        currentRow.add(current.toString());
        addCsvRow(rows, currentRow, rowStartLine);
        return rows;
    }

    private static void addCsvRow(List<ParsedRow> rows, List<String> fields, int lineNumber) {
        String[] cols = fields.toArray(new String[0]);
        if (cols.length == 0 || isBlank(cols)) return; // blank line: not a row
        rows.add(new ParsedRow(lineNumber, cols));
        if (rows.size() > MAX_ROWS + 1) throw new BadRequestException(TOO_MANY_ROWS);
    }
}
