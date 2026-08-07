Following steps are currently:

 1. some kind of brief data examination phase - looking at the output to see that the produced split matches the desired criteria for it (stratification, seeded randomness, (85/15)/(298/52) split) - agian, this ought to be brief - a few commands I can run
 2. educated guesses for hyperparameters - we probably don't want to run an actual proper hpo study at this point, but given
    1. a Nvidia Geforce GTX 1660 SUPER
    2. two Nvidia Geforce RTX 3090 GOUs

what kind of hyperparameters should we use? This ought to be answered in a `thesis_relevant/q_and_a.md` like fashion (probably best to integrate similar question between 3 and 4) So a brief writeup and actual tangible quotes from scientific literature (DOI number) or technical documentation or arxiv publications, code from the internet (github projects, ipynb notebooks, huuggingface, kaggle & the like) or if nothing better exists technical blogs (medium.com) etc. Here's the [relevant documentation of what hyperparameters are setuppable on mediapipe model maker](https://developers.google.com/edge/api/mediapipe/python/mediapipe_model_maker/object_detector/HParams)

 3. perform the actual training. "Test training" so actually starting & stopping a training process has already been completed, relevant code is in `data_and_training/devtools/tests/mediapipe_obd_training.py`. Most of this can be reused. The train and test data ought to be imported from the correct datasets & the hyperparameters ought to match whatever we decided in step 2 for the given gpu setup we have. Tha model should be exported to `data_and_training/models/ssd_plus_mobilenet_v2_l3f_TIMESTAMP/model.tflite` The training file ought to be written to `data_and_training/trainer.py`
