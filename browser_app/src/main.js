import { ObjectDetector, FilesetResolver } from '@mediapipe/tasks-vision';

const statusElement = document.querySelector('#status');
const browserStatusElement = document.querySelector('#browser-status');
const applicationStatusElement = document.querySelector('#application-status');
const modelStatusElement = document.querySelector('#model-status');

const testImageElement = document.querySelector('#test-image');
const runButton = document.querySelector('#run-btn');
const outputBoxElement = document.querySelector('#output-box');

function setStatus(message) {
  statusElement.textContent = message;
}

function checkBrowser() {
  browserStatusElement.textContent = `${navigator.userAgent}`;
  return true;
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

    const objectDetector = await ObjectDetector.createFromOptions(vision, {
      baseOptions: {
        modelAssetPath: '/models/model.tflite',
        delegate: 'CPU' // Or 'GPU'
      },
      scoreThreshold: 0.35,
      runningMode: 'IMAGE'
    });

    modelStatusElement.textContent = 'Model loaded and compiled successfully!';
    setStatus('Application started successfully.');

    // Enable inference trigger UI
    runButton.disabled = false;
    runButton.addEventListener('click', () => runInference(objectDetector));

    console.log('ObjectDetector ready:', objectDetector);
    return objectDetector;
  } catch (error) {
    console.error('Failed to initialize MediaPipe ObjectDetector:', error);
    setStatus(`Error: ${error.message}`);
    modelStatusElement.textContent = 'Failed to load/compile.';
  }
}

function runInference(detector) {
  if (!testImageElement.complete) {
    outputBoxElement.textContent = 'Image still loading, please wait...';
    return;
  }

  outputBoxElement.textContent = 'Running inference...';

  // Execute inference on the image element
  const detectionResult = detector.detect(testImageElement);

  console.log('Detection Output:', detectionResult);

  // Format and output detection data
  if (detectionResult.detections.length === 0) {
    outputBoxElement.textContent = 'Inference complete. No objects detected above score threshold.';
    return;
  }

  const formattedOutput = detectionResult.detections.map((detection, index) => {
    const box = detection.boundingBox;
    const category = detection.categories[0];

    return [
      `--- Detection #${index + 1} ---`,
      `Label: ${category.categoryName || category.displayName || 'Unknown'}`,
      `Score: ${(category.score * 100).toFixed(2)}%`,
      `Bounding Box:`,
      `  Origin X: ${box.originX}px`,
      `  Origin Y: ${box.originY}px`,
      `  Width:    ${box.width}px`,
      `  Height:   ${box.height}px`
    ].join('\n');
  }).join('\n\n');

  outputBoxElement.textContent = formattedOutput;
}

checkBrowser();
startApplication();
