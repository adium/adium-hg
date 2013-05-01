/*
 * Adium is the legal property of its developers, whose names are listed in the copyright file included
 * with this source distribution.
 *
 * This program is free software; you can redistribute it and/or modify it under the terms of the GNU
 * General Public License as published by the Free Software Foundation; either version 2 of the License,
 * or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
 * the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
 * Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along with this program; if not,
 * write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */

#import "AIGroupChat.h"
#import "AIContactControllerProtocol.h"
#import "AIListContact.h"
#import "AIListObject.h"
#import "AIServiceIcons.h"
#import "AIUserIcons.h"
#import "AIContentTopic.h"
#import "AIContentControllerProtocol.h"
#import "AIAttributedStringAdditions.h"
#import "AIChatControllerProtocol.h"
#import "AIContactObserverManager.h"
#import "AIContactHidingController.h"
#import "AIArrayAdditions.h"
#import "AIService.h"

@interface AIGroupChat ()

- (void)contentObjectAdded:(NSNotification *)notification;

@end

@implementation AIGroupChat

static int nextChatNumber = 0;

@synthesize lastMessageDate, showJoinLeave;

- (id)initForAccount:(AIAccount *)inAccount
{
    if ((self = [super initForAccount:inAccount])) {
        showJoinLeave = YES;
		expanded = YES;
        participatingNicks = [[NSMutableArray alloc] init];
		participatingNicksFlags = [[NSMutableDictionary alloc] init];
		participatingNicksContacts = [[NSMutableDictionary alloc] init];

        
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(contentObjectAdded:)
													 name:Content_ContentObjectAdded
												   object:self];
    }
    
    return self;
}

- (void)dealloc
{
	[topic release]; [topicSetter release];
    
	[self removeAllParticipatingContactsSilently];
    
    [lastMessageDate release];
	[participatingNicks release];
	[participatingNicksFlags release];
	[participatingNicksContacts release];
    
    [super dealloc];
}

- (NSImage *)chatImage
{
    AIListContact 	*listObject = nil;
	NSImage			*image = nil;
    
    listObject = (AIListContact *)[adium.contactController existingBookmarkForChat:self];
    
	if (listObject) {
		image = listObject.parentContact.userIcon;
		if (!image) image = [AIServiceIcons serviceIconForObject:listObject type:AIServiceIconLarge direction:AIIconNormal];
	} else {
		image = [AIServiceIcons serviceIconForObject:self.account type:AIServiceIconLarge direction:AIIconNormal];
	}
    
	return image;
}

//lil image
- (NSImage *)chatMenuImage
{
	AIListObject 	*listObject = nil;
	NSImage			*chatMenuImage = nil;
	
	listObject = (AIListContact *)[adium.contactController existingBookmarkForChat:self];
    
	if (listObject) {
		chatMenuImage = [AIUserIcons menuUserIconForObject:listObject];
	} else {
		chatMenuImage = [AIServiceIcons serviceIconForObject:account
														type:AIServiceIconSmall
												   direction:AIIconNormal];
	}
    
	return chatMenuImage;
}

- (void)object:(id)inObject didChangeValueForProperty:(NSString *)key notify:(NotifyTiming)notify
{
	//If our unviewed content changes or typing status changes, and we have a single list object,
	//apply the change to that object as well so it can be cleanly reflected in the contact list.
	if ([key isEqualToString:KEY_UNVIEWED_CONTENT] ||
		[key isEqualToString:KEY_TYPING]) {
		AIListObject	*listObject = nil;
		
		listObject = (AIListContact *)[adium.contactController existingBookmarkForChat:self];
		
		if (listObject) [listObject setValue:[self valueForProperty:key] forProperty:key notify:notify];
	}
	
	[super object:inObject didChangeValueForProperty:key notify:notify];
}

AIGroupChatFlags highestFlag(AIGroupChatFlags flags)
{
	if ((flags & AIGroupChatFounder) == AIGroupChatFounder)
		return AIGroupChatFounder;
	
	if ((flags & AIGroupChatOp) == AIGroupChatOp)
		return AIGroupChatOp;
	
	if ((flags & AIGroupChatHalfOp) == AIGroupChatHalfOp)
		return AIGroupChatHalfOp;
	
	if ((flags & AIGroupChatVoice) == AIGroupChatVoice)
		return AIGroupChatVoice;
	
	return AIGroupChatNone;
}

- (AIListContact *)listObject
{
    return nil;
}

- (NSString *)uniqueChatID
{
	if (!uniqueChatID) {
        uniqueChatID = [[NSString alloc] initWithFormat:@"%@.%i", self.name, nextChatNumber++];
        
		if (!uniqueChatID) {
			uniqueChatID = [[NSString alloc] initWithFormat:@"UnknownGroupChat.%i", nextChatNumber++];
			NSLog(@"Warning: Unknown group chat %p",self);
		}
	}
    
	return uniqueChatID;
}

- (AIChatSendingAbilityType)messageSendingAbility
{
	AIChatSendingAbilityType sendingAbilityType;
    
    if (self.account.online) {
        //XXX Liar!
        sendingAbilityType = AIChatCanSendMessageNow;
    } else {
        sendingAbilityType = AIChatCanNotSendMessage;
    }
	
	return sendingAbilityType;
}

#pragma mark Group Chats

/*!
 * @brief Does this chat support topics?
 */
- (BOOL)supportsTopic
{
	return account.groupChatsSupportTopic;
}

/*!
 * @brief Update the topic.
 */
- (void)updateTopic:(NSString *)inTopic withSource:(NSString *)nick
{
	NSParameterAssert([nick isKindOfClass:[NSString class]]);
	
	AIListContact *contact = [self contactForNick:nick];
	
	[self setValue:inTopic forProperty:KEY_TOPIC notify:NotifyNow];
	
	[self setValue:nick forProperty:KEY_TOPIC_SETTER notify:NotifyNow];
	
	// Apply the new topic to the message view
	AIContentTopic *contentTopic = [AIContentTopic topicInChat:self
													withSource:contact
													sourceNick:nick
												   destination:nil
														  date:[NSDate date]
													   message:[NSAttributedString stringWithString:[self valueForProperty:KEY_TOPIC] ?: @""]];
	
	// The content controller has huge problems with blank messages being let through.
	if (![[self valueForProperty:KEY_TOPIC] length]) {
		contentTopic.message = CONTENT_TOPIC_MESSAGE_ACTUALLY_EMPTY;
		contentTopic.actuallyBlank = YES;
	}
	
	[adium.contentController receiveContentObject:contentTopic];
}

/*!
 * @brief Set the chat's topic, telling the account to update it.
 */
- (void)setTopic:(NSString *)inTopic
{
	if (self.supportsTopic) {
		// We mess with the topic, replacing nbsp with spaces; make sure we're not setting an identical one other than this.
		NSString *tempTopic = [[self valueForProperty:KEY_TOPIC] stringByReplacingOccurrencesOfString:@"\u00A0" withString:@" "];
		if ([tempTopic isEqualToString:inTopic]) {
			AILogWithSignature(@"Not setting topic for %@, already the same.", self);
		} else {
			AILogWithSignature(@"Setting %@ topic to: %@", self, [self valueForProperty:KEY_TOPIC]);
			[account setTopic:inTopic forChat:self];
		}
	} else {
		AILogWithSignature(@"Attempt to topic when account doesn't support it.");
	}
}

- (void)contentObjectAdded:(NSNotification *)notification
{
	AIContentMessage *content = [[notification userInfo] objectForKey:@"AIContentObject"];
	
	self.lastMessageDate = [content date];
}


/*!
 * @brief Resorts our participants
 *
 * This is called when our list objects change.
 */
- (void)resortParticipants
{
	[participatingNicks sortUsingComparator:^(id objectA, id objectB){
		AIGroupChatFlags flagA = highestFlag([self flagsForNick:objectA]), flagB = highestFlag([self flagsForNick:objectB]);
		
		if(flagA > flagB) {
			return (NSComparisonResult)NSOrderedAscending;
		} else if (flagA < flagB) {
			return (NSComparisonResult)NSOrderedDescending;
		} else {
			return [objectA localizedCaseInsensitiveCompare:objectB];
		}
	}];
}

//Participating ListObjects --------------------------------------------------------------------------------------------
#pragma mark Participating ListObjects

- (AIListObject *)contactForNick:(NSString *)nick
{
	return [participatingNicksContacts objectForKey:nick];
}

- (AIGroupChatFlags)flagsForNick:(NSString *)nick
{
	return [[participatingNicksFlags objectForKey:nick] intValue];
}

- (void)setFlags:(AIGroupChatFlags)flags forNick:(NSString *)nick
{
	[participatingNicksFlags setObject:@(flags)
								forKey:nick];
}

- (void)setContact:(AIListContact *)contact forNick:(NSString *)nick
{
	NSParameterAssert(contact != nil);
	
	[participatingNicksContacts setObject:contact
								   forKey:nick];
}

- (void)changeNick:(NSString *)from to:(NSString *)to
{
	[participatingNicks removeObject:from];
	[participatingNicks addObject:to];
	
	NSNumber *flags = [participatingNicksFlags objectForKey:from];
	[participatingNicksFlags removeObjectForKey:from];
	if (flags) [participatingNicksFlags setObject:flags forKey:to];
	
	AIListObject *contact = [participatingNicksContacts objectForKey:from];
	[participatingNicksContacts removeObjectForKey:from];
	if (contact) [participatingNicksContacts setObject:contact forKey:to];
}

/*!
 * @brief Remove the saved values for a contact
 *
 * Removes any values which are dependent upon the contact, such as
 * its flags or alias.
 */
- (void)removeSavedValuesForNick:(NSString *)nick
{
	[participatingNicksFlags removeObjectForKey:nick];
	[participatingNicksContacts removeObjectForKey:nick];
}

- (NSArray *)nicksForContact:(AIListContact *)contact
{
	NSMutableArray *nicks = [NSMutableArray array];
	
	for (NSString *nick in participatingNicks) {
		if ([[participatingNicksContacts objectForKey:nick] isEqual:contact]) {
			[nicks addObject:nick];
		}
	}
	
	return nicks;
}

- (void)addParticipatingNick:(NSString *)inObject notify:(BOOL)notify
{
	[self addParticipatingNicks:[NSArray arrayWithObject:inObject] notify:notify];
}

- (void)addParticipatingNicks:(NSArray *)inObjects notify:(BOOL)notify
{
	[participatingNicks addObjectsFromArray:inObjects];
	[adium.chatController chat:self addedListContacts:inObjects notify:notify];
}

- (BOOL)addObject:(NSString *)inObject
{
	NSParameterAssert([inObject isKindOfClass:[NSString class]]);
    
	[self addParticipatingNick:inObject notify:YES];
	return YES;
}

// Invite a list object to join the chat. Returns YES if the chat joins, NO otherwise
- (BOOL)inviteListContact:(AIListContact *)inContact withMessage:(NSString *)inviteMessage
{
	return ([self.account inviteContact:inContact toChat:self withMessage:inviteMessage]);
}

- (NSArray *)containedObjects
{
	return [participatingNicksContacts allValues];
}

- (NSArray *)visibleContainedObjects
{
	return self.containedObjects;
}

- (NSUInteger)countOfContainedObjects
{
	return [participatingNicks count];
}

- (BOOL)containsObject:(AIListObject *)inObject
{
	return [[participatingNicksContacts allValues] containsObjectIdenticalTo:inObject];
}

- (NSString *)visibleObjectAtIndex:(NSUInteger)idx
{
	return [participatingNicks objectAtIndex:idx];
}

- (NSUInteger)visibleIndexOfObject:(AIListObject *)obj
{
	if(![[AIContactHidingController sharedController] visibilityOfListObject:obj inContainer:self])
		return NSNotFound;
	for (NSString *nick in participatingNicks) {
		if ([[participatingNicksContacts objectForKey:nick] isEqual:obj]) {
			return [participatingNicks indexOfObject:nick];
		}
	}
	
	return NSNotFound;
}

- (NSArray *)uniqueContainedObjects
{
	NSMutableArray *contacts = [NSMutableArray array];
	
	for (AIListContact *contact in [participatingNicksContacts allValues]) {
		if (![contacts containsObject:contacts]) {
			[contacts addObject:contact];
		}
	}
		
	return contacts;
}

- (void)removeObject:(NSString *)inObject
{
	AIListContact *contact = [participatingNicksContacts valueForKey:inObject];
	
	//make sure removing it from the array doesn't deallocate it immediately, since we need it for -chat:removedListContact:
	[contact retain];
	
	[participatingNicks removeObject:inObject];
	
	[self removeSavedValuesForNick:inObject];
	
	[adium.chatController chat:self removedListContact:contact];
	
	if (contact.isStranger &&
		![adium.chatController allGroupChatsContainingContact:contact.parentContact].count &&
		![adium.chatController existingChatWithContact:contact.parentContact]) {
		
		[[AIContactObserverManager sharedManager] delayListObjectNotifications];
		[adium.contactController accountDidStopTrackingContact:contact];
		[[AIContactObserverManager sharedManager] endListObjectNotificationsDelaysImmediately];
	}
	
	[contact release];
}

- (void)removeObjectAfterAccountStopsTracking:(NSString *)object
{
	assert(FALSE);
}

- (void)removeAllParticipatingContactsSilently
{
	/* Note that allGroupChatsContainingContact won't count this chat if it's already marked as not open */
	for (AIListContact *listContact in [participatingNicksContacts allValues]) {
		if (listContact.isStranger &&
			![adium.chatController existingChatWithContact:listContact.parentContact] &&
			([adium.chatController allGroupChatsContainingContact:listContact.parentContact].count == 0)) {
			[adium.contactController accountDidStopTrackingContact:listContact];
		}
	}
    
	[participatingNicks removeAllObjects];
	[participatingNicksFlags removeAllObjects];
	[participatingNicksContacts removeAllObjects];
    
	[[NSNotificationCenter defaultCenter] postNotificationName:Chat_ParticipatingListObjectsChanged
                                                        object:self];
}

@synthesize expanded;

- (BOOL)isExpandable
{
	return NO;
}

- (NSUInteger)visibleCount
{
	return self.countOfContainedObjects;
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)stackbuf count:(NSUInteger)len
{
	return [participatingNicks countByEnumeratingWithState:state objects:stackbuf count:len];
}

- (BOOL) canContainObject:(id)obj
{
	return [obj isKindOfClass:[AIListContact class]];
}


//Retrieve a specific object by service and UID
- (AIListObject *)objectWithService:(AIService *)inService UID:(NSString *)inUID
{
	for (AIListContact *object in self) {
		if ([inUID isEqualToString:object.UID] && object.service == inService)
			return object;
	}
	
	return nil;
}

//Not used
- (float)smallestOrder { return 0; }
- (float)largestOrder { return 1E10f; }
- (float)orderIndexForObject:(AIListObject *)listObject { return 0; }
- (void)listObject:(AIListObject *)listObject didSetOrderIndex:(float)inOrderIndex {};



- (NSString *)contentsBasedIdentifier
{
	return [NSString stringWithFormat:@"%@-%@.%@",self.name, self.account.service.serviceID, self.account.UID];
}

- (BOOL)isGroupChat
{
    return YES;
}

@end
