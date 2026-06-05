// Notebook Application State
let notebookName = "hello";
let cells = [];
let nextCellId = 1;
let monacoLoaded = false;
let activeEditorDecorations = {}; // Map of cellId -> decorations array

// --- MONACO EDITOR SETUP ---

require.config({ paths: { vs: 'https://cdnjs.cloudflare.com/ajax/libs/monaco-editor/0.39.0/min/vs' } });

require(['vs/editor/editor.main'], function() {
    monacoLoaded = true;
    
    // Register Zig language grammar in Monaco
    monaco.languages.register({ id: 'zig' });
    monaco.languages.setMonarchTokensProvider('zig', {
        keywords: [
            'const', 'var', 'fn', 'pub', 'usingnamespace', 'struct', 'union', 'enum',
            'if', 'else', 'switch', 'while', 'for', 'break', 'continue', 'return',
            'defer', 'errdefer', 'try', 'catch', 'or', 'and', 'noreturn', 'void',
            'bool', 'true', 'false', 'comptime', 'inline', 'align', 'extern', 'export',
            'threadlocal', 'packed', 'linksection', 'noalias', 'volatile', 'allowzero',
            'test', 'asm', 'unreachable', 'anytype', 'anyframe'
        ],
        typeKeywords: [
            'i8', 'u8', 'i16', 'u16', 'i32', 'u32', 'i64', 'u64', 'i128', 'u128', 'isize', 'usize',
            'f16', 'f32', 'f64', 'f80', 'f128', 'bool', 'void', 'noreturn', 'type', 'anyerror',
            '[]const u8', '[]u8'
        ],
        operators: [
            '=', '+', '-', '*', '/', '%', '==', '!=', '<', '>', '<=', '>=',
            '!', '&', '|', '^', '~', '<<', '>>', '+=', '-=', '*=', '/=', '%=',
            '&=', '|=', '^=', '<<=', '>>=', '++', '.*', '.?', '?'
        ],
        symbols:  /[=><!~?:&|+\-*\/\^%]+/,
        escapes: /\\(?:[abfnrtv\\"']|x[0-9A-Fa-f]{2}|u\{[0-9A-Fa-f]{1,6}\})/,
        tokenizer: {
            root: [
                [/[a-zA-Z_][a-zA-Z0-9_]*/, {
                    cases: {
                        '@keywords': 'keyword',
                        '@typeKeywords': 'type',
                        '@default': 'identifier'
                    }
                }],
                { include: '@whitespace' },
                [/[{}()\[\]]/, '@brackets'],
                [/@symbols/, {
                    cases: {
                        '@operators': 'operator',
                        '@default': ''
                    }
                }],
                [/\d*\.\d+([eE][\-+]?\d+)?/, 'number.float'],
                [/0[xX][0-9a-fA-F]+/, 'number.hex'],
                [/\d+/, 'number'],
                [/"([^"\\]|\\.)*$/, 'string.invalid'],
                [/"/,  { token: 'string.quote', bracket: '@open', next: '@string' }],
                [/'[^\\']'/, 'string'],
                [/(')(@escapes)(')/, ['string','string.escape','string']],
                [/'/, 'string.invalid']
            ],
            string: [
                [/[^\\"]+/,  'string'],
                [/@escapes/, 'string.escape'],
                [/\\./,      'string.escape.invalid'],
                [/"/,        { token: 'string.quote', bracket: '@close', next: '@pop' }]
            ],
            whitespace: [
                [/[ \t\r\n]+/, ''],
                [/\/\*/,       'comment', '@comment' ],
                [/\/\/.*$/,    'comment'],
            ],
            comment: [
                [/[^\/*]+/, 'comment' ],
                [/\/\*/,    'comment', '@push' ],
                [/\*\//,    'comment', '@pop'  ],
                [/[\/*]/,   'comment' ]
            ],
        }
    });

    // Custom Obsidian Dark Theme
    monaco.editor.defineTheme('znb-dark', {
        base: 'vs-dark',
        inherit: true,
        rules: [
            { token: 'keyword', foreground: 'c084fc', fontStyle: 'bold' },
            { token: 'type', foreground: '38bdf8' },
            { token: 'comment', foreground: '64748b', fontStyle: 'italic' },
            { token: 'string', foreground: '34d399' },
            { token: 'number', foreground: 'fb923c' },
            { token: 'operator', foreground: 'f43f5e' }
        ],
        colors: {
            'editor.background': '#101014',
            'editor.lineHighlightBackground': '#18181f',
            'editorLineNumber.foreground': '#475569',
            'editorLineNumber.activeForeground': '#cbd5e1',
            'editor.selectionBackground': '#3b0764'
        }
    });

    // Configure marked options
    marked.setOptions({
        gfm: true,
        breaks: true,
        headerIds: false
    });

    // Initial loading sequence
    loadNotebookList().then(() => {
        loadNotebook(notebookName);
    });
});

// --- DOM ELEMENTS ---

const cellsContainer = document.getElementById("cells-container");
const notebookNameInput = document.getElementById("notebook-name");
const saveStatusSpan = document.getElementById("save-status");
const kernelStatusDot = document.querySelector(".status-dot");
const kernelStatusText = document.querySelector(".status-text");
const notebooksListUl = document.getElementById("notebooks-list");

// Toolbar
document.getElementById("btn-save").addEventListener("click", saveNotebook);
document.getElementById("btn-run-all").addEventListener("click", runAllCells);
document.getElementById("btn-restart").addEventListener("click", restartKernel);
document.getElementById("btn-new-notebook").addEventListener("click", createNewNotebook);
notebookNameInput.addEventListener("change", () => {
    updateSaveStatus(false);
});

// Add cells at bottom
document.getElementById("btn-add-code-bottom").addEventListener("click", () => addCell("code"));
document.getElementById("btn-add-markdown-bottom").addEventListener("click", () => addCell("markdown"));

// --- STATE MANAGEMENT & FILE I/O ---

function updateSaveStatus(saved) {
    if (saved) {
        saveStatusSpan.textContent = "Saved";
        saveStatusSpan.style.borderColor = "var(--border-color)";
        saveStatusSpan.style.color = "var(--text-muted)";
    } else {
        saveStatusSpan.textContent = "Unsaved Draft";
        saveStatusSpan.style.borderColor = "rgba(245, 158, 11, 0.3)";
        saveStatusSpan.style.color = "var(--warning)";
    }
}

function setKernelStatus(status) {
    if (status === "busy") {
        kernelStatusDot.className = "status-dot status-busy";
        kernelStatusText.textContent = "Running Zig...";
    } else {
        kernelStatusDot.className = "status-dot status-idle";
        kernelStatusText.textContent = "Idle";
    }
}

async function loadNotebookList() {
    try {
        const response = await fetch("/api/notebooks");
        const data = await response.json();
        notebooksListUl.innerHTML = "";
        
        if (data.notebooks.length === 0) {
            notebooksListUl.innerHTML = `<li class="loading-item">No saved notebooks</li>`;
            return;
        }
        
        data.notebooks.forEach(name => {
            const li = document.createElement("li");
            li.innerHTML = `<i class="fa-regular fa-file-code"></i> ${name}`;
            li.classList.toggle("active", name === notebookName);
            li.addEventListener("click", () => {
                // If current notebook is modified, save it first
                if (saveStatusSpan.textContent === "Unsaved Draft") {
                    if (confirm("You have unsaved changes. Save before switching?")) {
                        saveNotebook().then(() => switchNotebook(name));
                        return;
                    }
                }
                switchNotebook(name);
            });
            notebooksListUl.appendChild(li);
        });
    } catch (err) {
        console.error("Failed to load notebook list", err);
        notebooksListUl.innerHTML = `<li class="loading-item" style="color:var(--error)">Error loading</li>`;
    }
}

function switchNotebook(name) {
    notebookName = name;
    notebookNameInput.value = name;
    // Highlight active list item
    Array.from(notebooksListUl.children).forEach(li => {
        li.classList.toggle("active", li.textContent.trim() === name);
    });
    loadNotebook(name);
}

async function loadNotebook(name) {
    try {
        cellsContainer.innerHTML = `<div class="loading-item" style="padding:40px; text-align:center; font-size:16px;">Loading cells...</div>`;
        const response = await fetch(`/api/notebook/${name}`);
        
        if (response.status === 404) {
            // Create a default notebook template if not found
            createDefaultNotebookTemplate();
            return;
        }
        
        const data = await response.json();
        cellsContainer.innerHTML = "";
        cells = [];
        
        if (data.cells && data.cells.length > 0) {
            data.cells.forEach(c => {
                const cell = addCell(c.type, c.source, false);
                if (c.outputs) {
                    cell.outputs = c.outputs;
                    renderOutputs(cell);
                }
                if (c.execution_count) {
                    cell.executionCount = c.execution_count;
                    const indicator = document.getElementById(`exec-num-${cell.id}`);
                    if (indicator) indicator.textContent = `[${c.execution_count}]`;
                }
            });
        } else {
            addCell("code");
        }
        updateCellNumbers();
        
        updateSaveStatus(true);
    } catch (err) {
        console.error("Error loading notebook content", err);
        cellsContainer.innerHTML = `<div class="loading-item" style="color:var(--error); padding:40px; text-align:center;">Failed to load notebook data</div>`;
    }
}

async function saveNotebook() {
    const serializedCells = cells.map(cell => {
        const source = cell.type === "code" 
            ? cell.editor.getValue() 
            : cell.isEditing ? cell.editor.value : cell.source;
        return {
            id: cell.id,
            type: cell.type,
            source: source,
            execution_count: cell.executionCount,
            outputs: cell.outputs
        };
    });
    
    const name = notebookNameInput.value.trim() || "untitled";
    
    try {
        const response = await fetch("/api/save", {
            method: "POST",
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name: name, cells: serializedCells })
        });
        const data = await response.json();
        if (data.success) {
            notebookName = data.name;
            notebookNameInput.value = data.name;
            updateSaveStatus(true);
            loadNotebookList();
        }
    } catch (err) {
        console.error("Failed to save notebook", err);
        alert("Failed to save notebook");
    }
}

function createNewNotebook() {
    if (saveStatusSpan.textContent === "Unsaved Draft") {
        if (!confirm("Discard unsaved changes?")) return;
    }
    
    notebookName = "untitled_" + Math.floor(Math.random() * 1000);
    notebookNameInput.value = notebookName;
    cellsContainer.innerHTML = "";
    cells = [];
    addCell("code");
    updateSaveStatus(false);
}

function createDefaultNotebookTemplate() {
    cellsContainer.innerHTML = "";
    cells = [];
    
    // Add default cell instructions
    addCell("markdown", `# Getting Started with Zig ZNotebook\n\nWelcome to your cell-based interactive Zig IDE. You can execute code, write math notebooks, document libraries, and output formatted HTML tables or plots.\n\n### Notebook Shortcuts:\n- **Shift + Enter**: Run the active cell.\n- **Double Click** on a Markdown cell to edit it.\n\nTry running the next cell!`);
    
    addCell("code", `const std = @import("std");\n\nstd.debug.print("Hello, ZNotebook!\\n", .{});`);
    
    updateSaveStatus(true);
}

// --- CELL ACTIONS & RENDERING ---

function addCell(type, source = "", append = true) {
    const id = `cell-${nextCellId++}`;
    const cell = {
        id: id,
        type: type,
        source: source,
        outputs: [],
        editor: null,
        isEditing: true,
        executionCount: null
    };
    
    cells.push(cell);
    
    const cellEl = document.createElement("div");
    cellEl.id = id;
    cellEl.className = `cell cell-type-${type}`;
    
    // HTML structure
    cellEl.innerHTML = `
        <div class="cell-header">
            <div class="cell-info">
                <span class="cell-number-label" id="cell-num-label-${id}">Cell</span>
                <span class="execution-indicator" id="exec-num-${id}">[ ]</span>
                <span class="cell-type-badge">${type}</span>
            </div>
            <div class="cell-actions">
                <button class="btn-icon btn-icon-run" onclick="runCell('${id}')" title="Run Cell (Shift+Enter)">
                    <i class="fa-solid fa-play"></i>
                </button>
                <button class="btn-icon" onclick="moveCell('${id}', -1)" title="Move Cell Up">
                    <i class="fa-solid fa-arrow-up"></i>
                </button>
                <button class="btn-icon" onclick="moveCell('${id}', 1)" title="Move Cell Down">
                    <i class="fa-solid fa-arrow-down"></i>
                </button>
                <button class="btn-icon" onclick="deleteCell('${id}')" title="Delete Cell">
                    <i class="fa-solid fa-trash-can"></i>
                </button>
            </div>
        </div>
        <div class="cell-input" id="input-container-${id}">
            <!-- Editor mounts here -->
        </div>
        <div class="cell-output-wrapper" id="output-wrapper-${id}" style="display: none;">
            <!-- Errors and Prints render here -->
        </div>
    `;
    
    if (append) {
        cellsContainer.appendChild(cellEl);
    } else {
        // Find insert spot or append
        cellsContainer.appendChild(cellEl);
    }
    
    const inputContainer = document.getElementById(`input-container-${id}`);
    
    if (type === "code") {
        // Create Monaco editor
        const editorContainer = document.createElement("div");
        editorContainer.className = "monaco-editor-container";
        inputContainer.appendChild(editorContainer);
        
        const editor = monaco.editor.create(editorContainer, {
            value: source,
            language: 'zig',
            theme: 'znb-dark',
            minimap: { enabled: false },
            fontSize: 14,
            fontFamily: "'JetBrains Mono', monospace",
            lineNumbers: "on",
            scrollbar: {
                vertical: 'hidden',
                horizontal: 'auto',
                useShadows: false
            },
            overviewRulerBorder: false,
            hideCursorInOverviewRuler: true,
            scrollBeyondLastLine: false,
            automaticLayout: true
        });
        
        cell.editor = editor;
        
        // Auto-growing cell height
        const updateHeight = () => {
            const contentHeight = Math.max(120, Math.min(1000, editor.getContentHeight()));
            editorContainer.style.height = `${contentHeight}px`;
            editor.layout();
        };
        editor.onDidContentSizeChange(updateHeight);
        editor.onDidChangeModelContent(() => {
            updateSaveStatus(false);
            clearErrorHighlight(cell);
        });
        updateHeight();
        
        // Keybindings (Shift+Enter to run)
        editor.addCommand(monaco.KeyMod.Shift | monaco.KeyCode.Enter, () => {
            runCell(id);
        });
        
    } else {
        // Markdown cell editing textarea vs preview
        const textarea = document.createElement("textarea");
        textarea.className = "markdown-edit-textarea";
        textarea.placeholder = "Write Markdown here. Use Shift+Enter to render.";
        textarea.value = source;
        
        const preview = document.createElement("div");
        preview.className = "markdown-rendered-view";
        preview.style.display = "none";
        
        inputContainer.appendChild(textarea);
        inputContainer.appendChild(preview);
        
        cell.editor = textarea;
        
        textarea.addEventListener("input", () => {
            cell.source = textarea.value;
            updateSaveStatus(false);
        });
        
        textarea.addEventListener("keydown", (e) => {
            if (e.key === "Enter" && e.shiftKey) {
                e.preventDefault();
                runCell(id);
            }
        });
        
        preview.addEventListener("dblclick", () => {
            preview.style.display = "none";
            textarea.style.display = "block";
            textarea.focus();
            cell.isEditing = true;
        });
        
        if (source.trim()) {
            // Render initial content
            preview.innerHTML = marked.parse(source);
            preview.style.display = "block";
            textarea.style.display = "none";
            cell.isEditing = false;
        }
    }
    updateCellNumbers();
    return cell;
}

function deleteCell(id) {
    if (cells.length === 1) {
        alert("Cannot delete the only cell in a notebook!");
        return;
    }
    
    const idx = cells.findIndex(c => c.id === id);
    if (idx !== -1) {
        const cell = cells[idx];
        if (cell.editor && cell.type === "code") {
            cell.editor.dispose();
        }
        cells.splice(idx, 1);
        document.getElementById(id).remove();
        updateCellNumbers();
        updateSaveStatus(false);
    }
}

function moveCell(id, direction) {
    const idx = cells.findIndex(c => c.id === id);
    if (idx === -1) return;
    
    const targetIdx = idx + direction;
    if (targetIdx < 0 || targetIdx >= cells.length) return;
    
    // Swap state
    const temp = cells[idx];
    cells[idx] = cells[targetIdx];
    cells[targetIdx] = temp;
    
    // Swap DOM
    const cellEl = document.getElementById(id);
    const targetEl = document.getElementById(cells[idx].id); // Element now at previous index
    
    if (direction === -1) {
        cellsContainer.insertBefore(cellEl, targetEl);
    } else {
        cellsContainer.insertBefore(targetEl, cellEl);
    }
    updateCellNumbers();
    updateSaveStatus(false);
}

function updateCellNumbers() {
    cells.forEach((cell, index) => {
        const label = document.getElementById(`cell-num-label-${cell.id}`);
        if (label) {
            label.textContent = `Cell ${index + 1}`;
        }
    });
}

// --- CELL RUNNER ---

let executionSequence = 1;

async function runCell(id) {
    const cell = cells.find(c => c.id === id);
    if (!cell) return;
    
    const cellIndex = cells.findIndex(c => c.id === id);
    
    if (cell.type === "markdown") {
        // Markdown cell - just render it
        const textarea = cell.editor;
        const preview = textarea.nextSibling;
        
        cell.source = textarea.value;
        preview.innerHTML = marked.parse(cell.source || "*Empty markdown cell. Double-click to edit.*");
        
        textarea.style.display = "none";
        preview.style.display = "block";
        cell.isEditing = false;
        
        // Mark execution number
        cell.executionCount = executionSequence++;
        document.getElementById(`exec-num-${id}`).textContent = `[${cell.executionCount}]`;
        return;
    }
    
    // Code Cell - compile and run all code cells up to this one
    setKernelStatus("busy");
    const cellEl = document.getElementById(id);
    cellEl.classList.add("active-execution");
    
    // Show spinner in execution indicator
    const execIndicator = document.getElementById(`exec-num-${id}`);
    execIndicator.innerHTML = `<i class="fa-solid fa-spinner fa-spin"></i>`;
    
    // Prepare body
    const runCells = cells.map(c => {
        return {
            id: c.id,
            type: c.type,
            source: c.type === "code" ? c.editor.getValue() : c.source
        };
    });
    
    try {
        const response = await fetch("/api/run", {
            method: "POST",
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                cells: runCells,
                target_index: cellIndex,
                notebook_name: notebookName
            })
        });
        
        const data = await response.json();
        
        cell.executionCount = executionSequence++;
        execIndicator.textContent = `[${cell.executionCount}]`;
        
        // Process results
        cell.outputs = [];
        
        if (!data.success) {
            // Compilation / Runtime error occurred
            if (data.errors && data.errors.length > 0) {
                cell.outputs.push({
                    type: 'error',
                    errors: data.errors
                });
                
                // Draw squiggles in editor
                highlightCompileErrors(data.errors);
            } else {
                // Generic execution crash with output
                cell.outputs.push({
                    type: 'stderr',
                    text: data.stderr || "Process finished with non-zero exit code"
                });
            }
        } else {
            // Successful run, clear error marks
            clearAllErrorHighlights();
            
            if (data.stdout.trim()) {
                cell.outputs.push({
                    type: 'stdout',
                    text: data.stdout
                });
            }
            if (data.stderr.trim()) {
                cell.outputs.push({
                    type: 'stderr',
                    text: data.stderr
                });
            }
        }
        
        renderOutputs(cell);
        updateSaveStatus(false);
        
    } catch (err) {
        console.error("Execution failed", err);
        execIndicator.textContent = `[Err]`;
        cell.outputs = [{
            type: 'stderr',
            text: `Fetch Error: ${err.message}`
        }];
        renderOutputs(cell);
    } finally {
        cellEl.classList.remove("active-execution");
        setKernelStatus("idle");
    }
}

async function runAllCells() {
    for (let cell of cells) {
        await runCell(cell.id);
    }
}

function restartKernel() {
    if (confirm("Restart Kernel? This will clear all code cell outputs.")) {
        cells.forEach(cell => {
            cell.outputs = [];
            cell.executionCount = null;
            
            const indicator = document.getElementById(`exec-num-${cell.id}`);
            if (indicator) indicator.textContent = `[ ]`;
            
            const wrapper = document.getElementById(`output-wrapper-${cell.id}`);
            if (wrapper) {
                wrapper.innerHTML = "";
                wrapper.style.display = "none";
            }
            
            // Clear error markers
            clearErrorHighlight(cell);
        });
        executionSequence = 1;
        updateSaveStatus(false);
    }
}

// --- OUTPUT PARSING & RENDERING ---

function renderOutputs(cell) {
    const wrapper = document.getElementById(`output-wrapper-${cell.id}`);
    wrapper.innerHTML = "";
    
    if (!cell.outputs || cell.outputs.length === 0) {
        wrapper.style.display = "none";
        return;
    }
    
    wrapper.style.display = "flex";
    
    cell.outputs.forEach(out => {
        if (out.type === "error") {
            // Renders standard IDE compile error display
            const errorBox = document.createElement("div");
            errorBox.className = "compile-error-alert";
            
            let html = `<div class="compile-error-title"><i class="fa-solid fa-triangle-exclamation"></i> Zig Compilation Error</div>`;
            out.errors.forEach(err => {
                const cellRef = err.cell_idx !== null ? `Cell ${err.cell_idx + 1}` : `notebook.zig`;
                const lineRef = err.cell_line !== null ? `Line ${err.cell_line}` : `gen line ${err.gen_line}`;
                html += `<div><strong>${cellRef}:${lineRef}:${err.col}</strong> - ${err.message}</div>`;
            });
            errorBox.innerHTML = html;
            wrapper.appendChild(errorBox);
            
        } else if (out.type === "stdout") {
            // Parse stdout line by line for rich contents
            const lines = out.text.split("\n");
            
            let currentConsoleBuffer = [];
            
            const flushConsole = () => {
                if (currentConsoleBuffer.length > 0) {
                    const consoleEl = document.createElement("pre");
                    consoleEl.className = "console-output";
                    consoleEl.textContent = currentConsoleBuffer.join("\n");
                    wrapper.appendChild(consoleEl);
                    currentConsoleBuffer = [];
                }
            };
            
            lines.forEach(line => {
                if (line.startsWith("[ZNB_HTML]")) {
                    flushConsole();
                    const htmlContent = line.replace("[ZNB_HTML]", "");
                    const richBox = document.createElement("div");
                    richBox.className = "rich-output-container";
                    richBox.innerHTML = htmlContent;
                    wrapper.appendChild(richBox);
                } else if (line.startsWith("[ZNB_IMAGE]")) {
                    flushConsole();
                    const base64OrSvg = line.replace("[ZNB_IMAGE]", "").trim();
                    const richBox = document.createElement("div");
                    richBox.className = "rich-output-container";
                    
                    if (base64OrSvg.startsWith("<svg") || base64OrSvg.startsWith("<?xml")) {
                        richBox.innerHTML = base64OrSvg;
                    } else {
                        richBox.innerHTML = `<img src="data:image/png;base64,${base64OrSvg}">`;
                    }
                    wrapper.appendChild(richBox);
                } else if (line.startsWith("[ZNB_MD]")) {
                    flushConsole();
                    const mdContent = line.replace("[ZNB_MD]", "");
                    const richBox = document.createElement("div");
                    richBox.className = "rich-output-container markdown-rendered-view";
                    richBox.innerHTML = marked.parse(mdContent);
                    wrapper.appendChild(richBox);
                } else {
                    currentConsoleBuffer.push(line);
                }
            });
            
            flushConsole();
            
        } else if (out.type === "stderr") {
            const errBox = document.createElement("pre");
            errBox.className = "console-output";
            errBox.style.color = "#fca5a5"; // Soft red for runtime stderr
            errBox.textContent = out.text;
            wrapper.appendChild(errBox);
        }
    });
}

// --- COMPILE ERROR SQUIGGLE HIGHLIGHTS ---

function highlightCompileErrors(errors) {
    clearAllErrorHighlights();
    
    errors.forEach(err => {
        if (err.cell_idx === null || err.cell_line === null) return;
        
        const cell = cells[err.cell_idx];
        if (!cell || cell.type !== "code" || !cell.editor) return;
        
        const line = err.cell_line;
        
        // Set inline error decorations
        const newDecorations = cell.editor.deltaDecorations([], [
            {
                range: new monaco.Range(line, 1, line, 1),
                options: {
                    isWholeLine: true,
                    className: 'compile-error-line',
                    glyphMarginClassName: 'compile-error-glyph',
                    hoverMessage: { value: `Error: ${err.message}` }
                }
            }
        ]);
        
        if (!activeEditorDecorations[cell.id]) {
            activeEditorDecorations[cell.id] = [];
        }
        activeEditorDecorations[cell.id].push(...newDecorations);
    });
}

function clearErrorHighlight(cell) {
    if (cell.editor && activeEditorDecorations[cell.id]) {
        cell.editor.deltaDecorations(activeEditorDecorations[cell.id], []);
        activeEditorDecorations[cell.id] = [];
    }
}

function clearAllErrorHighlights() {
    cells.forEach(cell => {
        clearErrorHighlight(cell);
    });
}
