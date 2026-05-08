Okay so here's briefly what the next steps are:

 1. Download `mediapipe_model_maker` and the already pretrained `MOBILENET_V2` model they have. Try to run inference with some test image. Here's how inference should work:
    - You cannot directly run inference on `mediapipe_model_maker`
    - model needs to be trained & exported first
    - "But we want to access the pre-trained weights to test the model working before we do a real training process"
    - Probably best to just run a "dummy training process" with a dummy dataset
    - 2 images, VOC format, basically any content
    - basically won't affect the pre trained weights
    - basically runs instantly
    - export to `.tflite`, test using `mediapipe` `ObjectDetector`

Check out: input format, output format. Successful if: inference runs. So nn produces an output where an object is succesfully detected. Since this nn is pretrained with coco it should be able to detect any object from a coco class. Theoretically the input image could be any image that has such an object.

 2. The data gathering and preprocessing stage stage. According to `q_and_a.md` we want to gather 350 images per category. Data categories are listed at: **`README.md` -> Implementation stages -> Stage 1: Data Gathering -> Data categories**. A single image may belong to multiple categories (if an image has an apple and a knife in it is considered both an "apple" image and a "knife" image. Let there only be one image with both an apple and a knife. In this case:
    - there are a total of 350 apple images. $|Apple| = 350$
    - there are a total of 350 knife images. $|Knife| = 350$
    - there is a 1 image overlap between apple and knife $|Apple \cap Knife| = 1$
    - so the total amount of images is $|Apple \cup Knife| = |Apple|+|Knife|-|Apple \cap Knife| = 699$

Data displaying tools have to be developed to:

   - make sure that for any given category $c_i, |c_i| = 350$ even when $|c_1 \ cup c_2 \cup ... \cup c_n| < 350n$
      - Remember: $|c_1 \ cup c_2 \cup ... \cup c_n| < 350n$ is a good thing. Images with multiple categories ensure that the tracking works with objects from mulriple categories at a time!
    - to render the images together with the bounding boxes so that we can quickly visually determine whether: 
      - Our raw data is correct (no problems with data quality etc)
      - Our output is all right

Data preprocessing means that all data gets converted to a format that our nn can use as a learning input. `mediapipe_model_maker` uses something called the **PASCAL VOC format** where the dataset file structure is set up like this:
 
```
<dataset_dir>/
  data/
    <file0>.<jpg/jpeg>
    ...
  Annotations/
    <file0>.xml
    ...
```

And annotation datafiles (`<file0>.xml`) have the following structure:

```xml
<annotation>
  <filename>file0.jpg</filename>
  <object>
    <name>kangaroo</name>
    <bndbox>
      <xmin>233</xmin>
      <ymin>89</ymin>
      <xmax>386</xmax>
      <ymax>262</ymax>
    </bndbox>
  </object>
  <object>
    ...
  </object>
  ...
</annotation>
```

We also need a separate train and val set for training. From the gathered images, we probably want 298 train images and 52 val images.

> we maintained an 85% of the generated images for pretraining and reserved the remaining 15% for validation.

Paiano et al., *Transfer learning with generative models for object detection on limited datasets*, University of Florence, arXiv:2402.06784 · [arXiv](https://arxiv.org/html/2402.06784v1) 

We want to set up `data_and_training/data_display`, `data_and_training/data_download`, `data_and_training/data_pipeline.sh`, `data_and_training/data_preprocess` to automatize as much as we can from this process.

 3. Attempt training (fine-tuning) with `mediapipe_model_maker`. Make sure trained model inference works at an acceptable quality
    - works no problem? good. move on to browser inference testing & AR-app development
    - buggy? try to debug as best as you can
    - doesn't work? plan 2: `qfgaohao/pytorch-ssd` has a pytorch implementation of *SSD + MobileNet-v2* (plus pretrained checkpoints). try what you can achieve with this. Note: may need to redo initial inference tests & data pipeline.
