# Universal PDF Converter

A command-line tool that converts various file types to PDF and can combine multiple files into a single PDF output.

## Features

- Convert various file types to PDF:
  - Office documents (DOCX, PPTX, XLSX, ODT, DOC, XLS, PPT, RTF, etc.)
  - Images (PNG, JPEG, GIF, BMP, TIFF, WebP, SVG, HEIC, AVIF, etc.)
  - Text files (TXT) with proper formatting
  - LaTeX files (TEX) with proper compilation
  - Markdown files (MD)
  - HTML files with CSS and JavaScript support
  - Existing PDFs
- Special handling for animated GIFs (each frame as a separate page)
- Combine multiple files into a single PDF
- Minimal dependencies with fallbacks
- Graceful handling of missing dependencies
- Detailed error reporting

## Dependencies

The script uses the following tools:

1. **LibreOffice** - For converting office documents
   - The script checks for both `libreoffice` and `soffice` commands (on some systems, LibreOffice is available as `soffice`)
2. **ImageMagick** - Preferred tool for image conversion with special handling for animated GIFs
3. **FFmpeg** - Alternative tool for image conversion
4. **wkhtmltopdf** - Preferred tool for HTML conversion (better rendering of CSS, JavaScript, etc.)
5. **Pandoc** - For converting Markdown files and as a fallback for HTML and LaTeX conversion
6. **Ghostscript** - For merging PDFs
7. **enscript/a2ps** - For better text file conversion (with proper formatting, syntax highlighting)
8. **TeX Live** - For converting LaTeX files (provides pdflatex, xelatex, lualatex)

The script will check for these dependencies and skip file types that require missing tools. It uses a priority system for conversion:

- **Images**: ImageMagick → FFmpeg → LibreOffice
- **HTML**: wkhtmltopdf → Pandoc
- **Text**: enscript → a2ps → LibreOffice
- **LaTeX**: pdflatex → xelatex → lualatex → Pandoc
- **Office Documents**: LibreOffice only
- **Markdown**: Pandoc only

### Installing Dependencies

#### macOS

```bash
# Essential tools
brew install libreoffice pandoc ghostscript

# For better image conversion
brew install imagemagick ffmpeg

# For better HTML conversion
brew install wkhtmltopdf

# For better text file conversion
brew install enscript ghostscript

# For LaTeX file conversion
brew install basictex
```

#### Ubuntu/Debian

```bash
sudo apt update

# Essential tools
sudo apt install libreoffice pandoc ghostscript

# For better image conversion
sudo apt install imagemagick ffmpeg

# For better HTML conversion
sudo apt install wkhtmltopdf

# For better text file conversion
sudo apt install enscript ghostscript a2ps

# For LaTeX file conversion
sudo apt install texlive
```

#### Fedora

```bash
# Essential tools
sudo dnf install libreoffice pandoc ghostscript texlive

# For better image conversion
sudo dnf install imagemagick ffmpeg

# For better HTML conversion
sudo dnf install wkhtmltopdf

# For better text file conversion
sudo dnf install enscript ghostscript a2ps

# For LaTeX file conversion
sudo dnf install texlive
```

#### Windows

For Windows, it's recommended to use WSL (Windows Subsystem for Linux) and follow the Ubuntu/Debian instructions.

Alternatively, you can install these tools directly on Windows:
- [LibreOffice](https://www.libreoffice.org/download/download/)
- [Pandoc](https://pandoc.org/installing.html)
- [Ghostscript](https://ghostscript.com/releases/gsdnld.html)
- [ImageMagick](https://imagemagick.org/script/download.php#windows)
- [MiKTeX](https://miktex.org/download) (for LaTeX)

## Installation

1. Clone or download this repository
2. Make the script executable:

```bash
chmod +x pdf_converter.sh
```

## Usage

The script's behavior is determined by the input arguments:

```bash
./pdf_converter.sh [-q|--quiet] input_file1 [input_file2 ...] output.pdf
```

Options:
- `-q, --quiet`: Suppress all output messages

### Converting a Single File to PDF

To convert a single file to PDF:

```bash
./pdf_converter.sh input_file output.pdf
```

Example:

```bash
./pdf_converter.sh document.docx document.pdf
```

### Converting a Single File Silently (No Output)

To convert a file without any output messages:

```bash
./pdf_converter.sh -q input_file output.pdf
```

Example:

```bash
./pdf_converter.sh --quiet document.docx document.pdf
```

### Converting and Combining Multiple Files

To convert multiple files and combine them into a single PDF:

```bash
./pdf_converter.sh input_file1 input_file2 input_file3 output.pdf
```

Example:

```bash
./pdf_converter.sh document.docx image.png notes.md combined.pdf
```

### Batch Processing Multiple Files Individually

To convert multiple files individually (one input file to one output file), you can use a loop or xargs:

Using a loop:

```bash
# Create output directory if it doesn't exist
mkdir -p output

# Process each file in the current directory with a specific extension
for file in *.docx; do
    ./pdf_converter.sh "$file" "output/${file%.docx}.pdf"
done
```

Using xargs:

```bash
# Create output directory if it doesn't exist
mkdir -p output

# Find all files with specific extensions and process them
find . -name "*.docx" -o -name "*.pptx" | xargs -I{} bash -c './pdf_converter.sh "{}" "output/$(basename "{}" | sed "s/\.[^.]*$/.pdf/")"'
```

### Processing All Files in a Directory Individually (Without Filtering)

To convert all files in a directory to individual PDFs regardless of their extension:

```bash
# Create output directory if it doesn't exist
mkdir -p output

# Process all files in a directory
for file in directory/*; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        ./pdf_converter.sh "$file" "output/${filename%.*}.pdf"
    fi
done
```

For silent processing (useful in scripts):

```bash
# Process all files silently
for file in directory/*; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        ./pdf_converter.sh -q "$file" "output/${filename%.*}.pdf"
    fi
done
```

### Converting All Files in a Directory to a Single PDF

To convert all files in a directory to a single combined PDF:

```bash
# Convert all files in the current directory
./pdf_converter.sh * combined.pdf

# Convert all files with specific extensions
./pdf_converter.sh *.docx *.pptx *.jpg combined.pdf

# Convert all files in a specific directory
./pdf_converter.sh directory/* combined.pdf
```

### Advanced Usage: Sorting Files Before Combining

To ensure files are processed in a specific order:

```bash
# Sort files alphabetically before combining
./pdf_converter.sh $(ls -1 *.pdf | sort) combined.pdf

# Sort files by modification time (oldest first)
./pdf_converter.sh $(ls -1t *.pdf | tac) combined.pdf
```

## Special Features

### Animated GIF Handling

The script provides special handling for animated GIFs:
- Detects if a GIF is animated (has multiple frames)
- Extracts each frame as a separate image
- Converts each frame to a PDF page
- Combines all frames into a single multi-page PDF
- Each frame appears as a separate page in the final PDF

### Text File Formatting

For text files, the script tries multiple conversion methods in this order:
1. **enscript**: Provides nice formatting with page numbers, headers, etc.
2. **a2ps**: Another text-to-PostScript converter with good formatting
3. **LibreOffice**: As a fallback if the above tools are not available

### LaTeX Compilation

For LaTeX files, the script tries multiple compilation methods in this order:
1. **pdflatex**: Standard LaTeX compiler
2. **xelatex**: For better Unicode and font support
3. **lualatex**: For advanced features and better performance
4. **Pandoc**: As a fallback if the above tools are not available

### HTML Conversion

For HTML files, the script prioritizes:
1. **wkhtmltopdf**: Renders HTML with CSS and JavaScript support
2. **Pandoc**: As a fallback if wkhtmltopdf is not available

## Troubleshooting

### Common Issues

1. **"Error: No valid files were converted to PDF"**
   - Check if the input files exist and are of supported types
   - Verify that the required dependencies are installed

2. **"Warning: Failed to convert X with LibreOffice/Pandoc"**
   - Check if the file is corrupted or password-protected
   - Try converting the file manually to see if there are specific errors

3. **Files with spaces in their names**
   - The script handles files with spaces in their names, but when using shell expansion (e.g., `*.docx`), make sure to quote the arguments if needed

4. **LaTeX compilation errors**
   - LaTeX files often require additional packages or resources
   - Try compiling the file manually to see specific errors
   - Make sure all required LaTeX packages are installed

### Debugging

For more detailed output, you can modify the script to remove the `>/dev/null 2>&1` redirections, which will show all command output including errors.
