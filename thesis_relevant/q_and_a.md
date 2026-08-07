# Open questions & answers

## 1. Fine tuning vs training from scratch

 - Fine tuning: faster, lower effort, less data needed, BUT: fine tuning data can't include data from pre-training stage (limits acceptable data sources)

We want to fine-tune a pre-trained ssd-mobilenet-v2, because that requires a much smaller data set (COCO contains over 110k images, He, Girshick & Dollar only used 10% of it for fine-tuning and achieved comparable results)

> "Transfer learning is usually done for tasks where your dataset has too little data to train a full-scale model from scratch."

[Transfer learning & fine-tuning | TensorFlow Core](https://www.tensorflow.org/guide/keras/transfer_learning)

> "ImageNet pre-training speeds up convergence early in training, but does not necessarily provide regularization or improve final target task accuracy"

> "results hold even when: (i) using only 10% of the training data"

He, Girshick & Dollar, *Rethinking ImageNet Pre-Training*, ICCV 2019 · [CVF Open Access](https://openaccess.thecvf.com/content_ICCV_2019/html/He_Rethinking_ImageNet_Pre-Training_ICCV_2019_paper.html)

---

## 2. How much data is actually needed? Where to acquire it? Licensing needs

I didn't find a straightforward answer to the "how many images I need" from scientific literature. (**NOTE:** this itself can be considered a problem in using CV with AR (or with using CV in general)) Bumbaca's & Borgogno-Mondino's research paper to determine how many images are needed to fine-tune an object detection neural network got 60-130 images as a reasonable answer. However they trained a single-class object detector so it doesn't exactly cover our needs. Another study by Paiano et al. measures how one can achieve high performance quality with object detection systems comparing traditional datasets with datasets of real images augmented with ai generated images. They used datasets with 300 ral images + many more AI generated. Deducing from this: We'd probably need more than 300 images per category. Let's say 350.

> "models trained on in-domain data reached the benchmark with as few as 60–130 annotated images, depending on architecture"

> "no model trained on out-of-distribution data achieved acceptable performance, regardless of dataset size"

Bumbaca & Borgogno-Mondino, *On the Minimum Dataset Requirements for Fine-Tuning an Object Detector for Arable Crop Plant Counting*, Remote Sensing 2025 · [DOI: 10.3390/rs17132190](https://doi.org/10.3390/rs17132190)


> "Our method achieves detection performance comparable to models trained on thousands of images, using only a few hundreds of input data."

> "300 real images combined with 9,000 generated images exhibit performance equivalent to the full dataset of 4,500 real images."

Paiano et al., *Transfer learning with generative models for object detection on limited datasets*, University of Florence, arXiv:2402.06784 · [arXiv](https://arxiv.org/html/2402.06784v1) 

As to where to get pre-existing data from: Below are a few links:

- [detection-datasets/coco](https://huggingface.co/datasets/detection-datasets/coco)
- [bitmind/open-images-v7](https://huggingface.co/datasets/bitmind/open-images-v7)
- [lrad3/kitchen_utensils_13k](https://huggingface.co/datasets/lrad3/kitchen_utensils_13k)

---

## 3. Where to find *Tensorflow* compatible *SSD + MobileNet-v2* implementation (use pre-existing implementation from github/huggingface/some pre-existing library/some pre-existing model collection; remember: may be pre-trained, important to know what it's pre-trained on)

I found three ways to retrain a pre-trained *SSD + MobileNet-v2* implementation:

**Plan 1 — MediaPipe Model Maker (primary)**
- Source: `mediapipe-model-maker` pip library (Google, actively maintained)
- Model: SSD + MobileNet v2, 256×256 or 320×320 input
- Pretrained on: COCO 2017 (detection head) + ImageNet (MobileNet v2 backbone)
- Browser runtime: `@mediapipe/tasks-vision` (npm), loads `.tflite` export
- [mediapipe-model-maker object detection docs](https://ai.google.dev/edge/mediapipe/solutions/customization/object_detector)

**Plan 2 — PyTorch SSD (secondary)**
- Source: `qfgaohao/pytorch-ssd` on GitHub, pretrained weights included
- Model: SSD + MobileNet v2
- Pretrained on: COCO 2017 (exact checkpoint TBC from repo README at implementation time)
- Browser runtime: `onnxruntime-web` (npm), loads `.onnx` export
- [qfgaohao/pytorch-ssd](https://github.com/qfgaohao/pytorch-ssd)

**Plan 3 — TF Object Detection API (fallback)**
- Source: TF2 Detection Model Zoo (`ssd_mobilenet_v2_320x320_coco17_tpu-8`)
- Pretrained on: COCO 2017
- Browser runtime: `@tensorflow/tfjs` (npm), loads TF.js graph model converted via `tensorflowjs_converter`
- [TF2 Detection Model Zoo](https://github.com/tensorflow/models/blob/master/research/object_detection/g3doc/tf2_detection_zoo.md)

---

## 4. Given a) a Nvidia Geforce GTX 1660 SUPER b) two Nvidia Geforce RTX 3090 GPUs    what kind of hyperparameters should we use?

mediapipe let's me set learning rate, batch size, number of epochs, steps per epoch, checkpoints, cosine decay ([source](https://developers.google.com/edge/api/mediapipe/python/mediapipe_model_maker/object_detector/HParams)). Notably warmup is seemingly not supported.

[Other people](https://arxiv.org/abs/2010.04427) used substantially lower lr than the mediapipe default, so we start experimenting with a 0.08 starting lr (we change it if we think this breaks the system) on 1660 super and 0.32 starting lr on dual 3090 (larger batches)

[Park et al.](https://arxiv.org/abs/2010.04427) used a 32 batch size on a 24GB GPU, on our dual 3090 setup we have two of those so a batch size of 64 is applicable there. For our 1660 SUPER we start at 16, and if it OOMs (which it probably will) we move down to 8 which is the mediapipe default.

We start at 30 epochs, but if the training loss still visibly reduces in the last steps we can move up to 60, 90, 120 epochs respectively

We won't touch the `steps_per_epoch` parameter (even though our ds is still closer to 2000 images than 1500 even after the train-val-split)

We use checkpointing (set `export_dir` to `data_and_training/models/ssd_plus_mobilenet_v2_l3f_TIMESTAMP/checkpoints`)

`num_gpus` is 1 for our 1660 SUPER setup and 2 for our dual 3090 setup

We use a standard cosine decay so `cosine_decay_epochs = epochs` (30, 60, 90, 120) and `cosine_decay_alpha = 0.0`, which means learning rate is dropped to $0.0$ over $epochs$ epochs [[]](https://www.tensorflow.org/api_docs/python/tf/keras/optimizers/schedules/CosineDecay), which is a standard practice which other machine learning approaches have used [[]](https://arxiv.org/abs/2111.09883)

---

## 5. Object detection to recipe step recognition. How do we do this exactly?

---

## 6. Precise browser app structure and specification still needs to be decided
