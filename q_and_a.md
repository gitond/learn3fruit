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

---

## 4. Object detection to recipe step recognition. How do we do this exactly?

---

## 5. Precise browser app structure and specification still needs to be decided
