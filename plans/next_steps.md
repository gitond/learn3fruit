Coco overlap check:

 - if an image is included in the COCO dataset, we don't want it in our dataset

Filtering:

 - oiv7 and COCO both use flickr images
 - images in both datasets have a flickr url
 - Use for filtering

Todo:

 1. Update `data_and_training/devtools/SOURCES.md`

`data_and_training/devtools/validation-images-with-rotation.csv`: from https://storage.googleapis.com/openimages/2018_04/validation/validation-images-with-rotation.csv: has oiv7 val metadata. Format:

```
ImageID,Subset,OriginalURL,OriginalLandingURL,License,AuthorProfileURL,Author,Title,OriginalSize,OriginalMD5,Thumbnail300KURL,Rotation
fe600639ac5f36c1,validation,https://farm2.staticflickr.com/5612/15340259497_dd0f22ebf2_o.jpg,https://www.flickr.com/photos/118815643@N04/15340259497,https://creativecommons.org/licenses/by/2.0/,https://www.flickr.com/people/118815643@N04/,LabHacker CD,_GUT6674,242145,0jBpbNION09+r02xkTIBcA==,https://c8.staticflickr.com/6/5612/15340259497_6b4323bab9_z.jpg,
```

https://storage.googleapis.com/openimages/2018_04/train/train-images-boxable-with-rotation.csv has oiv7 train metadata in same format. undownloaded. Download when starting to use train set

`data_and_training/devtools/instances_val2017.json` has COCO2017 metadata in a very annoying very large 1 line json. Exploration: `jq 'keys' data_and_training/devtools/instances_val2017.json` prints:

```json
[
  "annotations",
  "categories",
  "images",
  "info",
  "licenses"
]
```

`jq '.images | .[:3]' data_and_training/devtools/instances_val2017.json` prints:

```json
[
  {
    "license": 4,
    "file_name": "000000397133.jpg",
    "coco_url": "http://images.cocodataset.org/val2017/000000397133.jpg",
    "height": 427,
    "width": 640,
    "date_captured": "2013-11-14 17:02:52",
    "flickr_url": "http://farm7.staticflickr.com/6116/6255196340_da26cf2c9e_z.jpg",
    "id": 397133
  },
  {
    "license": 1,
    "file_name": "000000037777.jpg",
    "coco_url": "http://images.cocodataset.org/val2017/000000037777.jpg",
    "height": 230,
    "width": 352,
    "date_captured": "2013-11-14 20:55:31",
    "flickr_url": "http://farm9.staticflickr.com/8429/7839199426_f6d48aa585_z.jpg",
    "id": 37777
  },
  {
    "license": 4,
    "file_name": "000000252219.jpg",
    "coco_url": "http://images.cocodataset.org/val2017/000000252219.jpg",
    "height": 428,
    "width": 640,
    "date_captured": "2013-11-14 22:32:02",
    "flickr_url": "http://farm4.staticflickr.com/3446/3232237447_13d84bd0a1_z.jpg",
    "id": 252219
  }
]
```

 2. Write coco overlap checker
 3. Test coco overlap checker
 4. Integrate coco overlap checker into `data_and_training/devtools/prep_data_dl.sh`
