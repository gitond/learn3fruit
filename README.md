# learn3fruit

A complete rewrite of the learn2fruit project

## Goal

The goal of this application is to prove that a Computer Vision Neural Network can be used to power a WebAR/Mobile-AR application. The finished app will guide the user through the preparation of a fruit salad given using a built in recipe (step-by-step format), where the neural network knows where to display the 3D-Augmentations by locating the ingredients & tools (object detection).

## Recipe 

The finished app will guide the users through the following recipe steps:

```tex
\begin{lstlisting}[caption=The recipe,captionpos=b,label=recipelisting]
Chop apples with a knife
Place apples to bowl
Chop oranges with a knife
Place oranges to bowl
Chop bananas with a knife
Place bananas to bowl
Stir apples, oranges and bananas in a bowl with a spoon
\end{lstlisting}
```

## Architecture / Tech stack

### Training stage

 - Python 3
 - TensorFlow
 - SSD + MobileNet-v2
 - Training in containerized environment (Docker/Podman)
 - .sh files for 
 - jq for data exploration
 - graphical data displaying tools needed 

### Browser app

 - Javascript
 - TensorFlow.js for in-browser inference
 - A-Frame for 3D/AR rendering
 - Webcam feed
 - Static hosting (no backend needed)

### Bridging

 - `tensorflowjs_converter` to convert the Python SavedModel to a format TF.js can load

## Implementation stages

### Stage 1: Data Gathering

Gather enough high quality data to train *SSD + MobileNet-v2* Neural Network for Object detection task. Relevant questions & challenges: 1, 2

Data categories:

 - apple
 - knife
 - bowl
 - orange
 - banana
 - spoon

We'll need to gather an **approximately** equal amount of data for these categories

**PROBLEM:** we assume a lot more data will be available for fruits (apple, orange, banana) than for kitchen appliances (knife, bowl, spoon)

Data will need to be preprocessed so that:

 - data from different sources shares a format
 - no unnecessary "polluting" categories exist in data
 - data format supported by nn for training

Whole preprocessing pipeline (download, reformatting, file structure building) needs to be handled by single .sh file (so that it's doable in a containerized environment without issue)

### Stage 2: NN-Training

 - *Tensorflow* compatible *SSD + MobileNet-v2* implementation needed (q3)
   - may need to be pre-trained (depends on how we decide to handle q1)
 - Training needs to happen on GPU
 - Training in containerized environment (Docker/Podman)
 - End result: trained, lightweight, exportable (tensorflowjs_converter) nn, we can run inference on

### Stage 3: Browser app

 - Infer on webcam feed using exported nn
 - Walk through **Recipe** above
 - Use nn to "recognize" each step (q4)
 - 3d animation for each step rendered on top of webcam feed (A-frames; This is the step that makes this app "AR")

## Project structure

```
.
├── browser_app
├── data_and_training
│   ├── data
│   │   ├── preprocessed
│   │   └── raw
│   │       ├── ds1
│   │       └── ds2
│   ├── data_display
│   ├── data_download
│   ├── data_pipeline.sh
│   ├── data_preprocess
│   ├── devtools
│   │   ├── example.jq
│   │   ├── file_from_github.py
│   │   └── library_from_github
│   ├── .dockerignore
│   ├── models
│   │   └── my_ssd_mobilenet_v2
│   ├── trainer.Dockerfile
│   └── trainer.py
├── .gitignore
├── README.md
└── requirements.txt
```

This is a conceptual plan, actual implementation may differ. Precise plan for browser app will be designed later (q5)

## Hardware availability

GPU: Nvidia Geforce GTX 1660 Super. We might get access to a dual-4090-server (or other high performance hardware) for training. It is important to perform training in a containerized ienvironment for easy portability.

## Open questions/challenges

 1. Fine tuning vs training from scratch
    - Fine tuning: faster, lower effort, less data needed, BUT: fine tuning data can't include data from pre-training stage (limits acceptable data sources)
 2. How much data is actually needed? Where to acquire it? Licensing needs
 3. Where to find *Tensorflow* compatible *SSD + MobileNet-v2* implementation (use pre-existing implementation from github/huggingface/some pre-existing library/some pre-existing model collection; remember: may be pre-trained, important to know what it's pre-trained on)
 4. Object detection to recipe step recognition. How do we do this exactly?
 5. Precise browser app structure and specification still needs to be decided
