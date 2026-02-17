let field;
let width, height, mines;
let w, h, m;
let screenshotUrl;

let pasteButton;
let urlInput;
let widthInput;
let heightInput;
let minesInput;
let calcButton;

let grid;

class WASM {
    constructor() {
        this.instance = null;
        this.memory = null;
        this.allocator = null;
    }

    async init() {
        const response = await fetch('./wasm/app.wasm');
        const bytes = await response.arrayBuffer();

        const { instance } = await WebAssembly.instantiate(bytes);
        this.instance = instance;
        this.memory = instance.exports.memory;
        
        this.exports = instance.exports;
        
        console.log("WASM initialized");
    }
    
    writeInput() {
        const wasmPtr = this.exports.inputPtr();
        const len = this.exports.inputLen();
        
        if (field.length != len) {
            throw new Error("Data does not match");
        }

        for (let i = 0; i < field.length; i++) {
            if (field[i] == 11) {
                field[i] = 9;
            }
        }
        
        const wasmArray = new Uint8Array(this.memory.buffer, wasmPtr, len);
        wasmArray.set(field);
    }
    
    readOutput() {
        const wasmPtr = this.exports.probsPtr();
        const len = this.exports.probsLen();
        
        const wasmArray = new Uint8Array(this.memory.buffer, wasmPtr, len);
        return wasmArray.slice();
    }
}

const wasm = new WASM();

const setWidth = (value) => { 
    width = value;
    let parse = Number(value);
    if (Number.isInteger(parse)) {
        w = parse;
    }
    widthInput.value = value;
}
const setHeight = (value) => { 
    height = value;
    let parse = Number(value);
    if (Number.isInteger(parse)) {
        h = parse;
    }
    heightInput.value = value;
}
const setMines = (value) => { 
    mines = value;
    let parse = Number(value);
    if (Number.isInteger(parse)) {
        m = parse;
    }
    minesInput.value = value;
}
const setScreenshotUrl = (value) => {
    screenshotUrl = value;
    urlInput.value = value;
}

document.addEventListener('DOMContentLoaded', async () => {
    pasteButton = document.getElementById('pasteButton');
    urlInput = document.getElementById('urlInput');
    widthInput = document.getElementById('widthInput');
    heightInput = document.getElementById('heightInput');
    minesInput = document.getElementById('minesInput');
    calcButton = document.getElementById('calcButton');

    widthInput.addEventListener('change', (e) => {setWidth(e.target.value)});
    heightInput.addEventListener('change', (e) => {setHeight(e.target.value)});
    minesInput.addEventListener('change', (e) => {setMines(e.target.value)});
    minesInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
            setMines(e.target.value);
            calc();
        }
    });
    urlInput.addEventListener('change', (e) => {setScreenshotUrl(e.target.value)});
    urlInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') {
            setScreenshotUrl(e.target.value);
            processScreenshotFromUrl();
        }
    });

    setWidth("30");
    setHeight("16");
    setMines("99");
    setScreenshotUrl("");

    field = new Uint8Array(w * h);

    widthInput.value = width;
    heightInput.value = height;
    minesInput.value = mines;

    pasteButton.addEventListener('click', processScreenshotFromUrl);
    calcButton.addEventListener('click', calc);

    grid = document.querySelector('.grid');
    grid.addEventListener('contextmenu', (e) => e.preventDefault());
    grid.style.width = 'fit-content';
    drawGrid();

    await wasm.init();
    const res = wasm.exports.initModule(w, h, m);
    if (!res) {
        console.error("Didn't initialized WASM internal probs module");
    } else {
        console.log("Probs module initialized");
    }
});

function convertPixelDataToArray(data, w) {
    const resultArray = [];
    let currentRow = [];

    for (let i = 0; i < data.length; i += 4) {
        currentRow.push([data[i], data[i+1], data[i+2], data[i+3]]);

        if ((i / 4 + 1) % w === 0) {
            resultArray.push(currentRow);
            currentRow = [];
        }
    }

    return resultArray;
}

const CELL_COLORS = {
    OPENED: [198, 198, 198, 255],
    CLOSED: [255, 255, 255, 255],
    FLAG: [100, 100, 100, 255],
    ONE: [0, 0, 247, 255],
    TWO: [0, 119, 0, 255],
    THREE: [236, 0, 0, 255],
    FOUR: [0, 0, 128, 255],
    FIVE: [128, 0, 0, 255],
    SIX: [0, 128, 128, 255],
    SEVEN: [0, 0, 0, 255],
    EIGHT: [112, 112, 112, 255],
};

function extractArray(data2d, w, h) {
    function colorsMatch(pixel, color) {
        return pixel[0] === color[0] &&
               pixel[1] === color[1] &&
               pixel[2] === color[2] &&
               pixel[3] === color[3];
    }

    const board = new Uint8Array(w * h);

    for (let j = 101; j < (h - 1) * 26 + 102; j += 26) {
        for (let i = 33; i < (w - 1) * 26 + 34; i += 26) {
            const col = (i - 33) / 26;
            const row = (j - 101) / 26;
            const pixel = data2d[j][i];

            if (colorsMatch(pixel, CELL_COLORS.OPENED)) {
                if (colorsMatch(data2d[j][i - 13], CELL_COLORS.CLOSED)) {
                    board[row * w + col] = 9;
                }
                else if (colorsMatch(data2d[j - 6][i], CELL_COLORS.SEVEN)) {
                    board[row * w + col] = 7;
                }
                else {
                    board[row * w + col] = 0;
                }
            }
            else if (colorsMatch(pixel, CELL_COLORS.ONE)) {
                board[row * w + col] = 1;
            }
            else if (colorsMatch(pixel, CELL_COLORS.TWO)) {
                board[row * w + col] = 2;
            }
            else if (colorsMatch(pixel, CELL_COLORS.THREE)) {
                board[row * w + col] = 3;
            }
            else if (colorsMatch(pixel, CELL_COLORS.FOUR)) {
                board[row * w + col] = 4;
            }
            else if (colorsMatch(pixel, CELL_COLORS.FIVE)) {
                board[row * w + col] = 5;
            }
            else if (colorsMatch(pixel, CELL_COLORS.SIX)) {
                board[row * w + col] = 6;
            }
            else if (colorsMatch(pixel, CELL_COLORS.EIGHT)) {
                board[row * w + col] = 8;
            }
            else if (colorsMatch(pixel, CELL_COLORS.FLAG)) {
                board[row * w + col] = 11;
            }
        }
    }
    return board;
}

async function processScreenshotFromUrl() {
    if (!screenshotUrl) return;

    try {
        const response = await fetch(screenshotUrl, {mode: "cors"});
        if (!response.ok) return;

        const blob = await response.blob();
        if (!blob.type.startsWith("image/")) return;

        const reader = new FileReader();
        const imageBase64 = await new Promise((resolve) => {
            reader.onload = (e) => {
                if (!e.target || !e.target.result) {
                    throw new Error("Failed to load the image");
                }
                resolve(e.target.result);
            };
            reader.readAsDataURL(blob);
        });

        const img = new Image();
        const imageLoaded = new Promise((resolve) => {
            img.onload = () => resolve(img);
        });
        img.src = imageBase64;
        await imageLoaded;

        const canvas = document.createElement("canvas");
        canvas.width = img.width;
        canvas.height = img.height;
        const ctx = canvas.getContext("2d");
        if (!ctx) {
            throw new Error("Couldn't get canvas context");
        }
        ctx.drawImage(img, 0, 0);
        const pixelData = ctx.getImageData(0, 0, img.width, img.height).data;
        const pixels2d = convertPixelDataToArray(pixelData, img.width);

        const imgWidth = (img.width - 39) / 26;
        const imgHeight = (img.height - 106) / 26;

        const board = extractArray(pixels2d, imgWidth, imgHeight);
        field = board;
        setWidth(imgWidth);
        setHeight(imgHeight);
        setScreenshotUrl("");

        drawGrid();

    } catch (error) {
        console.error(error);
    }
}

function calc() {
    try {
        const fw = wasm.exports.fieldWidth();
        const fh = wasm.exports.fieldHeight();
        const tm = wasm.exports.totalMines();
        if (fw != w || fh != h || tm != m) {
            const res = wasm.exports.resizeModule(w, h, m);
            if (!res) {
                throw new Error("Couldn't resize module");
            }
        }

        wasm.writeInput();

        const res = wasm.exports.probsCalc();
        if (!res) {
            throw new Error("Couldn't calculate result");
        }

        const probs = wasm.readOutput();
        switch (probs.at(0)) {
            case 20:
            case 21:
            case 22:
                throw new Error(`Something went wrong: error code is ${probs.at(0)}`);
        }
        field = probs;
        drawGrid();
    }
    catch (e) {
        console.error(e);
    }
}

function drawGrid() {
    grid.replaceChildren();

    for (let i = 0; i < field.length; i++) {
        const value = field[i];
        let content = "";
        let classname = `cell${value}`;
        let probname = "";
        
        if (value != 0 && value != 9 && value != 11 && value != 12)
        {
            if (value >= 27 && value <= 127){
                content = value - 27;
                classname = "cellprob";
                if (value == 27) {
                    content = "";
                    probname = "zeroprob";
                }
                else if (value == 127) {
                    content = "";
                    probname = "cell12";
                }
                else if (value < 47) {
                    probname = "lowprob";
                }
                else if (value < 93) {
                    probname = "medprob";
                }
                else if (value < 127) {
                    probname = "highprob";
                }
            }
            else {
                content = value;
            }
        }
        const cell = document.createElement("div");
        cell.classList.add("cell");
        const span = document.createElement("span");
        span.classList.add(classname);
        if (probname) span.classList.add(probname);
        span.textContent = content;
        cell.append(span);
        grid.append(cell);
    }
    grid.style.gridTemplateColumns = `repeat(${w}, 25px)`;
}

