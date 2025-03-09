#!/bin/bash

# Default settings
quiet_mode=false

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -q|--quiet)
            quiet_mode=true
            shift
            ;;
        *)
            break
            ;;
    esac
done

# Function to print messages unless in quiet mode
print_msg() {
    if [ "$quiet_mode" = false ]; then
        echo "$@"
    fi
}

# Check if required tools are installed and set flags
have_libreoffice=true
have_pandoc=true
have_ghostscript=true
have_imagemagick=true
have_ffmpeg=true
have_wkhtmltopdf=true
libreoffice_cmd="libreoffice"

# Check for LibreOffice (might be called libreoffice or soffice)
if command -v libreoffice >/dev/null 2>&1; then
    libreoffice_cmd="libreoffice"
elif command -v soffice >/dev/null 2>&1; then
    libreoffice_cmd="soffice"
else
    print_msg "Warning: LibreOffice is not installed. Office documents cannot be converted."
    have_libreoffice=false
fi

if ! command -v pandoc >/dev/null 2>&1; then
    print_msg "Warning: pandoc is not installed. Markdown files cannot be converted."
    have_pandoc=false
fi
if ! command -v gs >/dev/null 2>&1; then
    print_msg "Warning: ghostscript is not installed. PDFs cannot be merged."
    have_ghostscript=false
    # If we can't merge PDFs, we'll just use the first converted PDF as output
fi
if ! command -v convert >/dev/null 2>&1; then
    have_imagemagick=false
fi
if ! command -v ffmpeg >/dev/null 2>&1; then
    have_ffmpeg=false
fi
if ! command -v wkhtmltopdf >/dev/null 2>&1; then
    have_wkhtmltopdf=false
fi

# Check if we have any image conversion tools
have_image_converter=false
if [ "$have_imagemagick" = true ] || [ "$have_ffmpeg" = true ] || [ "$have_libreoffice" = true ]; then
    have_image_converter=true
else
    print_msg "Warning: No image conversion tools found. Images cannot be converted."
fi

# Check if we have any HTML conversion tools
have_html_converter=false
if [ "$have_wkhtmltopdf" = true ] || [ "$have_pandoc" = true ]; then
    have_html_converter=true
else
    print_msg "Warning: No HTML conversion tools found. HTML files cannot be converted."
fi

# Ensure at least two arguments: input files and output file
if [ "$#" -lt 2 ]; then
    print_msg "Usage: $0 [-q|--quiet] input_file1 [input_file2 ...] output.pdf"
    exit 1
fi

# Get the output file (last argument)
output="${!#}"

# Create a temporary directory for intermediate PDFs
tempdir=$(mktemp -d)

# Array to store temporary PDF files
pdfs=()

# Process each input file (all arguments except the last one)
for file in "${@:1:$#-1}"; do
    # Check if file exists
    if [ ! -f "$file" ]; then
        print_msg "Warning: '$file' does not exist, skipping."
        continue
    fi

    # Get file extension (lowercase)
    ext=$(echo "${file##*.}" | tr '[:upper:]' '[:lower:]')
    temp_pdf="$tempdir/$(basename "$file").pdf"

    case "$ext" in
        pdf)
            # Copy existing PDFs directly
            cp "$file" "$temp_pdf"
            if [ $? -eq 0 ]; then
                pdfs+=("$temp_pdf")
            else
                print_msg "Warning: Failed to copy '$file', skipping."
            fi
            ;;
        # Text files
        txt)
            # Try to convert text files with various methods
            converted=false
            
            # Try enscript if available (good for text files)
            if command -v enscript >/dev/null 2>&1 && [ "$converted" = false ]; then
                enscript -p "$tempdir/temp.ps" "$file" >/dev/null 2>&1
                if [ -f "$tempdir/temp.ps" ] && command -v ps2pdf >/dev/null 2>&1; then
                    ps2pdf "$tempdir/temp.ps" "$temp_pdf" >/dev/null 2>&1
                    if [ -f "$temp_pdf" ]; then
                        pdfs+=("$temp_pdf")
                        converted=true
                        print_msg "Converted '$file' with enscript and ps2pdf."
                    fi
                    rm -f "$tempdir/temp.ps"
                fi
            fi
            
            # Try a2ps if available and enscript failed
            if command -v a2ps >/dev/null 2>&1 && [ "$converted" = false ]; then
                a2ps -o "$tempdir/temp.ps" "$file" >/dev/null 2>&1
                if [ -f "$tempdir/temp.ps" ] && command -v ps2pdf >/dev/null 2>&1; then
                    ps2pdf "$tempdir/temp.ps" "$temp_pdf" >/dev/null 2>&1
                    if [ -f "$temp_pdf" ]; then
                        pdfs+=("$temp_pdf")
                        converted=true
                        print_msg "Converted '$file' with a2ps and ps2pdf."
                    fi
                    rm -f "$tempdir/temp.ps"
                fi
            fi
            
            # Fall back to LibreOffice if other methods failed
            if [ "$have_libreoffice" = true ] && [ "$converted" = false ]; then
                $libreoffice_cmd --headless --convert-to pdf "$file" --outdir "$tempdir" >/dev/null 2>&1
                generated_pdf="$tempdir/$(basename "$file" ".$ext").pdf"
                if [ -f "$generated_pdf" ]; then
                    mv "$generated_pdf" "$temp_pdf"
                    pdfs+=("$temp_pdf")
                    converted=true
                    print_msg "Converted '$file' with LibreOffice."
                fi
            fi
            
            if [ "$converted" = false ]; then
                print_msg "Warning: Failed to convert text file '$file' with any available tool, skipping."
            fi
            ;;
            
        # Office documents
        docx|pptx|xlsx|odt|ods|odp|rtf|doc|xls|ppt)
            if [ "$have_libreoffice" = true ]; then
                # Convert office docs with LibreOffice
                $libreoffice_cmd --headless --convert-to pdf "$file" --outdir "$tempdir" >/dev/null 2>&1
                generated_pdf="$tempdir/$(basename "$file" ".$ext").pdf"
                if [ -f "$generated_pdf" ]; then
                    mv "$generated_pdf" "$temp_pdf"
                    pdfs+=("$temp_pdf")
                    print_msg "Converted '$file' with LibreOffice."
                else
                    print_msg "Warning: Failed to convert '$file' with LibreOffice, skipping."
                fi
            else
                print_msg "Skipping '$file': LibreOffice is not installed and required for this file type."
            fi
            ;;
        
        # Images
        png|jpg|jpeg|gif|bmp|tiff|tif|webp|svg|heic|heif|avif|jfif)
            if [ "$have_image_converter" = true ]; then
                converted=false
                
                # Special handling for animated GIFs - extract frames as separate pages
                if [ "$ext" = "gif" ] && [ "$have_imagemagick" = true ]; then
                    # Check if GIF is animated - count frames
                    frame_count=$(identify "$file" | wc -l)
                    if [ "$frame_count" -gt 1 ]; then
                        print_msg "Detected animated GIF with $frame_count frames, extracting each frame as a page."
                        # Create a temporary directory for frames
                        frames_dir="$tempdir/frames"
                        mkdir -p "$frames_dir"
                        
                        # Extract frames
                        convert -coalesce "$file" "$frames_dir/frame-%03d.png" >/dev/null 2>&1
                        
                        # Convert each frame to PDF
                        frame_pdfs=()
                        for frame in "$frames_dir"/frame-*.png; do
                            frame_pdf="$frame.pdf"
                            convert "$frame" "$frame_pdf" >/dev/null 2>&1
                            if [ -f "$frame_pdf" ]; then
                                frame_pdfs+=("$frame_pdf")
                            fi
                        done
                        
                        # Combine all frames into one PDF
                        if [ ${#frame_pdfs[@]} -gt 0 ]; then
                            gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile="$temp_pdf" "${frame_pdfs[@]}" >/dev/null 2>&1
                            if [ -f "$temp_pdf" ]; then
                                pdfs+=("$temp_pdf")
                                converted=true
                                print_msg "Converted animated GIF '$file' with ImageMagick (each frame as a separate page)."
                            fi
                        fi
                        
                        # Clean up
                        rm -rf "$frames_dir"
                        
                        # If we successfully converted the animated GIF, continue to next file
                        if [ "$converted" = true ]; then
                            continue
                        fi
                    fi
                fi
                
                # Standard image conversion with ImageMagick
                if [ "$have_imagemagick" = true ] && [ "$converted" = false ]; then
                    convert "$file" "$temp_pdf" >/dev/null 2>&1
                    if [ -f "$temp_pdf" ]; then
                        pdfs+=("$temp_pdf")
                        converted=true
                        print_msg "Converted '$file' with ImageMagick."
                    fi
                fi
                
                # Try FFmpeg if ImageMagick failed or not available
                if [ "$have_ffmpeg" = true ] && [ "$converted" = false ]; then
                    ffmpeg -i "$file" "$temp_pdf" -y >/dev/null 2>&1
                    if [ -f "$temp_pdf" ]; then
                        pdfs+=("$temp_pdf")
                        converted=true
                        print_msg "Converted '$file' with FFmpeg."
                    fi
                fi
                
                # Try LibreOffice as last resort
                if [ "$have_libreoffice" = true ] && [ "$converted" = false ]; then
                    $libreoffice_cmd --headless --convert-to pdf "$file" --outdir "$tempdir" >/dev/null 2>&1
                    generated_pdf="$tempdir/$(basename "$file" ".$ext").pdf"
                    if [ -f "$generated_pdf" ]; then
                        mv "$generated_pdf" "$temp_pdf"
                        pdfs+=("$temp_pdf")
                        converted=true
                        print_msg "Converted '$file' with LibreOffice."
                    fi
                fi
                
                if [ "$converted" = false ]; then
                    print_msg "Warning: Failed to convert image '$file' with any available tool, skipping."
                fi
            else
                print_msg "Skipping '$file': No image conversion tools are installed."
            fi
            ;;
        # LaTeX files
        tex)
            converted=false
            
            # Try pdflatex if available
            if command -v pdflatex >/dev/null 2>&1 && [ "$converted" = false ]; then
                # Create a temporary directory for LaTeX compilation
                tex_dir="$tempdir/tex"
                mkdir -p "$tex_dir"
                
                # Copy the TeX file to the temporary directory
                cp "$file" "$tex_dir/"
                tex_file="$tex_dir/$(basename "$file")"
                
                # Change to the temporary directory and compile
                current_dir=$(pwd)
                cd "$tex_dir"
                pdflatex -interaction=nonstopmode "$(basename "$tex_file")" >/dev/null 2>&1
                
                # Check if PDF was generated
                generated_pdf="${tex_file%.tex}.pdf"
                if [ -f "$generated_pdf" ]; then
                    cp "$generated_pdf" "$temp_pdf"
                    pdfs+=("$temp_pdf")
                    converted=true
                    print_msg "Converted '$file' with pdflatex."
                fi
                
                # Return to original directory and clean up
                cd "$current_dir"
            fi
            
            # Try xelatex if pdflatex failed or not available
            if command -v xelatex >/dev/null 2>&1 && [ "$converted" = false ]; then
                # Create a temporary directory for LaTeX compilation
                tex_dir="$tempdir/tex"
                mkdir -p "$tex_dir"
                
                # Copy the TeX file to the temporary directory
                cp "$file" "$tex_dir/"
                tex_file="$tex_dir/$(basename "$file")"
                
                # Change to the temporary directory and compile
                current_dir=$(pwd)
                cd "$tex_dir"
                xelatex -interaction=nonstopmode "$(basename "$tex_file")" >/dev/null 2>&1
                
                # Check if PDF was generated
                generated_pdf="${tex_file%.tex}.pdf"
                if [ -f "$generated_pdf" ]; then
                    cp "$generated_pdf" "$temp_pdf"
                    pdfs+=("$temp_pdf")
                    converted=true
                    print_msg "Converted '$file' with xelatex."
                fi
                
                # Return to original directory and clean up
                cd "$current_dir"
            fi
            
            # Try lualatex if both pdflatex and xelatex failed or not available
            if command -v lualatex >/dev/null 2>&1 && [ "$converted" = false ]; then
                # Create a temporary directory for LaTeX compilation
                tex_dir="$tempdir/tex"
                mkdir -p "$tex_dir"
                
                # Copy the TeX file to the temporary directory
                cp "$file" "$tex_dir/"
                tex_file="$tex_dir/$(basename "$file")"
                
                # Change to the temporary directory and compile
                current_dir=$(pwd)
                cd "$tex_dir"
                lualatex -interaction=nonstopmode "$(basename "$tex_file")" >/dev/null 2>&1
                
                # Check if PDF was generated
                generated_pdf="${tex_file%.tex}.pdf"
                if [ -f "$generated_pdf" ]; then
                    cp "$generated_pdf" "$temp_pdf"
                    pdfs+=("$temp_pdf")
                    converted=true
                    print_msg "Converted '$file' with lualatex."
                fi
                
                # Return to original directory and clean up
                cd "$current_dir"
            fi
            
            # Try pandoc as a last resort
            if [ "$have_pandoc" = true ] && [ "$converted" = false ]; then
                pandoc "$file" -o "$temp_pdf" >/dev/null 2>&1
                if [ -f "$temp_pdf" ]; then
                    pdfs+=("$temp_pdf")
                    converted=true
                    print_msg "Converted '$file' with Pandoc."
                fi
            fi
            
            if [ "$converted" = false ]; then
                print_msg "Warning: Failed to convert LaTeX file '$file' with any available tool, skipping."
            fi
            ;;
            
        # Markdown files
        md)
            if [ "$have_pandoc" = true ]; then
                # Convert Markdown files with Pandoc
                pandoc "$file" -o "$temp_pdf" >/dev/null 2>&1
                if [ -f "$temp_pdf" ]; then
                    pdfs+=("$temp_pdf")
                else
                    print_msg "Warning: Failed to convert '$file' with Pandoc, skipping."
                fi
            else
                print_msg "Skipping '$file': Pandoc is not installed."
            fi
            ;;
            
        # HTML files
        html|htm)
            if [ "$have_html_converter" = true ]; then
                converted=false
                
                # Try wkhtmltopdf first if available (best for HTML)
                if [ "$have_wkhtmltopdf" = true ] && [ "$converted" = false ]; then
                    wkhtmltopdf "$file" "$temp_pdf" >/dev/null 2>&1
                    if [ -f "$temp_pdf" ]; then
                        pdfs+=("$temp_pdf")
                        converted=true
                        print_msg "Converted '$file' with wkhtmltopdf."
                    fi
                fi
                
                # Try Pandoc if wkhtmltopdf failed or not available
                if [ "$have_pandoc" = true ] && [ "$converted" = false ]; then
                    pandoc "$file" -o "$temp_pdf" >/dev/null 2>&1
                    if [ -f "$temp_pdf" ]; then
                        pdfs+=("$temp_pdf")
                        converted=true
                        print_msg "Converted '$file' with Pandoc."
                    fi
                fi
                
                if [ "$converted" = false ]; then
                    print_msg "Warning: Failed to convert HTML '$file' with any available tool, skipping."
                fi
            else
                print_msg "Skipping '$file': No HTML conversion tools are installed."
            fi
            ;;
        *)
            print_msg "Warning: Unsupported file type '.$ext' for '$file', skipping."
            continue
            ;;
    esac
done

# Check if any PDFs were generated
if [ ${#pdfs[@]} -eq 0 ]; then
    print_msg "Error: No valid files were converted to PDF."
    rm -rf "$tempdir"
    exit 1
fi

# Handle the output based on available tools and number of PDFs
if [ ${#pdfs[@]} -eq 1 ]; then
    # If there's only one PDF, just copy it to the output
    cp "${pdfs[0]}" "$output"
    if [ $? -ne 0 ]; then
        print_msg "Error: Failed to copy PDF to '$output'."
        rm -rf "$tempdir"
        exit 1
    fi
    print_msg "Only one PDF was generated, copied directly to '$output'."
elif [ "$have_ghostscript" = true ]; then
    # Merge all temporary PDFs into the final output using Ghostscript
    gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -sOutputFile="$output" "${pdfs[@]}" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        print_msg "Error: Failed to merge PDFs into '$output'."
        rm -rf "$tempdir"
        exit 1
    fi
else
    # If Ghostscript is not available, just use the first PDF
    cp "${pdfs[0]}" "$output"
    if [ $? -ne 0 ]; then
        print_msg "Error: Failed to copy PDF to '$output'."
        rm -rf "$tempdir"
        exit 1
    fi
    print_msg "Ghostscript is not installed, only the first PDF was used for '$output'."
fi

# Clean up temporary directory
rm -rf "$tempdir"

print_msg "Successfully created '$output' from ${#pdfs[@]} file(s)."
