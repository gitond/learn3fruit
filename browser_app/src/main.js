/// LIBRARY IMPORTS ///
import { ObjectDetector, FilesetResolver } from '@mediapipe/tasks-vision';
/// APPLICATION MODULE IMPORTS ///
import { startCamera, stopCamera, getCameraState, getCameraFps } from './camera.js';

/// DOM STUFF ///
// environment related
const statusElement = document.querySelector('#status');
const browserStatusElement = document.querySelector('#browser-status');
const applicationStatusElement = document.querySelector('#application-status');
const modelStatusElement = document.querySelector('#model-status');

// inference test related
const imageWrapperElement = document.querySelector('#image-wrapper');
const imageInputElement = document.querySelector('#image-input');
const testImageElement = document.querySelector('#test-image');
const canvasElement = document.querySelector('#output-canvas');
const runButton = document.querySelector('#run-btn');
const outputBoxElement = document.querySelector('#output-box');

// camera related
const cameraVideoElement = document.querySelector('#camera-video');
const cameraStartBtn = document.querySelector('#camera-start-btn');
const cameraStopBtn = document.querySelector('#camera-stop-btn');
const cameraStatusElement = document.querySelector('#camera-status');
const cameraFpsElement = document.querySelector('#camera-fps');


/// APPLICATION STATE ///
let objectDetector = null;
let currentObjectUrl = null;
let imageReady = false;
let fpsAnimationInterval = null; // Used to update the UI FPS reading on a timer
function updateRunButtonState() { runButton.disabled = !(objectDetector && imageReady); }

/// LOADING & SETUP ///
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
    // - generic
    imageInputElement.addEventListener('change', handleImageSelection);
    runButton.addEventListener('click', () => runUploadedImageInference(objectDetector));
    updateRunButtonState();
    // - camera
    cameraStartBtn.addEventListener('click', handleStartCamera);
    cameraStopBtn.addEventListener('click', handleStopCamera);

    console.log('ObjectDetector ready:', objectDetector);
    return objectDetector;
  } catch (error) {
    console.error('Failed to initialize MediaPipe ObjectDetector:', error);
    setStatus(`Error: ${error.message}`);
    modelStatusElement.textContent = 'Failed to load/compile.';
  }
}


/// WEBCAM HANDLING ///
async function handleStartCamera() {
  // Update button states & status text during request
  cameraStartBtn.disabled = true;
  cameraStatusElement.textContent = 'Requesting camera access...';

  try {
    await startCamera(cameraVideoElement);

    // Successfully started
    cameraStopBtn.disabled = false;
    cameraStatusElement.textContent = 'Camera active (running)';

    // Start UI update timer for rendering current FPS
    startFpsUiLoop();
  } catch (error) {
    cameraStartBtn.disabled = false;
    cameraStopBtn.disabled = true;

    if (error.name === 'NotAllowedError' || error.name === 'PermissionDeniedError') {
      cameraStatusElement.textContent = 'Error: Camera access denied by user or browser.';
    } else if (error.name === 'NotFoundError' || error.name === 'DevicesNotFoundError') {
      cameraStatusElement.textContent = 'Error: No camera device found.';
    } else {
      cameraStatusElement.textContent = `Error: ${error.message || 'Unable to access camera.'}`;
    }
  }
}

function handleStopCamera() {
  stopCamera();
  stopFpsUiLoop();

  // Reset UI
  cameraStartBtn.disabled = false;
  cameraStopBtn.disabled = true;
  cameraStatusElement.textContent = 'Camera stopped';
  cameraFpsElement.textContent = '—';
}

function startFpsUiLoop() {
  stopFpsUiLoop();

  // Refresh the rendered FPS text every ~250ms so numbers don't flicker uncontrollably
  fpsAnimationInterval = setInterval(() => {
    if (getCameraState() === 'running') {
      const currentFps = getCameraFps();
      cameraFpsElement.textContent = currentFps > 0 ? `${currentFps.toFixed(1)} FPS` : 'Calculating...';
    }
  }, 250);
}

function stopFpsUiLoop() {
  if (fpsAnimationInterval) {
    clearInterval(fpsAnimationInterval);
    fpsAnimationInterval = null;
  }
}

/// DISPLAYING & RENDERING FUNCTIONS ///
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

/**
 * Renders detection bounding boxes and labels onto a canvas.
 *
 * @param {DetectionResult} detectionResult
 * @param {HTMLCanvasElement} canvasElement
 */
function renderDetectionResult(detectionResult, canvasElement) {
  const ctx = canvasElement.getContext('2d');

  // Clear any previous render
  ctx.clearRect(0, 0, canvasElement.width, canvasElement.height);

  if (detectionResult.detections.length === 0) {
    return;
  }

  detectionResult.detections.forEach((detection) => {
    const box = detection.boundingBox;
    const category = detection.categories[0];
    const label = category.categoryName || category.displayName || 'Unknown';
    const score = (category.score * 100).toFixed(1);
    const color = getLabelColor(label);

    // 1. Draw Bounding Box
    ctx.strokeStyle = color;
    ctx.lineWidth = Math.max(2, Math.round(canvasElement.width / 300));
    ctx.strokeRect(
      box.originX,
      box.originY,
      box.width,
      box.height
    );

    // 2. Prepare Label Text
    const text = `${label} ${score}%`;
    const fontSize = Math.max(14, Math.round(canvasElement.width / 50));
    ctx.font = `bold ${fontSize}px sans-serif`;

    const textMetrics = ctx.measureText(text);
    const textWidth = textMetrics.width;
    const textHeight = fontSize + 6;

    // 3. Draw Label Background Box
    let labelY = box.originY - textHeight;

    // Keep label inside top border if box is at the very edge
    if (labelY < 0) {
      labelY = box.originY;
    }

    ctx.fillStyle = color;
    ctx.fillRect(
      box.originX,
      labelY,
      textWidth + 8,
      textHeight
    );

    // 4. Draw Label Text
    ctx.fillStyle = '#FFFFFF';
    ctx.fillText(
      text,
      box.originX + 4,
      labelY + fontSize
    );
  });
}

function resetImageUI() {
  if (imageWrapperElement) {
    imageWrapperElement.style.display = 'none';
  }
  testImageElement.src = '';

  const ctx = canvasElement.getContext('2d');
  ctx.clearRect(0, 0, canvasElement.width, canvasElement.height);

  outputBoxElement.textContent = 'Awaiting inference execution...';
  updateRunButtonState();
}

function prepareImageUIForInference(width, height) {
  canvasElement.width = width;
  canvasElement.height = height;
  imageWrapperElement.style.display = 'block';
  updateRunButtonState();
}

/// IMAGE HANDLING FUNCTIONS ///
function resetImageSelection() {
  if (currentObjectUrl) {
    URL.revokeObjectURL(currentObjectUrl);
    currentObjectUrl = null;
  }
  imageReady = false;

  resetImageUI();
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

/**
 * Loads a File object into an HTMLImageElement and returns a Object URL reference.
 * Pure data/DOM-node setup without UI status updates.
 */
function loadImageElement(file, imageElement) {
  return new Promise((resolve, reject) => {
    const objectUrl = URL.createObjectURL(file);

    imageElement.onload = () => {
      resolve({ objectUrl, naturalWidth: imageElement.naturalWidth, naturalHeight: imageElement.naturalHeight });
    };

    imageElement.onerror = () => {
      URL.revokeObjectURL(objectUrl);
      reject(new Error('Failed to load image into element.'));
    };

    imageElement.src = objectUrl;
  });
}

async function loadSelectedImage(file) {
  resetImageSelection();

  try {
    const { objectUrl, naturalWidth, naturalHeight } = await loadImageElement(file, testImageElement);

    // Store URL reference for cleanup later
    currentObjectUrl = objectUrl;
    imageReady = true;

    // Update UI state with loaded image properties
    prepareImageUIForInference(naturalWidth, naturalHeight);
  } catch (error) {
    resetImageSelection();
    outputBoxElement.textContent = 'Failed to load selected image.';
  }
}



/// INFERENCE STUFF ///
/**
 * Runs object detection on an image element.
 *
 * This is the core inference operation. It deliberately has
 * no knowledge of UI rendering or where the image came from.
 *
 * @param {ObjectDetector} detector
 * @param {HTMLImageElement} imageElement
 * @returns {DetectionResult}
 */
function runInference(detector, imageElement) {
  return detector.detect(imageElement);
}

/**
 * Runs inference using the currently loaded uploaded image
 * and performs the existing uploaded-image UI/rendering.
 *
 * @param {ObjectDetector} detector
 */
function runUploadedImageInference(detector) {
  if (!imageReady) {
    outputBoxElement.textContent =
      'No valid image loaded, please select an image...';
    return;
  }

  outputBoxElement.textContent = 'Running inference...';

  const detectionResult = runInference(
    detector,
    testImageElement
  );

  console.log('Detection Output:', detectionResult);

  renderDetectionResult(
    detectionResult,
    canvasElement
  );

  if (detectionResult.detections.length === 0) {
    outputBoxElement.textContent =
      'Inference complete. No objects detected above score threshold.';
    return;
  }

  outputBoxElement.textContent =
    `Inference complete. Detected ${detectionResult.detections.length} object(s).`;
}

/// ACTUALLY RUNNING THIS FILE ///
checkBrowser();
startApplication();
