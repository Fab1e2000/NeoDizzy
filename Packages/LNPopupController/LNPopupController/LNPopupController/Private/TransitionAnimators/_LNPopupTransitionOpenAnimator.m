//
//  _LNPopupTransitionOpenAnimator.m
//  LNPopupController
//
//  Created by Léo Natan on 2025-03-24.
//  Copyright © 2015-2025 Léo Natan. All rights reserved.
//

#import "_LNPopupTransitionOpenAnimator.h"
#import <objc/runtime.h>

@implementation _LNPopupTransitionOpenAnimator

- (CGRect)sourceFrame
{
	return self.barArtworkFrameInWindow;
}

- (CGRect)targetFrame
{
	return [self.popupContentView.window.layer convertRect:self.transitionView.sourceLayer.bounds fromLayer:self.transitionView.sourceLayer];;
}

- (CGFloat)sourceImageAlpha
{
	return self.popupBarImageAlphaBeforeAnimation;
}

- (CGFloat)targetImageAlpha
{
	return 1.0;
}

- (UIVisualEffect *)sourceContentTransitionEffect
{
	return self.popupBarEffect;
}

- (UIVisualEffect *)targetContentTransitionEffect
{
	return self.popupContentView._currentEffect;
}

- (CGRect)sourceContentFrame
{
	return self.barContentFrame;
}

- (CGRect)targetContentFrame
{
	return [self.popupContentView.superview convertRect:self.popupContentView.bounds fromView:self.popupContentView];
}

- (LNPopupViewCorners)sourceContentCornerRadius
{
	return self.barContentCorners;
}

- (LNPopupViewCorners)targetContentCornerRadius
{
	return [LNPopupContentView cornersForContentView:self.popupContentView];
}

- (CGFloat)sourceContentAlpha
{
	return 0.0;
}

- (CGFloat)targetContentAlpha
{
	return 1.0;
}

- (CGAffineTransform)transform
{
	CGFloat ratioX = self.sourceFrame.size.width / self.targetFrame.size.width;
	CGFloat ratioY = self.sourceFrame.size.height / self.targetFrame.size.height;
	return CGAffineTransformMakeScale(ratioX, ratioY);
}

- (CGFloat)scaledBarImageViewCornerRadius
{
	return self.barArtworkCornerRadius * self.targetFrame.size.width / MAX(self.barArtworkView.bounds.size.width, 1.0);
}

- (NSShadow *)scaledBarImageViewShadow
{
	NSShadow* scaled = self.barArtworkShadow.copy;
	scaled.shadowBlurRadius = scaled.shadowBlurRadius * self.targetFrame.size.width / MAX(self.barArtworkView.bounds.size.width, 1.0);
	return scaled;
}

- (LNPopupPresentationState)targetState
{
	return LNPopupPresentationStateOpen;
}

- (void)beforeAnyAnimation
{
	[super beforeAnyAnimation];
	
	self.crossfadeView.alpha = 1.0;
	self.crossfadeView.cornerRadius = self.barArtworkCornerRadius;
}

- (void)performBeforeAdditionalAnimations
{
	[super performBeforeAdditionalAnimations];
	
	self.transitionView.sourceViewTransform = self.transform;
}

- (void)performAdditionalAnimations
{
	[super performAdditionalAnimations];
	
	self.transitionView.frame = self.targetFrame;
	self.transitionView.sourceViewTransform = CGAffineTransformIdentity;
	self.crossfadeView.cornerRadius = self.transitionView.cornerRadius;
	
	self.contentViewTransitionView.alpha = self.targetContentAlpha;
	if(self.accessoryTransitionEffectView != nil)
	{
		self.contentTransitionEffectView.effect = self.popupContentView._currentEffect;
		self.accessoryTransitionEffectView.effect = nil;
	}
}

- (void)performAdditional01Animations
{
	[super performAdditional01Animations];
	
	self.crossfadeView.alpha = 0.0;
	
	self.popupBarTransitionView.alpha = 0.0;
}

@end
