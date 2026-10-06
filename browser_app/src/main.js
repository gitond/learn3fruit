/// LIBRARY IMPORTS ///
import { ObjectDetector, FilesetResolver } from '@mediapipe/tasks-vision';
/// APPLICATION MODULE IMPORTS ///
import { startCamera, stopCamera, getCameraState, getCameraFps } from './camera.js';

/// DOM STUFF ///
// environment & debug related
const statusElement = document.querySelector('#status');
const browserStatusElement = document.querySelector('#browser-status');
const applicationStatusElement = document.querySelector('#application-status');
const modelStatusElement = document.querySelector('#model-status');
const protocolStatusElement = document.querySelector('#protocol-status');
const secureContextStatusElement = document.querySelector('#secure-context-status');
const mediaDevicesStatusElement = document.querySelector('#media-devices-status');
const getUserMediaStatusElement = document.querySelector('#get-user-media-status');
const hostnameStatusElement = document.querySelector('#hostname-status');
const portStatusElement = document.querySelector('#port-status');
const originStatusElement = document.querySelector('#origin-status');

// inference test related
const imageWrapperElement = document.querySelector('#image-wrapper');
const imageInputElement = document.querySelector('#image-input');
const testImageElement = document.querySelector('#test-image');
const canvasElement = document.querySelector('#output-canvas');
const runButton = document.querySelector('#run-btn');
const imageOutputBoxElement = document.querySelector('#image-output-box');

// camera related
const cameraVideoElement = document.querySelector('#camera-video');
const webcamCanvasElement = document.querySelector('#webcam-output-canvas');
const cameraStartBtn = document.querySelector('#camera-start-btn');
const cameraStopBtn = document.querySelector('#camera-stop-btn');
const cameraStatusElement = document.querySelector('#camera-status');

// measurement related
const measurementRenderingsElement = document.querySelector('#measurement-renderings');
const webcamOutputBoxElement = document.querySelector('#webcam-output-box');
const recordCsvToggle = document.querySelector('#record-csv-toggle');
const downloadCsvBtn = document.querySelector('#download-csv-btn');
const recordStatusElement = document.querySelector('#record-status');

/// APPLICATION STATE ///
let objectDetector = null;
let currentObjectUrl = null;
let imageReady = false;
let fpsAnimationInterval = null; // Used to update the UI FPS reading on a timer
let inferenceInterval = null; // Timer reference for periodic camera inference (inference fps)
let measurementInterval = null;

let samplingCount = 0;
let inferenceCount = 0;
let inferenceLatencyMs = 0;
let measurementWindowStart = null;
let isRecording = false;
let recordedData = []; // Stores array of measurement objects
let sessionStartTime = null;

function updateRunButtonState() { runButton.disabled = !(objectDetector && imageReady); }

/// TRACKER DATA STRUCTURES & ADAPTERS ///

/**
 * Constants governing tracking configuration and confidence thresholds.
 */
const TRACKER_CONFIG = {
  // Window parameters for temporal reasoning
  BUFFER_WINDOW_MS: 500, // Minimal time window (y_ms)
  MIN_BUFFER_FRAMES: 10, // Minimal frame count window (x_frames)

  // Confidence thresholds
  MIN_TRACK_CONFIDENCE: 0.50, // Minimum track confidence to consider an instance CONFIRMED

  // Lifecycle thresholds
  CONFIRMATION_FRAMES: 3,     // Required consecutive detections before promotion from TENTATIVE
  MISSING_FRAMES_LIMIT: 5,    // Consecutive missed frames before marking DELETED

  // Matching thresholds (in pixel space)
  MAX_MATCH_DISTANCE_PX: 100
};

/**
 * Enumeration of lifecycle states for an object track instance.
 */
const TrackStatus = {
  TENTATIVE: 'TENTATIVE',
  CONFIRMED: 'CONFIRMED',
  TEMPORARILY_MISSING: 'TEMPORARILY_MISSING',
  DELETED: 'DELETED'
};

/**
 * Represents a single normalized observation extracted from a detector output frame.
 */
class Observation {
  /**
   * @param {Object} params
   * @param {number} params.timestamp - Capture timestamp (e.g., performance.now())
   * @param {string} params.category - Primary category label
   * @param {number} params.detectionConfidence - Raw score from the detector (0.0 - 1.0)
   * @param {Object} params.boundingBox - Original bounding box { originX, originY, width, height, angle }
   * @param {Object} params.center - Calculated pixel coordinates { centerX, centerY }
   */
  constructor({ timestamp, category, detectionConfidence, boundingBox, center }) {
    this.timestamp = timestamp;
    this.category = category;
    this.detectionConfidence = detectionConfidence;
    this.boundingBox = boundingBox;
    this.center = center;
  }
}

/**
 * Data structure representing a list of observations for one inference frame.
 */
class TrackerInput {
  /**
   * @param {number} timestamp
   * @param {Observation[]} observations
   */
  constructor(timestamp, observations = []) {
    this.timestamp = timestamp;
    this.observations = observations;
  }
}

/**
 * Represents a persistent hypothesis that multiple observations belong to the same physical object.
 */
class Track {
  /**
   * @param {string} instanceId - Unique identifier (e.g. "inst_1")
   * @param {Observation} initialObservation - First observation that spawned this track
   */
  constructor(instanceId, initialObservation) {
    this.instanceId = instanceId;
    this.status = TrackStatus.TENTATIVE;

    // Core spatial state (in pixel coordinates)
    this.center = { ...initialObservation.center };
    this.boundingBox = { ...initialObservation.boundingBox };
    this.velocity = { x: 0, y: 0 }; // Velocity vector in pixels/ms

    // Temporal evidence & history
    this.history = [initialObservation];
    this.categoryHistory = [{ category: initialObservation.category, timestamp: initialObservation.timestamp }];
    this.currentCategory = initialObservation.category;

    // Separate confidence metrics
    this.lastDetectionConfidence = initialObservation.detectionConfidence;
    this.trackConfidence = 0.30; // Initial tentative track confidence score

    // Counters and timestamps
    this.createdAt = initialObservation.timestamp;
    this.updatedAt = initialObservation.timestamp;
    this.consecutiveHits = 1;
    this.consecutiveMisses = 0;
  }
}

/**
 * Data structure exposing current state to downstream consumers (AR Renderer, Trajectory, etc.).
 */
class TrackerOutput {
  /**
   * @param {number} timestamp
   * @param {Track[]} tracks
   */
  constructor(timestamp, tracks = []) {
    this.timestamp = timestamp;
    this.tracks = tracks;
  }
}

/**
 * Calculates the center point of a bounding box in pixel coordinates.
 *
 * @param {Object} boundingBox - { originX, originY, width, height }
 * @returns {{ centerX: number, centerY: number }}
 */
function calculateCenter(boundingBox) {
  return {
    centerX: boundingBox.originX + boundingBox.width / 2,
    centerY: boundingBox.originY + boundingBox.height / 2
  };
}

/**
 * Adapts a MediaPipe detection item into an internal Observation data structure.
 *
 * @param {Object} detection - Single item from MediaPipe detectionResult.detections
 * @param {number} timestamp - High-resolution timestamp (e.g. performance.now())
 * @returns {Observation}
 */
function toObservation(detection, timestamp = performance.now()) {
  const primaryCategory = detection.categories?.[0];
  const categoryName = primaryCategory?.categoryName || 'unknown';
  const detectionConfidence = primaryCategory?.score || 0;

  const boundingBox = {
    originX: detection.boundingBox.originX,
    originY: detection.boundingBox.originY,
    width: detection.boundingBox.width,
    height: detection.boundingBox.height,
    angle: detection.boundingBox.angle || 0
  };

  const center = calculateCenter(boundingBox);

  return new Observation({
    timestamp,
    category: categoryName,
    detectionConfidence,
    boundingBox,
    center
  });
}

/**
 * Converts a raw MediaPipe DetectionResult payload into a normalized TrackerInput object.
 *
 * @param {Object} detectionResult - Raw output from objectDetector.detect()
 * @param {number} timestamp - High-resolution timestamp
 * @returns {TrackerInput}
 */
function toTrackerInput(detectionResult, timestamp = performance.now()) {
  if (!detectionResult || !Array.isArray(detectionResult.detections)) {
    return new TrackerInput(timestamp, []);
  }

  const observations = detectionResult.detections.map(detection =>
    toObservation(detection, timestamp)
  );

  return new TrackerInput(timestamp, observations);
}



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
    recordCsvToggle.addEventListener('change', handleToggleRecording);
    downloadCsvBtn.addEventListener('click', downloadCsvFile);
    // - camera
    cameraStartBtn.addEventListener('click', handleStartCamera);
    cameraStopBtn.addEventListener('click', handleStopCamera);
    cameraStartBtn.disabled = false;

    console.log('ObjectDetector ready:', objectDetector);
    return objectDetector;
  } catch (error) {
    console.error('Failed to initialize MediaPipe ObjectDetector:', error);
    setStatus(`Error: ${error.message}`);
    modelStatusElement.textContent = 'Failed to load/compile.';
    cameraStartBtn.disabled = true;
    runButton.disabled = true;
  }
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
    imageOutputBoxElement.textContent = 'Failed to load selected image.';
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

    // Mapping camera canvas coordinate system to actual webcam frames
    prepareWebcamCanvas();

    // Start UI update timer for rendering current FPS
    startFpsUiLoop();

    // Start running inference at specified FPS
    startInferenceMeasurements();
    startCameraInferenceLoop(14);
  } catch (error) {
    cameraStartBtn.disabled = false;
    cameraStopBtn.disabled = true;


    // Camera related error-classification
    const cameraState = getCameraState();

    if (cameraState === 'denied') {
      cameraStatusElement.textContent =
        'Error: Camera access denied by user or browser.';
    } else if (cameraState === 'no-camera') {
      cameraStatusElement.textContent = 'Error: No camera device found.';
    } else {
      cameraStatusElement.textContent =
        `Error: ${error.message || 'Unable to access camera.'}`;
    }
  }
}

function handleStopCamera() {
  stopCamera();
  stopFpsUiLoop();
  stopCameraInferenceLoop();
  stopInferenceMeasurements();

  // Reset UI
  cameraStartBtn.disabled = false;
  cameraStopBtn.disabled = true;

  cameraStatusElement.textContent = 'Camera stopped';
  webcamOutputBoxElement.textContent = 'Camera stopped';

  measurementRenderingsElement.textContent = 'Awaiting measurements...';

  webcamCanvasElement
    .getContext('2d')
    .clearRect(
      0,
      0,
      webcamCanvasElement.width,
      webcamCanvasElement.height
    );

  // Reset recording
  if (isRecording) {
    recordCsvToggle.checked = false;
    handleToggleRecording({ target: { checked: false } });
  }
}

function startFpsUiLoop() {
  stopFpsUiLoop();

  fpsAnimationInterval = setInterval(() => {
    if (getCameraState() === 'running') {
      updateMeasurementRendering();
    }
  }, 250);
}

function stopFpsUiLoop() {
  if (fpsAnimationInterval) {
    clearInterval(fpsAnimationInterval);
    fpsAnimationInterval = null;
  }
}



/// WEBCAM INFERENCE MEASUREMENTS ///
function startInferenceMeasurements() {
  stopInferenceMeasurements();

  samplingCount = 0;
  inferenceCount = 0;
  inferenceLatencyMs = 0;
  measurementWindowStart = performance.now();

  measurementInterval = setInterval(() => {
    const now = performance.now();
    const elapsedSeconds = (now - measurementWindowStart) / 1000;

    if (elapsedSeconds <= 0) { return; }

    const cameraFps = getCameraFps();
    const samplingFps = samplingCount / elapsedSeconds;
    const inferenceFps = inferenceCount / elapsedSeconds;

    if (isRecording) {
      recordedData.push({
        timestamp: new Date().toISOString(),
        cameraFps: Number(cameraFps.toFixed(2)),
        samplingFps: Number(samplingFps.toFixed(2)),
        inferenceFps: Number(inferenceFps.toFixed(2)),
        latencyMs: Number(inferenceLatencyMs.toFixed(2))
      });
      if (recordStatusElement) {
        recordStatusElement.textContent = `Recording... (${recordedData.length} samples)`;
      }
    }

    updateMeasurementRendering();

    samplingCount = 0;
    inferenceCount = 0;
    measurementWindowStart = now;
  }, 1000);
}

function stopInferenceMeasurements() {
  if (measurementInterval) {
    clearInterval(measurementInterval);
    measurementInterval = null;
  }
  samplingCount = 0;
  inferenceCount = 0;
  inferenceLatencyMs = 0;
  measurementWindowStart = null;
}

function handleToggleRecording(event) {
    isRecording = event.target.checked;

    if (isRecording) {
        // Reset buffers for new recording session
        recordedData = [];
        sessionStartTime = new Date();
        downloadCsvBtn.disabled = true;
        recordStatusElement.textContent = 'Recording started...';
    } else {
        // Stopped recording
        const sampleCount = recordedData.length;
        if (sampleCount > 0) {
            downloadCsvBtn.disabled = false;
            recordStatusElement.textContent = `Stopped. ${sampleCount} samples ready.`;
        } else {
            recordStatusElement.textContent = 'Stopped (no samples recorded).';
        }
    }
}

function downloadCsvFile() {
    if (recordedData.length === 0) return;

    // 1. Build CSV content string
    const headers = ['Timestamp', 'Camera_FPS', 'Sampling_FPS', 'Inference_FPS', 'Latency_MS'];
    const rows = recordedData.map(d =>
        `"${d.timestamp}",${d.cameraFps},${d.samplingFps},${d.inferenceFps},${d.latencyMs}`
    );
    const csvContent = [headers.join(','), ...rows].join('\n');

    // 2. Format ISO Timestamp for file name: fps_YYYYMMDD_HHMMSS.csv
    const ts = sessionStartTime || new Date();
    const pad = (n) => String(n).padStart(2, '0');
    const timeStr = `${ts.getFullYear()}${pad(ts.getMonth() + 1)}${pad(ts.getDate())}_${pad(ts.getHours())}${pad(ts.getMinutes())}${pad(ts.getSeconds())}`;
    const filename = `fps_${timeStr}.csv`;

    // 3. Create downloadable Blob URL
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);

    // 4. Trigger browser download
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.setAttribute('download', filename);
    document.body.appendChild(anchor);
    anchor.click();

    // 5. Cleanup
    document.body.removeChild(anchor);
    URL.revokeObjectURL(url);
}


/// INFERENCE STUFF ///
/**
 * Runs object detection on an image element.
 *
 * This is the core inference operation. It deliberately has
 * no knowledge of UI rendering or where the image came from.
 *
 * @param {ObjectDetector} detector
 * @param {HTMLImageElement, HTMLVideoElement} imageElement
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
    imageOutputBoxElement.textContent =
      'No valid image loaded, please select an image...';
    return;
  }

  imageOutputBoxElement.textContent = 'Running inference...';

  const detectionResult = runInference(
    detector,
    testImageElement
  );

  // Bbox rendering
  renderDetectionResult(
    detectionResult,
    canvasElement
  );

  // Textual output
  const summaryText = `Inference complete. Detected ${detectionResult.detections.length} object(s).\n\n`;
  imageOutputBoxElement.textContent = summaryText + renderDetectionResultText(detectionResult);

}

/**
 * Captures the current frame from the webcam video element,
 * runs inference through the existing detector pipeline,
 * and renders the detection result.
 */
function runWebcamFrameInference() {
  if (getCameraState() !== 'running') {
    webcamOutputBoxElement.textContent = 'Camera is not active.';
    return false;
  }

  prepareWebcamCanvas();

  webcamOutputBoxElement.textContent = 'Running inference on camera frame...';

  const inferenceStart = performance.now();

  // detector.detect() accepts HTMLVideoElement directly and extracts the current frame
  const detectionResult = runInference(objectDetector, cameraVideoElement);

  const inferenceEnd = performance.now();
  inferenceLatencyMs = inferenceEnd - inferenceStart;

  inferenceCount++;

  // Inference result output. Several times per s. Comment out when not using.
  //console.log(`[Webcam inference] ${inferenceLatencyMs.toFixed(2)} ms`, detectionResult);

  // Visual output
  renderDetectionResult(
    detectionResult,
    webcamCanvasElement
  );

  const summaryText = `[Camera Snapshot] Detected ${detectionResult.detections.length} object(s).\n\n`;
  webcamOutputBoxElement.textContent = summaryText + renderDetectionResultText(detectionResult);
  return true;
}

/**
 * Starts running frame inference periodically at a specified frame rate.
 * @param {number} fps - Target detections per second (e.g., 5)
 */
function startCameraInferenceLoop(fps = 5) {
  stopCameraInferenceLoop(); // Clear any existing loop

  const intervalMs = 1000 / fps; // 5 FPS = 200ms per frame
  inferenceInterval = setInterval(() => {
    if (getCameraState() === 'running' && objectDetector) {
      const sampled = runWebcamFrameInference();

      if (sampled) {
        samplingCount++;
      }
    }
  }, intervalMs);
}

function stopCameraInferenceLoop() {
  if (inferenceInterval) {
    clearInterval(inferenceInterval);
    inferenceInterval = null;
  }
}


/// TRACKER BUFFER ENGINE ///

/**
 * Temporal history queue for tracking observations.
 *
 * Implements dual temporal/frame-count eviction logic:
 *   should_dequeue = enough_frames && enough_time
 *
 * Where:
 *   enough_frames : buffer.length > TRACKER_CONFIG.MIN_BUFFER_FRAMES
 *   enough_time   : current_timestamp - oldest_entry.timestamp > TRACKER_CONFIG.BUFFER_WINDOW_MS
 */
class TemporalBuffer {
  /**
   * @param {Object} [config=TRACKER_CONFIG]
   */
  constructor(config = TRACKER_CONFIG) {
    this.buffer = [];
    this.minBufferFrames = config.MIN_BUFFER_FRAMES;
    this.bufferWindowMs = config.BUFFER_WINDOW_MS;
  }

  /**
   * Enqueues a new TrackerInput frame observation and triggers the dequeue check.
   *
   * @param {TrackerInput} trackerInput - Normalized frame observations with timestamp
   */
  enqueue(trackerInput) {
    if (!trackerInput || typeof trackerInput.timestamp !== 'number') {
      return;
    }

    this.buffer.push(trackerInput);
    this._evictStaleEntries(trackerInput.timestamp);
  }

  /**
   * Internal dequeue check that purges stale entries from the front of the queue.
   *
   * @param {number} currentTimestamp - Timestamp of the most recently enqueued frame
   * @private
   */
  _evictStaleEntries(currentTimestamp) {
    while (this.buffer.length > 0) {
      const oldestEntry = this.buffer[0];
      const timeElapsed = currentTimestamp - oldestEntry.timestamp;

      const enoughFrames = this.buffer.length > this.minBufferFrames;
      const enoughTime = timeElapsed > this.bufferWindowMs;

      // Dequeue if and only if both conditions are met
      if (enoughFrames && enoughTime) {
        this.buffer.shift();
      } else {
        break; // Stop checking once the oldest remaining entry should not be dequeued
      }
    }
  }

  /**
   * Returns a copy of all current TrackerInput entries stored in the buffer.
   *
   * @returns {TrackerInput[]}
   */
  getEntries() {
    return [...this.buffer];
  }

  /**
   * Flattens and returns all observations stored across all frames in the buffer.
   *
   * @returns {Observation[]}
   */
  getAllObservations() {
    return this.buffer.flatMap(entry => entry.observations);
  }

  /**
   * Returns the current number of frames in the buffer.
   *
   * @returns {number}
   */
  getFrameCount() {
    return this.buffer.length;
  }

  /**
   * Clears all entries from the buffer.
   */
  clear() {
    this.buffer = [];
  }
}




/// TRACKER: PREDICTIONS & MATCHING ///
/// TRACKER LIFECYCLE & STATE MANAGEMENT ///


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
  browserStatusElement.textContent = navigator.userAgent;

  protocolStatusElement.textContent = window.location.protocol;

  secureContextStatusElement.textContent =
    window.isSecureContext ? 'Yes' : 'No';

  mediaDevicesStatusElement.textContent =
    navigator.mediaDevices ? 'Available' : 'Unavailable';

  getUserMediaStatusElement.textContent =
    navigator.mediaDevices?.getUserMedia
      ? 'Available'
      : 'Unavailable';

  hostnameStatusElement.textContent =
    window.location.hostname;

  portStatusElement.textContent =
    window.location.port || '(default)';

  originStatusElement.textContent =
    window.location.origin;

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

/**
 * Formats detection results into a plain-text table or structured list.
 *
 * @param {DetectionResult} detectionResult
 * @returns {string} Formatted text output
 */
function renderDetectionResultText(detectionResult) {
  if (!detectionResult || detectionResult.detections.length === 0) {
    return 'No objects detected above score threshold.';
  }

  const lines = [
    'class           confidence      location',
    '------------------------------------------------------------------'
  ];

  detectionResult.detections.forEach((detection) => {
    const category = detection.categories[0];
    const label = (category?.categoryName || category?.displayName || 'Unknown').padEnd(16, ' ');
    const score = `${((category?.score || 0) * 100).toFixed(1)}%`.padEnd(16, ' ');

    const box = detection.boundingBox;
    const location = `x: ${Math.round(box.originX)}, y: ${Math.round(box.originY)}, w: ${Math.round(box.width)}, h: ${Math.round(box.height)}`;

    lines.push(`${label}${score}${location}`);
  });

  return lines.join('\n');
}

function resetImageUI() {
  if (imageWrapperElement) {
    imageWrapperElement.style.display = 'none';
  }
  testImageElement.src = '';

  const ctx = canvasElement.getContext('2d');
  ctx.clearRect(0, 0, canvasElement.width, canvasElement.height);

  imageOutputBoxElement.textContent = 'Awaiting inference execution...';
  updateRunButtonState();
}

function prepareImageUIForInference(width, height) {
  canvasElement.width = width;
  canvasElement.height = height;
  imageWrapperElement.style.display = 'block';
  updateRunButtonState();
}

function prepareWebcamCanvas() {
  const width = cameraVideoElement.videoWidth;
  const height = cameraVideoElement.videoHeight;

  if (width === 0 || height === 0) {
    return;
  }

  if (
    webcamCanvasElement.width !== width ||
    webcamCanvasElement.height !== height
  ) {
    webcamCanvasElement.width = width;
    webcamCanvasElement.height = height;
  }
}

function updateMeasurementRendering() {
  if (!measurementRenderingsElement) {
    return;
  }

  const currentFps = getCameraFps();

  const elapsedSeconds =
    measurementWindowStart === null
      ? 0
      : (performance.now() - measurementWindowStart) / 1000;

  const samplingFps =
    elapsedSeconds > 0
      ? samplingCount / elapsedSeconds
      : 0;

  const inferenceFps =
    elapsedSeconds > 0
      ? inferenceCount / elapsedSeconds
      : 0;

  measurementRenderingsElement.textContent =
    `[Webcam measurements] ` +
    `Camera: ${currentFps.toFixed(2)} FPS | ` +
    `Sampling: ${samplingFps.toFixed(2)} FPS | ` +
    `Inference: ${inferenceFps.toFixed(2)} FPS | ` +
    `Latency: ${inferenceLatencyMs.toFixed(2)} ms`;
}

/// ACTUALLY RUNNING THIS FILE ///
checkBrowser();
startApplication();
