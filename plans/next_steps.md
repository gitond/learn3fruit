 1. Webcam integration. Day by day:
    1. Camera module. In own .js file. Import it into main.js. Link up to new UI element in index.html. Keep separate from inference at first. Measure camera fps. Think about permission handling, permission failure, etc
    2. Frame sampling. Start with 10fps.  Make sampling format match nn input. Run inference on samples (without visualisations yet). Try to match sampling and inference rates experiment with (1-30 fps sampling, variable sample rate, compare to inference rate, etc.). Make camera vs sampling vs inference measurements.
    3. Debug day for previous 2.
    4. Connect inference visualisations to webcam rendering. Test: Multiple devices, cameras, etc. Test: long-running behavior (watch for: memory growth, increasing inference latency, browser throttling, exceptions, camera stream stopping, inference loop continuing after camera shutdown). For every test: record as much data as possible. Ensure interfaces are as clean as possible.
 2. Tracking: `Obd -> insDet`; some internal logic of the following: given object o of category c is at location (400x,150y); if an object of category c is at (395x,145y) in the next frame, it's likely the same object.
 3. Some way to record instance trajectories
 4. AR UI: appropriate 3D renderings on coordinates of the input frames based on inference results using some 3D js library (Three.js is a possibility, others should be investigated)
 5. AR progress detection; The user is supposed to complete a list of steps while in the AR app; we can build a model of "what kind of movements of each object category constitute progress in the step list", and we can turn this into AR progress detection.

Intersting links: [](https://hackernoon.com/we-built-a-face-and-mask-detection-web-app-for-google-chrome-836n33aq) [](https://www.webrtc-developers.com/building-your-own-video-pipeline/)
