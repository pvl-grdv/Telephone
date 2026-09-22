//
//  AKActiveCallView.m
//  Telephone
//
//  Copyright © 2008-2016 Alexey Kuznetsov
//  Copyright © 2016-2022 64 Characters
//
//  Telephone is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Telephone is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//

#import "AKActiveCallView.h"


@implementation AKActiveCallView

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)keyDown:(NSEvent *)theEvent {
    NSString *characters = theEvent.characters;
    if (characters.length == 0) {
        [super keyDown:theEvent];
        return;
    }

    NSCharacterSet *DTMFCharacterSet =
        [NSCharacterSet characterSetWithCharactersInString:@"0123456789*#abcdrABCDR"];
    unichar firstCharacter = [characters characterAtIndex:0];

    if ([DTMFCharacterSet characterIsMember:firstCharacter] && !theEvent.isARepeat) {
        // We want to get DTMF input as text so the delegate can forward it.
        [self interpretKeyEvents:@[theEvent]];
        return;
    }

    [super keyDown:theEvent];
}

- (void)insertText:(id)aString {
    if ([[self delegate] respondsToSelector:@selector(activeCallView:didReceiveText:)]) {
        [[self delegate] activeCallView:self didReceiveText:aString];
    }
}

@end
