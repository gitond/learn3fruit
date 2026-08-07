Dataset has equal image counts per class (350) but unequal bounding box instance counts — oranges/apples pile up in images, knives/spoons don't:

```
grep -rh '<name>' data_and_training/data/l3fds/ds/train/Annotations/ | sort | uniq -c | sort -rn
```
```
2125  orange (fruit)
1068  apple
 761  bowl
 704  banana
 460  spoon
 443  knife
```

```
grep -rh '<name>' data_and_training/data/l3fds/ds/val/Annotations/ | sort | uniq -c | sort -rn
```
```
341  orange (fruit)
222  apple
159  bowl
102  banana
 94  spoon
 79  knife
```

SSD loss is per bounding box, so orange/apple get ~5× more gradient signal than knife/spoon. Transfer learning from COCO mitigates this somewhat. Expect a per-class AP gap — check eval output after training.
