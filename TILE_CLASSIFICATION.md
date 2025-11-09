# Tile classification model

## Requirements

 - Should easily be trained on small amount of training data (300 pictures + augmentation)
 - Should work well on 64x64 or 128x128 images 
 
## AI model
### MobileNet V2 
 - Simpler architecture - No attention mechanisms means fewer parameters to overfit
 - Well-established - Extensive pretrained weights available, well-tested for transfer learning
 - Faster training - Simpler forward/backward passes
 - Better regularization - Less model complexity = less prone to overfitting on small data
 - Proven track record - Widely used in transfer learning scenarios with excellent results

### EfficientNet B0 (Alternative to MobileNet V2)
 - More accurate than MobileNet V2
 - Inference time longer
 - More power usage
 - Could work as an alternative to MobileNet V2
