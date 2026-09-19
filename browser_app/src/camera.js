// Camera state
let stream = null;
let videoElement = null;
let frameCallbackId = null;
let lastFrameTime = null;
let fps = 0;
let fpsSamples = [];

// Camera states
let state = 'idle';

/**
 * Starts the webcam and attaches the resulting stream to the given video element.
 *
 * @param {HTMLVideoElement} video - Video element that should display the camera.
 * @returns {Promise<void>}
 */
export async function startCamera(video) {
    if (!(video instanceof HTMLVideoElement)) {
        throw new TypeError('startCamera() requires an HTMLVideoElement.');
    }

    // If a camera is already running, don't request another stream.
    if (stream) {
        return;
    }

    videoElement = video;
    state = 'requesting';

    try {
        stream = await navigator.mediaDevices.getUserMedia({
            video: true,
            audio: false
        });

        videoElement.srcObject = stream;

        await videoElement.play();

        state = 'running';
        startFrameMeasurement();
    } catch (error) {
        stream = null;
        videoElement.srcObject = null;

        if (error.name === 'NotAllowedError') {
            state = 'denied';
        } else {
            state = 'error';
        }

        throw error;
    }
}

/**
 * Stops the webcam and releases all camera tracks.
 */
export function stopCamera() {
    stopFrameMeasurement();

    if (stream) {
        for (const track of stream.getTracks()) {
            track.stop();
        }
    }

    stream = null;

    if (videoElement) {
        videoElement.srcObject = null;
    }

    videoElement = null;

    fps = 0;
    fpsSamples = [];
    lastFrameTime = null;
    state = 'idle';
}

/**
 * Returns the current camera state.
 *
 * Possible values:
 * - idle
 * - requesting
 * - running
 * - denied
 * - error
 */
export function getCameraState() {
    return state;
}

/**
 * Returns the most recently calculated FPS estimate.
 */
export function getCameraFps() {
    return fps;
}

/**
 * Starts measuring the rate at which the video element receives frames.
 */
function startFrameMeasurement() {
    if (!videoElement || !('requestVideoFrameCallback' in videoElement)) {
        return;
    }

    lastFrameTime = null;
    fpsSamples = [];
    fps = 0;

    frameCallbackId = videoElement.requestVideoFrameCallback(
        handleVideoFrame
    );
}

/**
 * Handles a newly rendered video frame and schedules measurement
 * of the next frame.
 *
 * @param {DOMHighResTimeStamp} now
 */
function handleVideoFrame(now) {
    if (!videoElement || state !== 'running') {
        return;
    }

    if (lastFrameTime !== null) {
        const frameTime = now - lastFrameTime;

        if (frameTime > 0) {
            const currentFps = 1000 / frameTime;

            fpsSamples.push(currentFps);

            // Keep a rolling window of recent frame measurements.
            // This smooths out small frame-to-frame timing variations.
            const maxSamples = 30;

            if (fpsSamples.length > maxSamples) {
                fpsSamples.shift();
            }

            fps =
                fpsSamples.reduce((sum, value) => sum + value, 0) /
                fpsSamples.length;
        }
    }

    lastFrameTime = now;

    frameCallbackId = videoElement.requestVideoFrameCallback(
        handleVideoFrame
    );
}

/**
 * Stops FPS measurement.
 */
function stopFrameMeasurement() {
    if (
        videoElement &&
        frameCallbackId !== null &&
        'cancelVideoFrameCallback' in videoElement
    ) {
        videoElement.cancelVideoFrameCallback(frameCallbackId);
    }

    frameCallbackId = null;
}
