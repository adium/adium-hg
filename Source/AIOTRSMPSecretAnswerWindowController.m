//
//  AIOTRSMPSecretAnswerWindowController.m
//  Adium
//
//  Created by Thijs Alkemade on 17-10-12.
//  Copyright (c) 2012 The Adium Team. All rights reserved.
//

#import "AIOTRSMPSecretAnswerWindowController.h"

@implementation AIOTRSMPSecretAnswerWindowController

- (id)initWithQuestion:(NSString *)inQuestion from:(AIListContact *)inContact completionHandler:(void(^)(NSString *answer))inHandler
{
	if (self = [super initWithWindowNibName:@"AIOTRSMPSecretAnswerWindowController"]) {
		secretQuestion = [inQuestion retain];
		contact = [inContact retain];
		handler = Block_copy(inHandler);
	}
	
	return self;
}

- (void)dealloc
{
	[secretQuestion release];
	[contact release];
	
	[super dealloc];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
	[label_intro setStringValue:[NSString stringWithFormat:AILocalizedString(@"%@ asks you to answer the following secret question to confirm your identity:", nil), contact.UID]];
	
	NSAttributedString *question = [[[NSAttributedString alloc] initWithString:secretQuestion ?: @""] autorelease];
	
	[[field_question textStorage] setAttributedString:question];
}

- (IBAction)okay:(id)sender
{
	handler([[field_answer textStorage] string]);
	
	[self close];
	[self release];
}

- (IBAction)cancel:(id)sender
{
	handler(nil);
	
	[self close];
	[self release];
}

@end
