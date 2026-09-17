import { ObjectDetector, FilesetResolver } from '@mediapipe/tasks-vision';

const statusElement = document.querySelector('#status');
const browserStatusElement = document.querySelector('#browser-status');
const applicationStatusElement = document.querySelector('#application-status');
const modelStatusElement = document.querySelector('#model-status');

const imageWrapperElement = document.querySelector('#image-wrapper');
const imageInputElement = document.querySelector('#image-input');
const testImageElement = document.querySelector('#test-image');
const canvasElement = document.querySelector('#output-canvas');
const runButton = document.querySelector('#run-btn');
const outputBoxElement = document.querySelector('#output-box');

// Application State
let objectDetector = null;
let currentObjectUrl = null;
let imageReady = false;

// Helper to generate a consistent HSL color based on string hash
function getLabelColor(label) {
  let hash = 0;
  for (let i = 0; i < label.length; i++) {
    hash = label.charCodeAt(i) + ((hash << 5) - hash);
  }
  const hue = Math.abs(hash % 360);
  return `hsl(${hue}, 85%, 45%)`;
}

function setStatus(message) {
  statusElement.textContent = message;
}

function checkBrowser() {
  browserStatusElement.textContent = `${navigator.userAgent}`;
  return true;
}

function resetImageSelection() {
  if (currentObjectUrl) {
    URL.revokeObjectURL(currentObjectUrl);
    currentObjectUrl = null;
  }
  imageReady = false;

  // Hide container, leave testImageElement display rules alone
  if (imageWrapperElement) {
    imageWrapperElement.style.display = 'none';
  }
  testImageElement.src = '';

  // Reset canvas
  const ctx = canvasElement.getContext('2d');
  ctx.clearRect(0, 0, canvasElement.width, canvasElement.height);

  outputBoxElement.textContent = 'Awaiting inference execution...';
  updateRunButtonState();
}

function handleImageSelection(event) {
  const file = event.target.files[0];
  if (!file) return;

  // Enforce JPG/JPEG validation in JS
  const validTypes = ['image/jpeg', 'image/jpg'];
  const hasJpgExtension = /\.(jpe?g)$/i.test(file.name);

  if (!validTypes.includes(file.type) && !hasJpgExtension) {
    alert('Please select a valid .jpg or .jpeg image.');
    event.target.value = '';
    resetImageSelection();
    return;
  }

  loadSelectedImage(file);
}

function loadSelectedImage(file) {
  resetImageSelection();

  currentObjectUrl = URL.createObjectURL(file);
  testImageElement.src = currentObjectUrl;

  testImageElement.onload = () => {
    imageReady = true;

    // Match internal canvas buffer resolution to raw image resolution
    canvasElement.width = testImageElement.naturalWidth;
    canvasElement.height = testImageElement.naturalHeight;

    imageWrapperElement.style.display = 'block';
    updateRunButtonState();
  };

  testImageElement.onerror = () => {
    resetImageSelection();
    outputBoxElement.textContent = 'Failed to load selected image.';
  };
}

function updateRunButtonState() {
  runButton.disabled = !(objectDetector && imageReady);
}

async function startApplication() {
  applicationStatusElement.textContent = 'Initializing MediaPipe Vision WASM...';
  setStatus('Loading runtime...');

  try {
    // 1. Resolve WASM assets served from /wasm/
    const vision = await FilesetResolver.forVisionTasks('/wasm'); // No slash at the end; Would break file system
    applicationStatusElement.textContent = 'MediaPipe WASM initialized.';

    // 2. Load and compile the model file directly
    modelStatusElement.textContent = 'Fetching and compiling model.tflite...';

    // objectDetector is a global variable from the state machine
    objectDetector = await ObjectDetector.createFromOptions(vision, {
      baseOptions: {
        modelAssetPath: '/models/model.tflite',
        delegate: 'CPU' // Or 'GPU'
      },
      scoreThreshold: 0.35,
      runningMode: 'IMAGE'
    });

    modelStatusElement.textContent = 'Model loaded and compiled successfully!';
    setStatus('Application started successfully.');

    // Save instance to state and bind listeners
    imageInputElement.addEventListener('change', handleImageSelection);
    runButton.addEventListener('click', () => runInference(objectDetector));
    updateRunButtonState();

    console.log('ObjectDetector ready:', objectDetector);
    return objectDetector;
  } catch (error) {
    console.error('Failed to initialize MediaPipe ObjectDetector:', error);
    setStatus(`Error: ${error.message}`);
    modelStatusElement.textContent = 'Failed to load/compile.';
  }
}

function runInference(detector) {
  if (!imageReady) {
    outputBoxElement.textContent = 'No valid image loaded, please select an image...';
    return;
  }

  outputBoxElement.textContent = 'Running inference...';

  // Execute inference on the image element
  const detectionResult = detector.detect(testImageElement);
  console.log('Detection Output:', detectionResult);

  // Canvas operations
  const ctx = canvasElement.getContext('2d');
  // Clear any previous render
  ctx.clearRect(0, 0, canvasElement.width, canvasElement.height);

  if (detectionResult.detections.length === 0) {
    outputBoxElement.textContent = 'Inference complete. No objects detected above score threshold.';
    return;
  }

  // Draw detections
  detectionResult.detections.forEach((detection) => {
    const box = detection.boundingBox;
    const category = detection.categories[0];
    const label = category.categoryName || category.displayName || 'Unknown';
    const score = (category.score * 100).toFixed(1);
    const color = getLabelColor(label);

    // 1. Draw Bounding Box
    ctx.strokeStyle = color;
    ctx.lineWidth = Math.max(2, Math.round(canvasElement.width / 300)); // Dynamic stroke scaled to image size
    ctx.strokeRect(box.originX, box.originY, box.width, box.height);

    // 2. Prepare Label Text
    const text = `${label} ${score}%`;
    const fontSize = Math.max(14, Math.round(canvasElement.width / 50));
    ctx.font = `bold ${fontSize}px sans-serif`

    const textMetrics = ctx.measureText(text);
    const textWidth = textMetrics.width;
    const textHeight = fontSize + 6;

    // 3. Draw Label Background Box
    let labelY = box.originY - textHeight;
    // Keep label inside top border if box is at the very edge
    if (labelY < 0) labelY = box.originY;

    ctx.fillStyle = color;
    ctx.fillRect(box.originX, labelY, textWidth + 8, textHeight);

    // 4. Draw Label Text
    ctx.fillStyle = '#FFFFFF';
    ctx.fillText(text, box.originX + 4, labelY + fontSize);
  });


  outputBoxElement.textContent = `Inference complete. Detected ${detectionResult.detections.length} object(s).`;
}

checkBrowser();
startApplication();
