static void EXBloomInspectorApplyNativePropsToReactTag(
    id host,
    NSNumber *reactTag,
    NSDictionary *props,
    RCTPromiseResolveBlock resolve)
{
  if (!host || ![host respondsToSelector:@selector(moduleRegistry)] || !reactTag) {
    resolve(@{@"ok": @NO, @"reason": @"invalid-args"});
    return;
  }

  BOOL forceUIKit = NO;
  NSDictionary *effectiveProps = props;
  id forceUIKitValue = props[@"__bloomInspectorForceUIKit"];
  if ([forceUIKitValue respondsToSelector:@selector(boolValue)]) {
    forceUIKit = [forceUIKitValue boolValue];
  }
  if (forceUIKit) {
    NSMutableDictionary *mutableProps = [props mutableCopy];
    [mutableProps removeObjectForKey:@"__bloomInspectorForceUIKit"];
    effectiveProps = [mutableProps copy];
    @try {
      id presenter = [host valueForKey:@"surfacePresenter"];
      if (presenter &&
          [presenter respondsToSelector:@selector(findComponentViewWithTag_DO_NOT_USE_DEPRECATED:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          UIView *view = [(RCTSurfacePresenter *)presenter
              findComponentViewWithTag_DO_NOT_USE_DEPRECATED:reactTag.integerValue];
          if (view) {
            EXBloomInspectorApplyUIKitStyleToView(view, effectiveProps, resolve);
          } else {
            EXBloomInspectorOverlayView *overlayView =
                [[EXBloomInspectorOverlayManager sharedInstance] viewController].overlayView;
            UIView *fallbackView = overlayView.selectedHitView;
            if (fallbackView) {
              EXBloomInspectorApplyUIKitStyleToView(fallbackView, effectiveProps, resolve);
            } else {
              resolve(@{
                @"ok": @NO,
                @"mode": @"uikit",
                @"reason": @"forceUIKit-no-view",
                @"reactTag": reactTag,
              });
            }
          }
        });
        return;
      }
    } @catch (__unused NSException *exception) {
      // ignore
    }
  }

  // Fabric path (no viewName needed): `RCTSurfacePresenter synchronouslyUpdateViewOnUIThread:props:`
  @try {
    id presenter = [host valueForKey:@"surfacePresenter"];
    if (presenter && [presenter respondsToSelector:@selector(synchronouslyUpdateViewOnUIThread:props:)]) {
      dispatch_async(dispatch_get_main_queue(), ^{
        UIView *view = nil;
        if ([presenter respondsToSelector:@selector(findComponentViewWithTag_DO_NOT_USE_DEPRECATED:)]) {
          view = [(RCTSurfacePresenter *)presenter
              findComponentViewWithTag_DO_NOT_USE_DEPRECATED:reactTag.integerValue];
        }
        if (!view) {
          resolve(@{
            @"ok": @NO,
            @"reactTag": reactTag,
            @"mode": @"fabric",
            @"reason": @"fabric-view-missing",
          });
          return;
        }
        [(RCTSurfacePresenter *)presenter synchronouslyUpdateViewOnUIThread:reactTag
                                                                     props:effectiveProps];
        NSDictionary *style = [effectiveProps isKindOfClass:[NSDictionary class]]
          ? (NSDictionary *)effectiveProps[@"style"]
          : nil;
        if (![style isKindOfClass:[NSDictionary class]]) {
          style = nil;
        }
        if (style) {
          EXBloomInspectorApplyTextStyleToView(view, style);
        }
        NSString *textOverride = EXBloomInspectorExtractTextOverride(effectiveProps);
        if (textOverride) {
          EXBloomInspectorApplyTextOverrideToView(view, textOverride);
        }
        resolve(@{
          @"ok": @YES,
          @"reactTag": reactTag,
          @"mode": @"fabric",
          @"componentViewClass": NSStringFromClass([view class]),
          @"componentViewFrame": EXBloomInspectorRectInfo(view.frame),
          @"componentViewBounds": EXBloomInspectorRectInfo(view.bounds),
          @"componentViewHidden": @(view.hidden),
          @"componentViewAlpha": @(view.alpha),
          @"componentViewBackgroundColor": EXBloomInspectorColorToString(view.backgroundColor) ?: [NSNull null],
        });
      });
      return;
    }
  } @catch (__unused NSException *exception) {
    // ignore
  }

  id moduleRegistry = [host moduleRegistry];
  RCTUIManager *uiManager = [moduleRegistry moduleForName:"UIManager"];
  if (!uiManager) {
    uiManager = [moduleRegistry moduleForName:"RCTUIManager"];
  }
  if (!uiManager) {
    resolve(@{@"ok": @NO, @"reason": @"no-uiManager", @"reactTag": reactTag});
    return;
  }

  dispatch_queue_t uiQueue = [uiManager methodQueue];
  if (!uiQueue) {
    resolve(@{@"ok": @NO, @"reason": @"no-uiManager-queue", @"reactTag": reactTag});
    return;
  }

  dispatch_async(uiQueue, ^{
    if (forceUIKit && [uiManager respondsToSelector:@selector(viewForReactTag:)]) {
      UIView *view = [uiManager viewForReactTag:reactTag];
      dispatch_async(dispatch_get_main_queue(), ^{
        if (view) {
          EXBloomInspectorApplyUIKitStyleToView(view, effectiveProps, resolve);
        } else {
          EXBloomInspectorOverlayView *overlayView =
              [[EXBloomInspectorOverlayManager sharedInstance] viewController].overlayView;
          UIView *fallbackView = overlayView.selectedHitView;
          if (fallbackView) {
            EXBloomInspectorApplyUIKitStyleToView(fallbackView, effectiveProps, resolve);
          } else {
            resolve(@{
              @"ok": @NO,
              @"mode": @"uikit",
              @"reason": @"forceUIKit-no-view",
              @"reactTag": reactTag,
            });
          }
        }
      });
      return;
    }
    if (![uiManager respondsToSelector:@selector(viewNameForReactTag:)] ||
        ![uiManager respondsToSelector:@selector(synchronouslyUpdateViewOnUIThread:viewName:props:)]) {
      dispatch_async(dispatch_get_main_queue(), ^{
        resolve(@{@"ok": @NO, @"reason": @"missing-selectors", @"reactTag": reactTag});
      });
      return;
    }

    NSString *viewName = [uiManager viewNameForReactTag:reactTag];
    if (!viewName) {
      dispatch_async(dispatch_get_main_queue(), ^{
        resolve(@{@"ok": @NO, @"reason": @"viewName-missing", @"reactTag": reactTag});
      });
      return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      [uiManager synchronouslyUpdateViewOnUIThread:reactTag viewName:viewName props:effectiveProps];
      resolve(@{@"ok": @YES, @"reactTag": reactTag, @"viewName": viewName, @"mode": @"native"});
    });
  });
}

static UIColor *EXBloomInspectorColorFromString(NSString *value)
{
  if (!value || ![value isKindOfClass:[NSString class]]) {
    return nil;
  }
  NSString *lower = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
  if ([lower hasPrefix:@"#"]) {
    NSString *hex = [lower substringFromIndex:1];
    unsigned int a = 255, r = 0, g = 0, b = 0;
    if (hex.length == 6) {
      NSScanner *scanner = [NSScanner scannerWithString:hex];
      unsigned int rgb = 0;
      if (![scanner scanHexInt:&rgb]) {
        return nil;
      }
      r = (rgb >> 16) & 0xFF;
      g = (rgb >> 8) & 0xFF;
      b = rgb & 0xFF;
    } else if (hex.length == 8) {
      NSScanner *scanner = [NSScanner scannerWithString:hex];
      unsigned int argb = 0;
      if (![scanner scanHexInt:&argb]) {
        return nil;
      }
      a = (argb >> 24) & 0xFF;
      r = (argb >> 16) & 0xFF;
      g = (argb >> 8) & 0xFF;
      b = argb & 0xFF;
    } else {
      return nil;
    }
    return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:a / 255.0];
  }
  if ([lower isEqualToString:@"red"]) return UIColor.redColor;
  if ([lower isEqualToString:@"green"]) return UIColor.greenColor;
  if ([lower isEqualToString:@"blue"]) return UIColor.blueColor;
  if ([lower isEqualToString:@"black"]) return UIColor.blackColor;
  if ([lower isEqualToString:@"white"]) return UIColor.whiteColor;
  if ([lower isEqualToString:@"gray"] || [lower isEqualToString:@"grey"]) return UIColor.grayColor;
  if ([lower isEqualToString:@"clear"] || [lower isEqualToString:@"transparent"]) return UIColor.clearColor;
  return nil;
}

static UIColor *EXBloomInspectorColorFromNumber(id value)
{
  if (!value || ![value respondsToSelector:@selector(unsignedIntValue)]) {
    return nil;
  }
  uint32_t argb = (uint32_t)[(NSNumber *)value unsignedIntValue];
  CGFloat alpha = ((argb >> 24) & 0xFF) / 255.0;
  CGFloat red = ((argb >> 16) & 0xFF) / 255.0;
  CGFloat green = ((argb >> 8) & 0xFF) / 255.0;
  CGFloat blue = (argb & 0xFF) / 255.0;
  return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

static NSTextAlignment EXBloomInspectorTextAlignmentFromString(NSString *value)
{
  if (!value || ![value isKindOfClass:[NSString class]]) {
    return NSTextAlignmentNatural;
  }
  NSString *lower = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
  if ([lower isEqualToString:@"left"]) return NSTextAlignmentLeft;
  if ([lower isEqualToString:@"right"]) return NSTextAlignmentRight;
  if ([lower isEqualToString:@"center"]) return NSTextAlignmentCenter;
  if ([lower isEqualToString:@"justify"]) return NSTextAlignmentJustified;
  return NSTextAlignmentNatural;
}

static NSString *EXBloomInspectorColorToString(UIColor *color)
{
  if (!color) {
    return nil;
  }
  CGFloat r = 0, g = 0, b = 0, a = 0;
  if (![color getRed:&r green:&g blue:&b alpha:&a]) {
    return [color description];
  }
  return [NSString stringWithFormat:@"rgba(%d,%d,%d,%.3f)",
          (int)roundf(r * 255.0f),
          (int)roundf(g * 255.0f),
          (int)roundf(b * 255.0f),
          a];
}

static NSAttributedString *EXBloomInspectorCopyAttributedText(UIView *view)
{
  if (!view) {
    return nil;
  }
  id value = nil;
  @try {
    if ([view respondsToSelector:@selector(attributedText)]) {
      value = [view valueForKey:@"attributedText"];
      if ([value isKindOfClass:[NSAttributedString class]]) {
        return (NSAttributedString *)value;
      }
    }
  } @catch (__unused NSException *exception) {}
  @try {
    value = [view valueForKey:@"attributedString"];
    if ([value isKindOfClass:[NSAttributedString class]]) {
      return (NSAttributedString *)value;
    }
  } @catch (__unused NSException *exception) {}
  @try {
    value = [view valueForKey:@"_attributedString"];
    if ([value isKindOfClass:[NSAttributedString class]]) {
      return (NSAttributedString *)value;
    }
  } @catch (__unused NSException *exception) {}
  @try {
    value = [view valueForKey:@"textStorage"];
    if ([value isKindOfClass:[NSTextStorage class]]) {
      return [(NSTextStorage *)value copy];
    }
  } @catch (__unused NSException *exception) {}
  return nil;
}

static BOOL EXBloomInspectorApplyAttributedText(UIView *view, NSAttributedString *value)
{
  if (!view || !value) {
    return NO;
  }
  @try {
    if ([view respondsToSelector:@selector(setAttributedText:)]) {
      [view setValue:value forKey:@"attributedText"];
      return YES;
    }
  } @catch (__unused NSException *exception) {}
  @try {
    [view setValue:value forKey:@"attributedString"];
    return YES;
  } @catch (__unused NSException *exception) {}
  @try {
    [view setValue:value forKey:@"_attributedString"];
    return YES;
  } @catch (__unused NSException *exception) {}
  @try {
    id layoutManager = [view valueForKey:@"_layoutManager"];
    if (!layoutManager) {
      layoutManager = [view valueForKey:@"textLayoutManager"];
    }
    if (layoutManager) {
      if ([layoutManager respondsToSelector:@selector(setAttributedString:)]) {
        [layoutManager setValue:value forKey:@"attributedString"];
        return YES;
      }
    }
  } @catch (__unused NSException *exception) {}
  @try {
    id storage = [view valueForKey:@"textStorage"];
    if ([storage isKindOfClass:[NSTextStorage class]]) {
      [(NSTextStorage *)storage setAttributedString:value];
      return YES;
    }
  } @catch (__unused NSException *exception) {}
  return NO;
}

static void EXBloomInspectorForceRedraw(UIView *view)
{
  if (!view) {
    return;
  }
  [view setNeedsDisplay];
  [view setNeedsLayout];
  [view invalidateIntrinsicContentSize];
  CALayer *layer = view.layer;
  [layer setNeedsDisplay];
  if (layer.sublayers.count) {
    for (CALayer *sublayer in layer.sublayers) {
      [sublayer setNeedsDisplay];
    }
  }
  if (view.superview) {
    [view.superview setNeedsLayout];
    [view.superview layoutIfNeeded];
  }
}

static NSString *EXBloomInspectorGetPlainTextFromView(UIView *view)
{
  if (!view) {
    return nil;
  }
  if ([view isKindOfClass:[UILabel class]]) {
    return ((UILabel *)view).text;
  }
  if ([view isKindOfClass:[UITextView class]]) {
    return ((UITextView *)view).text;
  }
  if ([view isKindOfClass:[UITextField class]]) {
    return ((UITextField *)view).text;
  }
  if ([view isKindOfClass:[UIButton class]]) {
    return [(UIButton *)view titleForState:UIControlStateNormal];
  }
  NSAttributedString *attr = EXBloomInspectorCopyAttributedText(view);
  if (attr.string.length) {
    return attr.string;
  }
  @try {
    id value = [view valueForKey:@"text"];
    if ([value isKindOfClass:[NSString class]]) {
      return (NSString *)value;
    }
  } @catch (__unused NSException *exception) {}
  return nil;
}

static NSDictionary *EXBloomInspectorRectInfo(CGRect rect)
{
  return @{
    @"x": @(rect.origin.x),
    @"y": @(rect.origin.y),
    @"width": @(rect.size.width),
    @"height": @(rect.size.height),
  };
}

static UIView *EXBloomInspectorFindTextView(UIView *view)
{
  if (!view) {
    return nil;
  }
  if ([view isKindOfClass:[UILabel class]] ||
      [view isKindOfClass:[UITextView class]] ||
      [view isKindOfClass:[UITextField class]]) {
    return view;
  }
  for (UIView *subview in view.subviews) {
    UIView *match = EXBloomInspectorFindTextView(subview);
    if (match) {
      return match;
    }
  }
  return nil;
}

static NSString *EXBloomInspectorExtractTextOverride(NSDictionary *props)
{
  if (!props || ![props isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  id value = props[@"children"];
  if (!value) {
    value = props[@"text"];
  }
  if (!value) {
    value = props[@"value"];
  }
  if ([value isKindOfClass:[NSString class]]) {
    return (NSString *)value;
  }
  if ([value isKindOfClass:[NSNumber class]]) {
    return [(NSNumber *)value stringValue];
  }
  if ([value isKindOfClass:[NSArray class]]) {
    NSMutableString *joined = [NSMutableString string];
    for (id entry in (NSArray *)value) {
      if ([entry isKindOfClass:[NSString class]]) {
        [joined appendString:entry];
      } else if ([entry isKindOfClass:[NSNumber class]]) {
        [joined appendString:[(NSNumber *)entry stringValue]];
      }
    }
    return joined.length ? [joined copy] : nil;
  }
  return nil;
}

static BOOL EXBloomInspectorApplyParagraphTextStyle(UIView *view, NSDictionary *style)
{
  if (!view || ![style isKindOfClass:[NSDictionary class]]) {
    return NO;
  }
  NSString *className = NSStringFromClass([view class]);
  if (![className containsString:@"Paragraph"] && ![className containsString:@"Text"]) {
    return NO;
  }

  NSAttributedString *existing = EXBloomInspectorCopyAttributedText(view);
  NSString *baseText = existing ? existing.string : EXBloomInspectorGetPlainTextFromView(view);
  if (!baseText || !baseText.length) {
    id fallbackValue = style[@"__bloomInspectorFallbackText"];
    if ([fallbackValue isKindOfClass:[NSString class]]) {
      baseText = (NSString *)fallbackValue;
    } else if ([fallbackValue isKindOfClass:[NSNumber class]]) {
      baseText = [(NSNumber *)fallbackValue stringValue];
    }
  }
  if (!baseText) {
    baseText = @"";
  }

  NSMutableAttributedString *mutableText = existing
    ? [existing mutableCopy]
    : [[NSMutableAttributedString alloc] initWithString:baseText];

  NSRange range = NSMakeRange(0, mutableText.length);
  if (range.length == 0) {
    return NO;
  }

  UIColor *textColor = nil;
  id colorValue = style[@"color"];
  if ([colorValue isKindOfClass:[NSString class]]) {
    textColor = EXBloomInspectorColorFromString(colorValue);
  } else if ([colorValue isKindOfClass:[NSNumber class]]) {
    textColor = EXBloomInspectorColorFromNumber(colorValue);
  }
  if (textColor) {
    [mutableText addAttribute:NSForegroundColorAttributeName value:textColor range:range];
  }

  NSNumber *fontSize = [style[@"fontSize"] isKindOfClass:[NSNumber class]] ? style[@"fontSize"] : nil;
  if (fontSize) {
    UIFont *font = [mutableText attribute:NSFontAttributeName atIndex:0 effectiveRange:nil];
    CGFloat size = [fontSize floatValue];
    if (size > 0) {
      UIFont *nextFont = font ? [font fontWithSize:size] : [UIFont systemFontOfSize:size];
      [mutableText addAttribute:NSFontAttributeName value:nextFont range:range];
    }
  }

  NSString *textAlign = [style[@"textAlign"] isKindOfClass:[NSString class]] ? style[@"textAlign"] : nil;
  if (textAlign) {
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = EXBloomInspectorTextAlignmentFromString(textAlign);
    [mutableText addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:range];
  }

  NSString *decoration = [style[@"textDecorationLine"] isKindOfClass:[NSString class]]
                             ? style[@"textDecorationLine"]
                             : nil;
  if (decoration && [decoration containsString:@"underline"]) {
    UIColor *underlineColor = nil;
    id underlineValue = style[@"textDecorationColor"];
    if ([underlineValue isKindOfClass:[NSString class]]) {
      underlineColor = EXBloomInspectorColorFromString(underlineValue);
    } else if ([underlineValue isKindOfClass:[NSNumber class]]) {
      underlineColor = EXBloomInspectorColorFromNumber(underlineValue);
    }
    [mutableText addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:range];
    if (underlineColor) {
      [mutableText addAttribute:NSUnderlineColorAttributeName value:underlineColor range:range];
    }
  }
  if (!EXBloomInspectorApplyAttributedText(view, mutableText)) {
    return NO;
  }
  EXBloomInspectorForceRedraw(view);
  return YES;
}

static BOOL EXBloomInspectorApplyTextOverrideToView(UIView *view, NSString *textValue)
{
  if (!view || ![textValue isKindOfClass:[NSString class]]) {
    return NO;
  }

  if ([view isKindOfClass:[UILabel class]]) {
    ((UILabel *)view).text = textValue;
    return YES;
  }
  if ([view isKindOfClass:[UITextView class]]) {
    ((UITextView *)view).text = textValue;
    return YES;
  }
  if ([view isKindOfClass:[UITextField class]]) {
    ((UITextField *)view).text = textValue;
    return YES;
  }
  if ([view isKindOfClass:[UIButton class]]) {
    [(UIButton *)view setTitle:textValue forState:UIControlStateNormal];
    return YES;
  }

  NSString *className = NSStringFromClass([view class]);
  if ([className containsString:@"Paragraph"] || [className containsString:@"Text"]) {
    NSAttributedString *existing = EXBloomInspectorCopyAttributedText(view);
    NSDictionary *attributes = nil;
    if (existing.length > 0) {
      attributes = [existing attributesAtIndex:0 effectiveRange:nil];
    }
    NSMutableAttributedString *mutableText = attributes
      ? [[NSMutableAttributedString alloc] initWithString:textValue attributes:attributes]
      : [[NSMutableAttributedString alloc] initWithString:textValue];
    if (!EXBloomInspectorApplyAttributedText(view, mutableText)) {
      return NO;
    }
    EXBloomInspectorForceRedraw(view);
    return YES;
  }

  UIView *textView = EXBloomInspectorFindTextView(view);
  if (textView && textView != view) {
    return EXBloomInspectorApplyTextOverrideToView(textView, textValue);
  }
  return NO;
}

static void EXBloomInspectorApplyTextStyleToView(UIView *view, NSDictionary *style)
{
  if (!view || ![style isKindOfClass:[NSDictionary class]]) {
    return;
  }
  if (EXBloomInspectorApplyParagraphTextStyle(view, style)) {
    return;
  }
  UIView *textView = EXBloomInspectorFindTextView(view);
  if (!textView) {
    return;
  }
  UIColor *textColor = nil;
  id colorValue = style[@"color"];
  if ([colorValue isKindOfClass:[NSString class]]) {
    textColor = EXBloomInspectorColorFromString(colorValue);
  } else if ([colorValue isKindOfClass:[NSNumber class]]) {
    textColor = EXBloomInspectorColorFromNumber(colorValue);
  }
  if (textColor && [textView respondsToSelector:@selector(setTextColor:)]) {
    [(id)textView setTextColor:textColor];
  }
  NSString *textAlign = [style[@"textAlign"] isKindOfClass:[NSString class]] ? style[@"textAlign"] : nil;
  if (textAlign && [textView respondsToSelector:@selector(setTextAlignment:)]) {
    [(id)textView setTextAlignment:EXBloomInspectorTextAlignmentFromString(textAlign)];
  }
  NSNumber *fontSize = [style[@"fontSize"] isKindOfClass:[NSNumber class]] ? style[@"fontSize"] : nil;
  if (fontSize) {
    UIFont *font = nil;
    id fontValue = nil;
    @try {
      fontValue = [textView valueForKey:@"font"];
    } @catch (__unused NSException *exception) {
      fontValue = nil;
    }
    if ([fontValue isKindOfClass:[UIFont class]]) {
      font = (UIFont *)fontValue;
    }
    CGFloat size = [fontSize floatValue];
    if (size > 0) {
      UIFont *nextFont = font ? [font fontWithSize:size] : [UIFont systemFontOfSize:size];
      if ([textView respondsToSelector:@selector(setFont:)]) {
        [(id)textView setFont:nextFont];
      }
    }
  }
  NSString *decoration = [style[@"textDecorationLine"] isKindOfClass:[NSString class]]
                             ? style[@"textDecorationLine"]
                             : nil;
  if (decoration && [decoration containsString:@"underline"]) {
    UIColor *underlineColor = nil;
    id underlineValue = style[@"textDecorationColor"];
    if ([underlineValue isKindOfClass:[NSString class]]) {
      underlineColor = EXBloomInspectorColorFromString(underlineValue);
    } else if ([underlineValue isKindOfClass:[NSNumber class]]) {
      underlineColor = EXBloomInspectorColorFromNumber(underlineValue);
    }
    NSAttributedString *existing = EXBloomInspectorCopyAttributedText(textView);
    NSString *text = nil;
    if (!existing && [textView respondsToSelector:@selector(text)]) {
      text = [(id)textView text];
    }
    if (!existing && !text) {
      return;
    }
    NSMutableAttributedString *mutableText =
        existing ? [existing mutableCopy] : [[NSMutableAttributedString alloc] initWithString:text ?: @""];
    NSRange range = NSMakeRange(0, mutableText.length);
    if (range.length > 0) {
      [mutableText addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:range];
      if (underlineColor) {
        [mutableText addAttribute:NSUnderlineColorAttributeName value:underlineColor range:range];
      }
      if (textColor) {
        [mutableText addAttribute:NSForegroundColorAttributeName value:textColor range:range];
      }
    }
    if ([textView respondsToSelector:@selector(setAttributedText:)]) {
      [(id)textView setAttributedText:mutableText];
    }
  }
}

static void EXBloomInspectorApplyUIKitStyleToView(UIView *view, NSDictionary *props, RCTPromiseResolveBlock resolve)
{
  if (!view) {
    resolve(@{@"ok": @NO, @"reason": @"no-hitView", @"mode": @"uikit"});
    return;
  }

  NSDictionary *style = props[@"style"];
  if (![style isKindOfClass:[NSDictionary class]]) {
    style = props;
  }
  NSString *textOverride = EXBloomInspectorExtractTextOverride(props);
  BOOL hasStyle = [style isKindOfClass:[NSDictionary class]] && style.count > 0;
  if (!hasStyle && !textOverride) {
    resolve(@{@"ok": @NO, @"reason": @"empty-style", @"mode": @"uikit"});
    return;
  }
  if (!hasStyle) {
    style = @{};
  }

  id bg = style[@"backgroundColor"];
  if ([bg isKindOfClass:[NSString class]]) {
    UIColor *color = EXBloomInspectorColorFromString(bg);
    if (color) {
      view.backgroundColor = color;
      view.layer.backgroundColor = color.CGColor;
      view.opaque = YES;
      UIView *contentView = nil;
      if ([view respondsToSelector:@selector(contentView)]) {
        @try {
          contentView = [view valueForKey:@"contentView"];
        } @catch (__unused NSException *exception) {
          contentView = nil;
        }
      }
      if ([contentView isKindOfClass:[UIView class]]) {
        contentView.backgroundColor = color;
        contentView.layer.backgroundColor = color.CGColor;
        contentView.opaque = YES;
      } else if ([NSStringFromClass([view class]) containsString:@"Paragraph"]) {
        UIView *firstSubview = view.subviews.count ? view.subviews.firstObject : nil;
        if ([firstSubview isKindOfClass:[UIView class]]) {
          firstSubview.backgroundColor = color;
          firstSubview.layer.backgroundColor = color.CGColor;
          firstSubview.opaque = YES;
        }
      }
    }
  } else if ([bg isKindOfClass:[NSNumber class]]) {
    UIColor *color = EXBloomInspectorColorFromNumber(bg);
    if (color) {
      view.backgroundColor = color;
      view.layer.backgroundColor = color.CGColor;
      view.opaque = YES;
    }
  }
  id opacity = style[@"opacity"];
  if ([opacity isKindOfClass:[NSNumber class]]) {
    view.alpha = [(NSNumber *)opacity floatValue];
  }
  id hidden = style[@"display"];
  if ([hidden isKindOfClass:[NSString class]] && [hidden isEqualToString:@"none"]) {
    view.hidden = YES;
  }
  id borderColor = style[@"borderColor"];
  if ([borderColor isKindOfClass:[NSString class]]) {
    UIColor *color = EXBloomInspectorColorFromString(borderColor);
    if (color) {
      view.layer.borderColor = color.CGColor;
    }
  } else if ([borderColor isKindOfClass:[NSNumber class]]) {
    UIColor *color = EXBloomInspectorColorFromNumber(borderColor);
    if (color) {
      view.layer.borderColor = color.CGColor;
    }
  }
  id borderWidth = style[@"borderWidth"];
  if ([borderWidth isKindOfClass:[NSNumber class]]) {
    view.layer.borderWidth = [(NSNumber *)borderWidth floatValue];
  }
  id borderRadius = style[@"borderRadius"];
  if ([borderRadius isKindOfClass:[NSNumber class]]) {
    view.layer.cornerRadius = [(NSNumber *)borderRadius floatValue];
    view.layer.masksToBounds = YES;
  }
  EXBloomInspectorApplyTextStyleToView(view, style);
  if (textOverride) {
    EXBloomInspectorApplyTextOverrideToView(view, textOverride);
  }
  id tint = style[@"tintColor"];
  if ([tint isKindOfClass:[NSString class]]) {
    UIColor *color = EXBloomInspectorColorFromString(tint);
    if (color) {
      view.tintColor = color;
    }
  } else if ([tint isKindOfClass:[NSNumber class]]) {
    UIColor *color = EXBloomInspectorColorFromNumber(tint);
    if (color) {
      view.tintColor = color;
    }
  }
  id textColor = style[@"color"];
  if ([textColor isKindOfClass:[NSString class]] || [textColor isKindOfClass:[NSNumber class]]) {
    UIColor *color = [textColor isKindOfClass:[NSString class]]
      ? EXBloomInspectorColorFromString(textColor)
      : EXBloomInspectorColorFromNumber(textColor);
    if (color) {
      if ([view isKindOfClass:[UILabel class]]) {
        ((UILabel *)view).textColor = color;
      } else if ([view isKindOfClass:[UITextView class]]) {
        ((UITextView *)view).textColor = color;
      } else if ([view isKindOfClass:[UITextField class]]) {
        ((UITextField *)view).textColor = color;
      } else if ([view isKindOfClass:[UIButton class]]) {
        [(UIButton *)view setTitleColor:color forState:UIControlStateNormal];
      }
    }
  }

  resolve(@{
    @"ok": @YES,
    @"mode": @"uikit",
    @"componentViewClass": NSStringFromClass([view class]),
    @"componentViewFrame": EXBloomInspectorRectInfo(view.frame),
    @"componentViewBounds": EXBloomInspectorRectInfo(view.bounds),
    @"componentViewHidden": @(view.hidden),
    @"componentViewAlpha": @(view.alpha),
    @"componentViewBackgroundColor": EXBloomInspectorColorToString(view.backgroundColor) ?: [NSNull null],
  });
}
