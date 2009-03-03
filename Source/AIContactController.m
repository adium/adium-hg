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

// $Id$

#import "AIContactController.h"

#import "AISCLViewPlugin.h"
#import <Adium/AIContactHidingController.h>

#import <Adium/AIAccountControllerProtocol.h>
#import <Adium/AIInterfaceControllerProtocol.h>
#import <Adium/AILoginControllerProtocol.h>
#import <Adium/AIMenuControllerProtocol.h>
#import <Adium/AIPreferenceControllerProtocol.h>
#import <Adium/AIToolbarControllerProtocol.h>
#import <Adium/AIContactAlertsControllerProtocol.h>

#import <AIUtilities/AIArrayAdditions.h>
#import <AIUtilities/AIDictionaryAdditions.h>
#import <AIUtilities/AIFileManagerAdditions.h>
#import <AIUtilities/AIMenuAdditions.h>
#import <AIUtilities/AIToolbarUtilities.h>
#import <AIUtilities/AIApplicationAdditions.h>
#import <AIUtilities/AIImageAdditions.h>
#import <AIUtilities/AIStringAdditions.h>
#import <Adium/AIAccount.h>
#import <Adium/AIChat.h>
#import <Adium/AIContentMessage.h>
#import <Adium/AIListContact.h>
#import <Adium/AIListGroup.h>
#import <Adium/AIListObject.h>
#import <Adium/AIMetaContact.h>
#import <Adium/AIService.h>
#import <Adium/AISortController.h>
#import <Adium/AIUserIcons.h>
#import <Adium/AIServiceIcons.h>
#import <Adium/AIListBookmark.h>
#import <Adium/AIContactList.h>

#define KEY_FLAT_GROUPS					@"FlatGroups"			//Group storage
#define KEY_FLAT_CONTACTS				@"FlatContacts"			//Contact storage
#define KEY_FLAT_METACONTACTS			@"FlatMetaContacts"		//Metacontact objectID storage
#define KEY_BOOKMARKS					@"Bookmarks"

#define	OBJECT_STATUS_CACHE				@"Object Status Cache"


#define TOP_METACONTACT_ID				@"TopMetaContactID"
#define KEY_IS_METACONTACT				@"isMetaContact"
#define KEY_OBJECTID					@"objectID"
#define KEY_METACONTACT_OWNERSHIP		@"MetaContact Ownership"
#define CONTACT_DEFAULT_PREFS			@"ContactPrefs"

#define	SHOW_GROUPS_MENU_TITLE			AILocalizedString(@"Show Groups",nil)
#define	HIDE_GROUPS_MENU_TITLE			AILocalizedString(@"Hide Groups",nil)

#define SHOW_GROUPS_IDENTIFER			@"ShowGroups"

#define SERVICE_ID_KEY					@"ServiceID"
#define UID_KEY							@"UID"

@interface AIListObject ()
@property (readwrite, nonatomic) CGFloat orderIndex;
@end

@interface AIContactController ()
- (void)saveContactList;
- (NSArray *)_arrayRepresentationOfListObjects:(NSArray *)listObjects;
- (void)_loadBookmarks;
- (NSArray *)allBookmarksInObject:(AIListObject<AIContainingObject> *)inGroup;
- (void)_didChangeContainer:(AIListObject<AIContainingObject> *)inContainingObject object:(AIListObject *)object;
- (void)prepareShowHideGroups;
- (void)_performChangeOfUseContactListGroups;
- (void)_positionObject:(AIListObject *)listObject atIndex:(NSInteger)index inObject:(AIListObject<AIContainingObject> *)group;
- (void)_moveContactServerside:(AIListContact *)listContact toGroups:(NSSet *)groups;
- (void)_renameGroup:(AIListGroup *)listGroup to:(NSString *)newName;

//MetaContacts
- (BOOL)_restoreContactsToMetaContact:(AIMetaContact *)metaContact;
- (void)_restoreContactsToMetaContact:(AIMetaContact *)metaContact fromContainedContactsArray:(NSArray *)containedContactsArray;
- (void)addContact:(AIListContact *)inContact toMetaContact:(AIMetaContact *)metaContact;
- (BOOL)_performAddContact:(AIListContact *)inContact toMetaContact:(AIMetaContact *)metaContact;
- (void)removeContact:(AIListContact *)inContact fromMetaContact:(AIMetaContact *)metaContact;
- (void)_loadMetaContactsFromArray:(NSArray *)array;
- (void)_saveMetaContacts:(NSDictionary *)allMetaContactsDict;
- (void)breakdownAndRemoveMetaContact:(AIMetaContact *)metaContact;
- (void)_storeListObject:(AIListObject *)listObject inMetaContact:(AIMetaContact *)metaContact;
@end

@implementation AIContactController

- (id)init
{
	if ((self = [super init])) {
		//
		contactDict = [[NSMutableDictionary alloc] init];
		groupDict = [[NSMutableDictionary alloc] init];
		bookmarkDict = [[NSMutableDictionary alloc] init];
		metaContactDict = [[NSMutableDictionary alloc] init];
		contactToMetaContactLookupDict = [[NSMutableDictionary alloc] init];
		contactLists = [[NSMutableArray alloc] init];

		contactPropertiesObserverManager = [AIContactObserverManager sharedManager];
	}
	
	return self;
}

- (void)controllerDidLoad
{	
	//Default contact preferences
	[adium.preferenceController registerDefaults:[NSDictionary dictionaryNamed:CONTACT_DEFAULT_PREFS
																		forClass:[self class]]
										  forGroup:PREF_GROUP_CONTACT_LIST];
	
	contactList = [[AIContactList alloc] initWithUID:ADIUM_ROOT_GROUP_NAME];
	[contactLists addObject:contactList];
	//Root is always "expanded"
	[contactList setExpanded:YES];
	
	//Show Groups menu item
	[self prepareShowHideGroups];
	
	//Observe content (for preferredContactForContentType:forListContact:)
    [adium.notificationCenter addObserver:self
                                   selector:@selector(didSendContent:)
                                       name:CONTENT_MESSAGE_SENT
                                     object:nil];
	
	[self loadContactList];
	[self sortContactList];
	
	[adium.preferenceController registerPreferenceObserver:self forGroup:PREF_GROUP_CONTACT_LIST_DISPLAY];
}

- (void)controllerWillClose
{
	[self saveContactList];
}

- (void)dealloc
{
	[adium.preferenceController unregisterPreferenceObserver:self];
		
	[contactDict release];
	[groupDict release];
	[bookmarkDict release];
	[metaContactDict release];
	[contactToMetaContactLookupDict release];
	[contactLists release];
	
	[contactPropertiesObserverManager release];

	[super dealloc];
}

- (void)clearAllMetaContactData
{
	if (metaContactDict.count) {
		[contactPropertiesObserverManager delayListObjectNotifications];
		
		//Remove all the metaContacts to get any existing objects out of them
		for (AIMetaContact *metaContact in [[[metaContactDict copy] autorelease] objectEnumerator]) {
			[self breakdownAndRemoveMetaContact:metaContact];
		}
		
		[contactPropertiesObserverManager endListObjectNotificationsDelay];
	}
	
	[metaContactDict release]; metaContactDict = [[NSMutableDictionary alloc] init];
	[contactToMetaContactLookupDict release]; contactToMetaContactLookupDict = [[NSMutableDictionary alloc] init];
	
	//Clear the preferences for good measure
	[adium.preferenceController setPreference:nil
										 forKey:KEY_FLAT_METACONTACTS
										  group:PREF_GROUP_CONTACT_LIST];
	[adium.preferenceController setPreference:nil
										 forKey:KEY_METACONTACT_OWNERSHIP
										  group:PREF_GROUP_CONTACT_LIST];
	
	//Clear out old metacontact files
	[[NSFileManager defaultManager] removeFilesInDirectory:[[adium.loginController userDirectory] stringByAppendingPathComponent:OBJECT_PREFS_PATH]
												withPrefix:@"MetaContact"
											 movingToTrash:NO];
	[[NSFileManager defaultManager] removeFilesInDirectory:[adium cachesPath]
												withPrefix:@"MetaContact"
											 movingToTrash:NO];
}

#pragma mark Local Contact List Storage
//Load the contact list
- (void)loadContactList
{
	//We must load all the groups before loading contacts for the ordering system to work correctly.
	[self _loadMetaContactsFromArray:[adium.preferenceController preferenceForKey:KEY_FLAT_METACONTACTS
																			  group:PREF_GROUP_CONTACT_LIST]];
	[self _loadBookmarks];
}

//Save the contact list
- (void)saveContactList
{
	for (AIListGroup *listGroup in [groupDict objectEnumerator]) {
		[listGroup setPreference:[NSNumber numberWithBool:[listGroup isExpanded]]
						  forKey:@"IsExpanded"
						   group:PREF_GROUP_CONTACT_LIST];
	}
	
	NSMutableArray *bookmarks = [NSMutableArray array];
	for (AIListObject *listObject in self.allBookmarks) {
		if ([listObject isKindOfClass:[AIListBookmark class]]) {
			[bookmarks addObject:[NSKeyedArchiver archivedDataWithRootObject:listObject]];
		}
	}
	
	[adium.preferenceController setPreference:bookmarks
										 forKey:KEY_BOOKMARKS
										  group:PREF_GROUP_CONTACT_LIST];
}

- (void)_loadBookmarks
{
	for (NSData *data in [adium.preferenceController preferenceForKey:KEY_BOOKMARKS group:PREF_GROUP_CONTACT_LIST]) {
		AIListBookmark	*bookmark;
		//As a bookmark is initialized, it will add itself to the contact list in the right place
		bookmark = [NSKeyedUnarchiver unarchiveObjectWithData:data];	
		
		//It's a newly created object, so set its initial attributes
		[contactPropertiesObserverManager _updateAllAttributesOfObject:bookmark];
	}
}

- (void)_loadMetaContactsFromArray:(NSArray *)array
{	
	for (NSString *identifier in array) {
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		NSNumber *objectID = [NSNumber numberWithInteger:[[[identifier componentsSeparatedByString:@"-"] objectAtIndex:1] integerValue]];
		[self metaContactWithObjectID:objectID];
		[pool release];
	}
}

//Flattened array of the contact list content
- (NSArray *)_arrayRepresentationOfListObjects:(NSArray *)listObjects
{
	NSMutableArray	*array = [NSMutableArray array];
	
	for (AIListObject *object in listObjects) {
		[array addObject:[NSDictionary dictionaryWithObjectsAndKeys:
						  @"Group", @"Type",
						  [object UID], UID_KEY,
						  [NSNumber numberWithBool:[(AIListGroup *)object isExpanded]], @"Expanded",
						  nil]];
	}
	
	return array;
}

#pragma mark Contact Grouping

//Redetermine the local grouping of a contact in response to server grouping information or an external change
- (void)contactRemoteGroupingChanged:(AIListContact *)inContact
{
	NSSet *remoteGroupNames = inContact.remoteGroupNames;
	[[inContact retain] autorelease];
	
	if (inContact.metaContact) {
		
		/* If inContact's containingObject is a metaContact, and that metaContact has no groups,
		 * use inContact's remote grouping as the metaContact's grouping.
		 */
		if (inContact.metaContact.groups.count == 0 && remoteGroupNames.count > 0) {
			//If no similar objects exist, we add this contact directly to the list
			//Create a group for the contact even if contact list groups aren't on,
			//otherwise requests for all the contact list groups will return nothing
			for (NSString *remoteGroupName in remoteGroupNames) {
				AIListGroup *localGroup, *contactGroup = [self groupWithUID:remoteGroupName];
				
				localGroup = (useContactListGroups ?
							  (useOfflineGroup && !inContact.online ? self.offlineGroup : contactGroup) :
							  contactList);
				
				[localGroup addObject:inContact.metaContact];
				
				[self _didChangeContainer:localGroup object:inContact.metaContact];
				
				//todo: updating too frequently here
				[adium.notificationCenter postNotificationName:@"Contact_ListChanged"
				 object:localGroup.contactList
				 userInfo:nil];
			}
			
			//NSLog(@"contactRemoteGroupingChanged: %@ is in %@, which was moved to %@",inContact,containingObject,localGroup);
		}
		
	} else if (remoteGroupNames.count > 0) {
		//Create a group for the contact even if contact list groups aren't on,
		//otherwise requests for all the contact list groups will return nothing
		NSMutableSet *groups = [NSMutableSet set];
		for (NSString *remoteGroupName in remoteGroupNames) {
			AIListGroup *localGroup, *contactGroup = [self groupWithUID:remoteGroupName];
			
			localGroup = useContactListGroups ?
				(useOfflineGroup && !inContact.online ? self.offlineGroup : contactGroup) :
				contactList;
			
			//NSLog(@"contactRemoteGroupingChanged: %@: remoteGroupName %@ --> %@",inContact,remoteGroupName,localGroup);
			
			[groups addObject:localGroup];
		}
		[self _moveContactLocally:inContact toGroups:groups];
		
	} else if (inContact.groups.count > 0) {
		//If !remoteGroupName, remove the contact from any local groups
		for (AIListGroup *group in [[inContact.groups copy] autorelease]) {
			[group removeObject:inContact];
			[self _didChangeContainer:group object:inContact];
		}
		
		//NSLog(@"contactRemoteGroupingChanged: %@: -- !remoteGroupName so removed from %@",inContact,containingObject);
	}
	
	BOOL	isCurrentlyAStranger = inContact.isStranger;
	if ((isCurrentlyAStranger && remoteGroupNames.count > 0) || (!isCurrentlyAStranger && remoteGroupNames.count == 0)) {
		[inContact setValue:(remoteGroupNames.count > 0 ? [NSNumber numberWithBool:YES] : nil)
							forProperty:@"NotAStranger"
							notify:NotifyLater];
		[inContact notifyOfChangedPropertiesSilently:YES];
	}
}

- (void)_addContactLocally:(AIListContact *)listContact toGroup:(AIListGroup *)localGroup
{
	AIListObject	*existingObject;
	BOOL			performedGrouping = NO;
	
	//Protect with a retain while we are removing and adding the contact to our arrays
	[listContact retain];
	
	//XXX
	//	AILog(@"Adding %@ to %@",listContact,localGroup);
	
	if (listContact.canJoinMetaContacts) {
		if ((existingObject = [localGroup objectWithService:[listContact service] UID:listContact.UID])) {
			//If an object exists in this group with the same UID and serviceID, create a MetaContact
			//for the two.
			[self groupContacts:[NSArray arrayWithObjects:listContact,existingObject,nil]];
			performedGrouping = YES;
			
		} else {
			AIMetaContact	*metaContact;
			
			//If no object exists in this group which matches, we should check if there is already
			//a MetaContact holding a matching ListContact, since we should include this contact in it
			//If we found a metaContact to which we should add, do it.
			if ((metaContact = [contactToMetaContactLookupDict objectForKey:[listContact internalObjectID]])) {
				//XXX
				//			AILog(@"Found an existing metacontact; adding %@ to %@",listContact,metaContact);
				
				[self addContact:listContact toMetaContact:metaContact];
				performedGrouping = YES;
			}
		}
	}
	
	if (!performedGrouping) {
		//If no similar objects exist, we add this contact directly to the list
		[localGroup addObject:listContact];
		
		//Add
		[self _didChangeContainer:localGroup object:listContact];
	}
	
	//Cleanup
	[listContact release];
}

- (void)_moveContactLocally:(AIListContact *)listContact toGroups:(NSSet *)groups
{
	//Protect with a retain while we are removing and adding the contact to our arrays
	[listContact retain];
	
	//Remove this object from any local groups we have it in currently
	for (AIListGroup *group in [[listContact.groups copy] autorelease]) {
		[group removeObject:listContact];
		[self _didChangeContainer:group object:listContact];
	}
	
	for (AIListGroup *group in groups)
		[self _addContactLocally:listContact toGroup:group];
	
	[listContact release];
}

- (NSSet *)remoteGroupsForContact:(AIListContact *)inContact
{
	NSSet *groups;
	
	if ([inContact isKindOfClass:[AIMetaContact class]]) {
		//For a metaContact, the closest we have to a remote group is the groups it is within locally
		groups = inContact.groups;
		
	} else {
		groups = [NSMutableSet set];
		for (NSString *remoteGroup in inContact.remoteGroupNames) {
			[(NSMutableSet *)groups addObject:[self groupWithUID:remoteGroup]];
		}
	}
	
	return groups;
}

//Post a list grouping changed notification for the object and containing object
- (void)_didChangeContainer:(AIListObject<AIContainingObject> *)inContainingObject object:(AIListObject *)object
{
	if ([contactPropertiesObserverManager updatesAreDelayed]) {
		[contactPropertiesObserverManager noteContactChanged:object];

	} else {
		[adium.notificationCenter postNotificationName:Contact_ListChanged
												  object:inContainingObject
												userInfo:nil];
	}
}

- (BOOL)useContactListGroups
{
	return useContactListGroups;
}

- (void)setUseContactListGroups:(BOOL)inFlag
{
	if (inFlag != useContactListGroups) {
		useContactListGroups = inFlag;
		
		[self _performChangeOfUseContactListGroups];
	}
}

- (void)_performChangeOfUseContactListGroups
{
	[contactPropertiesObserverManager delayListObjectNotifications];
	
	//Store the preference
	[adium.preferenceController setPreference:[NSNumber numberWithBool:!useContactListGroups]
										 forKey:KEY_HIDE_CONTACT_LIST_GROUPS
										  group:PREF_GROUP_CONTACT_LIST_DISPLAY];
	
	//Configure the sort controller to force ignoring of groups as appropriate
	[[AISortController activeSortController] forceIgnoringOfGroups:(useContactListGroups ? NO : YES)];
	
	if (useContactListGroups) { /* We are now using contact list groups, but we weren't before. */
		//Restore the grouping of all root-level contacts
		for (AIListObject *listObject in [[[contactList containedObjects] copy] autorelease]) {
			if ([listObject isKindOfClass:[AIListContact class]]) {
				[(AIListContact *)listObject restoreGrouping];
			}
		}
		
	} else { /* We are no longer using contact list groups, but we were before. */
		for (AIListObject *listObject in [[[contactList containedObjects] copy] autorelease]) {
			if ([listObject isKindOfClass:[AIListGroup class]]) {
				
				NSArray *containedObjects = [[(AIListGroup *)listObject containedObjects] copy];
				for (AIListObject *containedListObject in containedObjects) {
					if ([containedListObject isKindOfClass:[AIListContact class]]) {
						[self _moveContactLocally:(AIListContact *)containedListObject
										 toGroups:[NSSet setWithObject:contactList]];
					}
				}
				[containedObjects release];
			}
		}
	}
	
	//Stop delaying object notifications; this will automatically resort the contact list, so we're done.
	[contactPropertiesObserverManager endListObjectNotificationsDelay];
}

- (void)prepareShowHideGroups
{
	//Load the preference
	useContactListGroups = ![[adium.preferenceController preferenceForKey:KEY_HIDE_CONTACT_LIST_GROUPS
																	  group:PREF_GROUP_CONTACT_LIST_DISPLAY] boolValue];
	
	//Show offline contacts menu item
    menuItem_showGroups = [[NSMenuItem alloc] initWithTitle:(useContactListGroups ? HIDE_GROUPS_MENU_TITLE : SHOW_GROUPS_MENU_TITLE)
													 target:self
													 action:@selector(toggleShowGroups:)
											  keyEquivalent:@""];
	[adium.menuController addMenuItem:menuItem_showGroups toLocation:LOC_View_Toggles];
	
	//Toolbar
	NSToolbarItem	*toolbarItem;
    toolbarItem = [AIToolbarUtilities toolbarItemWithIdentifier:SHOW_GROUPS_IDENTIFER
														  label:AILocalizedString(@"Show Groups",nil)
												   paletteLabel:AILocalizedString(@"Toggle Groups Display",nil)
														toolTip:AILocalizedString(@"Toggle display of groups",nil)
														 target:self
												settingSelector:@selector(setImage:)
													itemContent:[NSImage imageNamed:(useContactListGroups ?
																					 @"togglegroups_transparent" :
																					 @"togglegroups")
																		   forClass:[self class]
																		 loadLazily:YES]
														 action:@selector(toggleShowGroupsToolbar:)
														   menu:nil];
    [adium.toolbarController registerToolbarItem:toolbarItem forToolbarType:@"ContactList"];
}

- (IBAction)toggleShowGroups:(id)sender
{
	//Flip-flop.
	useContactListGroups = !useContactListGroups;
	[menuItem_showGroups setTitle:(useContactListGroups ? HIDE_GROUPS_MENU_TITLE : SHOW_GROUPS_MENU_TITLE)];

	//Update the contact list.  Do it on the next run loop for better menu responsiveness, as it may be a lengthy procedure.
	[self performSelector:@selector(_performChangeOfUseContactListGroups)
			   withObject:nil
			   afterDelay:0];
}

- (IBAction)toggleShowGroupsToolbar:(id)sender
{
	[self toggleShowGroups:sender];
	
	[sender setImage:[NSImage imageNamed:(useContactListGroups ?
										  @"togglegroups_transparent" :
										  @"togglegroups")
								forClass:[self class]]];
}

- (BOOL)useOfflineGroup
{
	return useOfflineGroup;
}

- (AIListGroup *)offlineGroup
{
	if(!useOfflineGroup)
		return [groupDict objectForKey:[AILocalizedString(@"Offline", "Name of offline group") lowercaseString]];

	return [self groupWithUID:AILocalizedString(@"Offline", "Name of offline group")];
}

#pragma mark Meta Contacts

/*!
 * @brief Create or load a metaContact
 *
 * @param inObjectID The objectID of an existing but unloaded metaContact, or nil to create and save a new metaContact
 */
- (AIMetaContact *)metaContactWithObjectID:(NSNumber *)inObjectID
{
	BOOL			shouldRestoreContacts = YES;
	
	//If no object ID is provided, use the next available object ID
	//(MetaContacts should always have an individually unique object id)
	if (!inObjectID) {
		NSInteger topID = [[adium.preferenceController preferenceForKey:TOP_METACONTACT_ID
															  group:PREF_GROUP_CONTACT_LIST] integerValue];
		inObjectID = [NSNumber numberWithInteger:topID];
		[adium.preferenceController setPreference:[NSNumber numberWithInteger:([inObjectID integerValue] + 1)]
											 forKey:TOP_METACONTACT_ID
											  group:PREF_GROUP_CONTACT_LIST];
		
		//No reason to waste time restoring contacts when none are in the meta contact yet.
		shouldRestoreContacts = NO;
	}
	
	//Look for a metacontact with this object ID.  If none is found, create one
	//and add its contained contacts to it.
	NSString		*metaContactDictKey = [AIMetaContact internalObjectIDFromObjectID:inObjectID];
	
	AIMetaContact   *metaContact = [metaContactDict objectForKey:metaContactDictKey];
	if (!metaContact) {
		metaContact = [(AIMetaContact *)[AIMetaContact alloc] initWithObjectID:inObjectID];
		
		//Keep track of it in our metaContactDict for retrieval by objectID
		[metaContactDict setObject:metaContact forKey:metaContactDictKey];
		
		//Add it to our more general contactDict, as well
		[contactDict setObject:metaContact forKey:[metaContact internalUniqueObjectID]];
		
		/* We restore contacts (actually, internalIDs for contacts, to be added as necessary later) if the metaContact
		 * existed before this call to metaContactWithObjectID:
		 */
		if (shouldRestoreContacts)
			[self _restoreContactsToMetaContact:metaContact];
		
		/* As with contactWithService:account:UID, update all attributes so observers are initially informed of
		 * this object's existence.
		 */
		[contactPropertiesObserverManager _updateAllAttributesOfObject:metaContact];
		
		[metaContact release];
	}
	
	return metaContact;
}

/*!
 * @brief Associate the appropriate internal IDs for contained contacts with a metaContact
 *
 * @result YES if one or more contacts was associated with the metaContact; NO if none were.
 */
- (BOOL)_restoreContactsToMetaContact:(AIMetaContact *)metaContact
{
	NSDictionary	*allMetaContactsDict = [adium.preferenceController preferenceForKey:KEY_METACONTACT_OWNERSHIP
																				 group:PREF_GROUP_CONTACT_LIST];
	NSArray			*containedContactsArray = [allMetaContactsDict objectForKey:[metaContact internalObjectID]];
	BOOL			restoredContacts;
	
	if ([containedContactsArray count]) {
		[self _restoreContactsToMetaContact:metaContact
				 fromContainedContactsArray:containedContactsArray];
		
		restoredContacts = YES;
		
	} else {
		restoredContacts = NO;
	}
	
	return restoredContacts;
}

/*!
 * @brief Associate the internal IDs for an array of contacts with a specific metaContact
 *
 * This does not actually place any AIListContacts within the metaContact.  Instead, it updates the contactToMetaContactLookupDict
 * dictionary to have metaContact associated with the list contacts specified by containedContactsArray. This
 * allows us to add them lazily to the metaContact (in contactWithService:account:UID:) as necessary.
 *
 * @param metaContact The metaContact to which contact referneces are added
 * @param containedContactsArray An array of NSDictionary objects, each of which has SERVICE_ID_KEY and UID_KEY which together specify an internalObjectID of an AIListContact
 */
- (void)_restoreContactsToMetaContact:(AIMetaContact *)metaContact fromContainedContactsArray:(NSArray *)containedContactsArray
{	
	for (NSDictionary *containedContactDict in containedContactsArray) {
		/* Before Adium 0.80, metaContacts could be created within metaContacts. Simply ignore any attempt to restore
		 * such erroneous data, which will have a YES boolValue for KEY_IS_METACONTACT. */
		if (![[containedContactDict objectForKey:KEY_IS_METACONTACT] boolValue]) {
			/* Assign this metaContact to the appropriate internalObjectID for containedContact's represented listObject.
			 *
			 * As listObjects are loaded/created/requested which match this internalObjectID, 
			 * they will be inserted into the metaContact.
			 */
			NSString	*internalObjectID = [AIListObject internalObjectIDForServiceID:[containedContactDict objectForKey:SERVICE_ID_KEY]
																				UID:[containedContactDict objectForKey:UID_KEY]];
			[contactToMetaContactLookupDict setObject:metaContact
											   forKey:internalObjectID];
		}
	}
}


//Add a list object to a meta contact, setting preferences and such
//so the association is lasting across program launches.
- (void)addContact:(AIListContact *)inContact toMetaContact:(AIMetaContact *)metaContact
{
	if (!inContact) {
		//I can't think of why one would want to add an entire group to a metacontact. Let's say you can't.
		NSLog(@"Warning: addContact:toMetaContact: Attempted to add %@ to %@",inContact,metaContact);
		return;
	}
	
	if (inContact == metaContact) return;
	
	//If listObject contains other contacts, perform addContact:toMetaContact: recursively
	if ([inContact conformsToProtocol:@protocol(AIContainingObject)]) {
		for (AIListContact *someObject in [[[(AIListObject<AIContainingObject> *)inContact containedObjects] copy] autorelease]) {
			[self addContact:someObject toMetaContact:metaContact];
		}
		
	} else {
		//Obtain any metaContact this listObject is currently within, so we can remove it later
		AIMetaContact *oldMetaContact = [contactToMetaContactLookupDict objectForKey:[inContact internalObjectID]];
		
		if ([self _performAddContact:inContact toMetaContact:metaContact] && metaContact != oldMetaContact) {
			//If this listObject was not in this metaContact in any form before, store the change
			//Remove the list object from any other metaContact it is in at present
			if (oldMetaContact)
				[self removeContact:inContact fromMetaContact:oldMetaContact];
			
			[self _storeListObject:inContact inMetaContact:metaContact];

			//Do the update thing
			[contactPropertiesObserverManager _updateAllAttributesOfObject:metaContact];
		}
	}
}

- (void)_storeListObject:(AIListObject *)listObject inMetaContact:(AIMetaContact *)metaContact
{
	//we only allow group->meta->contact, not group->meta->meta->contact
	NSParameterAssert(![listObject conformsToProtocol:@protocol(AIContainingObject)]);
	
	//	AILog(@"MetaContacts: Storing %@ in %@",listObject, metaContact);
	NSDictionary		*containedContactDict;
	NSMutableDictionary	*allMetaContactsDict;
	NSMutableArray		*containedContactsArray;
	
	NSString			*metaContactInternalObjectID = [metaContact internalObjectID];
	
	//Get the dictionary of all metaContacts
	allMetaContactsDict = [[adium.preferenceController preferenceForKey:KEY_METACONTACT_OWNERSHIP
																	group:PREF_GROUP_CONTACT_LIST] mutableCopy];
	if (!allMetaContactsDict) {
		allMetaContactsDict = [[NSMutableDictionary alloc] init];
	}
	
	//Load the array for the new metaContact
	containedContactsArray = [[allMetaContactsDict objectForKey:metaContactInternalObjectID] mutableCopy];
	if (!containedContactsArray) containedContactsArray = [[NSMutableArray alloc] init];
	containedContactDict = nil;
	
	//Create the dictionary describing this list object
	containedContactDict = [NSDictionary dictionaryWithObjectsAndKeys:
							listObject.service.serviceID, SERVICE_ID_KEY,
							listObject.UID, UID_KEY, nil];
	
	//Only add if this dict isn't already in the array
	if (containedContactDict && ([containedContactsArray indexOfObject:containedContactDict] == NSNotFound)) {
		[containedContactsArray addObject:containedContactDict];
		[allMetaContactsDict setObject:containedContactsArray forKey:metaContactInternalObjectID];
		
		//Save
		[self _saveMetaContacts:allMetaContactsDict];
		
		[adium.contactAlertsController mergeAndMoveContactAlertsFromListObject:listObject
																  intoListObject:metaContact];
	}
	
	[allMetaContactsDict release];
	[containedContactsArray release];
}

//Actually adds a list contact to a meta contact. No preferences are changed.
//Attempts to add the list object, causing group reassignment and updates our contactToMetaContactLookupDict
//for quick lookup of the MetaContact given a AIListContact uniqueObjectID if successful.
- (BOOL)_performAddContact:(AIListContact *)inContact toMetaContact:(AIMetaContact *)metaContact
{
	//we only allow group->meta->contact, not group->meta->meta->contact
	NSParameterAssert(![inContact conformsToProtocol:@protocol(AIContainingObject)]);

	BOOL								success;
	
	NSSet *contactGroups = inContact.groups;
	
	//Remove the object from its previous containing groups
	for (AIListGroup *group in [[contactGroups copy] autorelease]) {
		[group removeObject:inContact];
		[self _didChangeContainer:group object:inContact];
	}
	
	//AIMetaContact will handle reassigning the list object's grouping to being itself
	if ((success = [metaContact addObject:inContact])) {
		[contactToMetaContactLookupDict setObject:metaContact forKey:[inContact internalObjectID]];
		
		[self _didChangeContainer:metaContact object:inContact];
		//If the metaContact isn't in a group yet, use the group of the object we just added
		if (metaContact.groups.count == 0) {
			for (AIListGroup *group in contactGroups) {
				[group addObject:metaContact];
				[self _didChangeContainer:group object:metaContact];
			}
		}

		//Ensure the metacontact ends up in the appropriate group
		if (metaContact.groups.count == 0 || [metaContact.groups containsObject:self.offlineGroup])
			[metaContact restoreGrouping];
	}
	
	return success;
}

- (void)removeAllContactsMatching:(AIListContact *)inContact fromMetaContact:(AIMetaContact *)metaContact
{	
	//Remove from the contactToMetaContactLookupDict first so we don't try to reinsert into this metaContact
	[contactToMetaContactLookupDict removeObjectForKey:[inContact internalObjectID]];
	
	[contactPropertiesObserverManager delayListObjectNotifications];
	for (AIListContact *contact in [self allContactsWithService:[inContact service] UID:inContact.UID]) {
		[self removeContact:contact fromMetaContact:metaContact];
	}
	[contactPropertiesObserverManager endListObjectNotificationsDelay];
}

- (void)removeContact:(AIListContact *)inContact fromMetaContact:(AIMetaContact *)metaContact
{
	//we only allow group->meta->contact, not group->meta->meta->contact
	NSParameterAssert(![inContact conformsToProtocol:@protocol(AIContainingObject)]);
	
	NSString			*metaContactInternalObjectID = [metaContact internalObjectID];
	
	//Get the dictionary of all metaContacts
	NSMutableDictionary *allMetaContactsDict = [adium.preferenceController preferenceForKey:KEY_METACONTACT_OWNERSHIP
																   group:PREF_GROUP_CONTACT_LIST];
	
	//Load the array for the metaContact
	NSArray *containedContactsArray = [allMetaContactsDict objectForKey:metaContactInternalObjectID];
	
	//Enumerate it, looking only for the appropriate type of containedContactDict
	
	NSString	*listObjectUID = inContact.UID;
	NSString	*listObjectServiceID = inContact.service.serviceID;
	
	NSDictionary *containedContactDict = nil;
	for (containedContactDict in containedContactsArray) {
		if ([[containedContactDict objectForKey:UID_KEY] isEqualToString:listObjectUID] &&
			[[containedContactDict objectForKey:SERVICE_ID_KEY] isEqualToString:listObjectServiceID]) {
			break;
		}
	}
	
	//If we found a matching dict (referring to our contact in the old metaContact), remove it and store the result
	if (containedContactDict) {
		NSMutableArray		*newContainedContactsArray;
		NSMutableDictionary	*newAllMetaContactsDict;
		
		newContainedContactsArray = [containedContactsArray mutableCopy];
		[newContainedContactsArray removeObjectIdenticalTo:containedContactDict];
		
		newAllMetaContactsDict = [allMetaContactsDict mutableCopy];
		[newAllMetaContactsDict setObject:newContainedContactsArray
								   forKey:metaContactInternalObjectID];
		
		[self _saveMetaContacts:newAllMetaContactsDict];
		
		[newContainedContactsArray release];
		[newAllMetaContactsDict release];
	}
	
	//The listObject can be within the metaContact without us finding a containedContactDict if we are removing multiple
	//listContacts referring to the same UID & serviceID combination - that is, on multiple accounts on the same service.
	//We therefore request removal of the object regardless of the if (containedContactDict) check above.
	[metaContact removeObject:inContact];
	
	[self _didChangeContainer:metaContact object:inContact];
}

/*!
 * @brief Determine the existing metacontact into which a grouping of UIDs and services would be placed
 *
 * @param UIDsArray NSArray of UIDs
 * @param servicesArray NSArray of serviceIDs corresponding to entries in UIDsArray
 * 
 * @result Either the existing AIMetaContact -[self groupUIDs:forServices:usingMetaContactHint:] would return if passed a nil metaContactHint,
 *         or nil (if no existing metacontact would be used).
 */
- (AIMetaContact *)knownMetaContactForGroupingUIDs:(NSArray *)UIDsArray forServices:(NSArray *)servicesArray
{
	AIMetaContact	*metaContact = nil;
	NSInteger count = [UIDsArray count];
	
	for (NSInteger i = 0; i < count; i++) {
		if ((metaContact = [contactToMetaContactLookupDict objectForKey:[AIListObject internalObjectIDForServiceID:[servicesArray objectAtIndex:i]
																											   UID:[UIDsArray objectAtIndex:i]]])) {
			break;
		}
	}
	
	return metaContact;
}

/*!
 * @brief Groups UIDs for services into a single metacontact
 *
 * UIDsArray and servicesArray should be a paired set of arrays, with each index corresponding to
 * a UID and a service, respectively, which together define a contact which should be included in the grouping.
 *
 * Assumption: This is only called after the contact list is finished loading, which occurs via
 * -(void)controllerDidLoad above.
 *
 * @param UIDsArray NSArray of UIDs
 * @param servicesArray NSArray of serviceIDs corresponding to entries in UIDsArray
 * @param metaContactHint If passed, an AIMetaContact to use for the grouping if an existing one isn't found. If nil, a new metacontact will be craeted in that case.
 */
- (AIMetaContact *)groupUIDs:(NSArray *)UIDsArray forServices:(NSArray *)servicesArray usingMetaContactHint:(AIMetaContact *)metaContactHint
{
	NSMutableSet *internalObjectIDs = [[NSMutableSet alloc] init];
	AIMetaContact *metaContact = nil;
	NSString *internalObjectID;
	NSInteger count = [UIDsArray count];
	
	/* Build an array of all contacts matching this description (multiple accounts on the same service listing
	 * the same UID mean that we can have multiple AIListContact objects with a UID/service combination)
	 */
	for (NSUInteger i = 0; i < count; i++) {
		NSString	*serviceID = [servicesArray objectAtIndex:i];
		NSString	*UID = [UIDsArray objectAtIndex:i];
		
		internalObjectID = [AIListObject internalObjectIDForServiceID:serviceID
																  UID:UID];
		if(!metaContact) {
			metaContact = [contactToMetaContactLookupDict objectForKey:internalObjectID];
		}
		
		[internalObjectIDs addObject:internalObjectID];
	}
	
	if ([internalObjectIDs count] > 1) {
		//Create a new metaContact is we didn't find one and weren't supplied a hint
		if (!metaContact && !(metaContact = metaContactHint)) {
			AILogWithSignature(@"New metacontact to group %@ on %@", UIDsArray, servicesArray);
			metaContact = [self metaContactWithObjectID:nil];
		}
		
		for (internalObjectID in internalObjectIDs) {
			AIListObject	*existingObject;
			if ((existingObject = [self existingListObjectWithUniqueID:internalObjectID])) {
				/* If there is currently an object (or multiple objects) matching this internalObjectID
				 * we should add immediately.
				 */
				NSAssert([existingObject isKindOfClass:[AIListContact class]], @"Attempting to add a non-AIListContact to an AIMetaContact");
				[self addContact:(AIListContact *)existingObject
					  toMetaContact:metaContact];	
			} else {
				/* If no objects matching this internalObjectID exist, we can simply add to the 
				 * contactToMetaContactLookupDict for use if such an object is created later.
				 */
				[contactToMetaContactLookupDict setObject:metaContact
												   forKey:internalObjectID];			
			}
		}
	}

	[internalObjectIDs release];
	
	return metaContact;
}

/* @brief Group an NSArray of AIListContacts, returning the meta contact into which they are added.
 *
 * This will reuse an existing metacontact (for one of the contacts in the array) if possible.
 * @param contactsToGroupArray Contacts to group together
 */
- (AIMetaContact *)groupContacts:(NSArray *)contactsToGroupArray
{
	AIMetaContact   *metaContact = nil;

	//Look for a metacontact we were passed directly
	for (AIListContact *listContact in contactsToGroupArray) {
		if ([listContact isKindOfClass:[AIMetaContact class]]) {
			metaContact = (AIMetaContact *)listContact;
			break;
		}
	}

	//If we weren't passed a metacontact, look for an existing metacontact associated with a passed contact
	if (!metaContact) {
		for (AIListContact *listContact in contactsToGroupArray) {
			if (![listContact isKindOfClass:[AIMetaContact class]] &&
				(metaContact = [contactToMetaContactLookupDict objectForKey:[listContact internalObjectID]])) {
					break;
			}
		}
	}

	//Create a new metaContact is we didn't find one.
	if (!metaContact) {
		AILogWithSignature(@"New metacontact to group %@", contactsToGroupArray);
		metaContact = [self metaContactWithObjectID:nil];
	}
	
	/* Add all these contacts to our MetaContact.
	 * Some may already be present, but that's fine, as nothing will happen.
	 */
	for (AIListContact *listContact in contactsToGroupArray) {
		[self addContact:listContact toMetaContact:metaContact];
	}
	
	return metaContact;
}

- (void)breakdownAndRemoveMetaContact:(AIMetaContact *)metaContact
{
	//Remove the objects within it from being inside it
	NSArray	*containedObjects = [metaContact.containedObjects copy];
	NSSet	*groups = metaContact.groups;
	
	NSMutableDictionary *allMetaContactsDict = [[adium.preferenceController preferenceForKey:KEY_METACONTACT_OWNERSHIP
																						 group:PREF_GROUP_CONTACT_LIST] mutableCopy];
	
	for (AIListContact *object in containedObjects) {
		
		//Remove from the contactToMetaContactLookupDict first so we don't try to reinsert into this metaContact
		[contactToMetaContactLookupDict removeObjectForKey:[object internalObjectID]];
		
		[self removeContact:object fromMetaContact:metaContact];
	}
	
	//Then, procede to remove the metaContact
	
	//Protect!
	[metaContact retain];
	
	//Remove it from its containing groups
	for (AIListGroup *group in groups) {
		[group removeObject:metaContact];
	}
	
	NSString	*metaContactInternalObjectID = [metaContact internalObjectID];
	
	//Remove our reference to it internally
	[metaContactDict removeObjectForKey:metaContactInternalObjectID];
	
	//Remove it from the preferences dictionary
	[allMetaContactsDict removeObjectForKey:metaContactInternalObjectID];
	
	//XXX - contactToMetaContactLookupDict
	
	//Post the list changed notification for the old containingObject
	for (AIListGroup *group in groups) {
		[self _didChangeContainer:group object:metaContact];
	}
	
	//Save the updated allMetaContactsDict which no longer lists the metaContact
	[self _saveMetaContacts:allMetaContactsDict];
	
	//Protection is overrated.
	[metaContact release];
	[containedObjects release];
	[allMetaContactsDict release];
}

- (void)_saveMetaContacts:(NSDictionary *)allMetaContactsDict
{
	AILog(@"MetaContacts: Saving!");
	[adium.preferenceController setPreference:allMetaContactsDict
										 forKey:KEY_METACONTACT_OWNERSHIP
										  group:PREF_GROUP_CONTACT_LIST];
	[adium.preferenceController setPreference:[allMetaContactsDict allKeys]
										 forKey:KEY_FLAT_METACONTACTS
										  group:PREF_GROUP_CONTACT_LIST];
}

//Sort list objects alphabetically by their display name
NSInteger contactDisplayNameSort(AIListObject *objectA, AIListObject *objectB, void *context)
{
	return [[objectA displayName] caseInsensitiveCompare:[objectB displayName]];
}

#pragma mark Preference observing
/*!
 * @brief Preferences changed
 */
- (void)preferencesChangedForGroup:(NSString *)group key:(NSString *)key
							object:(AIListObject *)object preferenceDict:(NSDictionary *)prefDict firstTime:(BOOL)firstTime
{
	if (!key ||
		[key isEqualToString:KEY_HIDE_CONTACTS] ||
		[key isEqualToString:KEY_SHOW_OFFLINE_CONTACTS] ||
		[key isEqualToString:KEY_USE_OFFLINE_GROUP] ||
		[key isEqualToString:KEY_HIDE_CONTACT_LIST_GROUPS]) {

		BOOL shouldUseOfflineGroup = ((![[prefDict objectForKey:KEY_HIDE_CONTACTS] boolValue] ||
									   [[prefDict objectForKey:KEY_SHOW_OFFLINE_CONTACTS] boolValue]) &&
									  [[prefDict objectForKey:KEY_USE_OFFLINE_GROUP] boolValue]);

		BOOL newlyRegistered = NO;
		
		if (shouldUseOfflineGroup != useOfflineGroup) {
			useOfflineGroup = shouldUseOfflineGroup;
			
			if (useOfflineGroup) {
				[contactPropertiesObserverManager registerListObjectObserver:self];
				newlyRegistered = YES;
			} else {
				[contactPropertiesObserverManager unregisterListObjectObserver:self];    
			}
		}
		
		if (!newlyRegistered && key)
			[contactPropertiesObserverManager updateAllListObjectsForObserver:self];	
	}
}

/*!
 * @brief Move contacts to and from the offline group as necessary as their online state changes.
 */
- (NSSet *)updateListObject:(AIListObject *)inObject keys:(NSSet *)inModifiedKeys silent:(BOOL)silent
{
	if (inModifiedKeys && [inModifiedKeys containsObject:@"Online"])
		return nil;
		
	if (![inObject isKindOfClass:[AIListContact class]])
		return nil;
	
	//If this contact is in a meta, don't bother since we'll get an update for the parent if appropriate
	if (((AIListContact *)inObject).metaContact)
		return nil;
	
	NSSet *groups = ((AIListContact *)inObject).groups;
	
	if (useOfflineGroup && useContactListGroups) {
		
		if (inObject.online && [groups containsObject:self.offlineGroup]) {
			[(AIListContact *)inObject restoreGrouping];
			
		} else if (!inObject.online && groups.count > 0 && ![groups containsObject:self.offlineGroup]) {
			[self _moveContactLocally:(AIListContact *)inObject
							 toGroups:[NSSet setWithObject:self.offlineGroup]];
		}
		
	} else if ([groups containsObject:self.offlineGroup]) {
		[(AIListContact *)inObject restoreGrouping];
	}
	
	return nil;
}

#pragma mark Contact Sorting

//Sort the entire contact list
- (void)sortContactList
{
	[self sortContactLists:contactLists];
}

- (void)sortContactLists:(NSArray *)lists
{
	for(AIContactList *list in lists) {
		[list sort];
	}
	[adium.notificationCenter postNotificationName:Contact_OrderChanged object:nil];
}

//Sort an individual object
- (void)sortListObject:(AIListObject *)inObject
{
	if ([contactPropertiesObserverManager updatesAreDelayed]) {
		[contactPropertiesObserverManager noteContactChanged:inObject];

	} else {
		for (AIListGroup *group in inObject.groups) {
			//Sort the groups containing this object
			[group sortListObject:inObject];
			[adium.notificationCenter postNotificationName:Contact_OrderChanged object:group];
		}
	}
}

#pragma mark Contact List Access

@synthesize contactList;

/*!
 * @brief Return an array of all contact list groups
 */
- (NSArray *)allGroups
{
	return [groupDict allValues];
}

/*!
 * @brief Returns a flat array of all contacts
 *
 * This does not include metacontacts
 */
- (NSArray *)allContacts
{
	NSMutableArray *result = [[[NSMutableArray alloc] init] autorelease];

	for (AIListContact *contact in self.contactEnumerator) {
		/* We want only contacts, not metacontacts. For a given contact, -[contact parentContact] could be used to access the meta. */
		if (![contact conformsToProtocol:@protocol(AIContainingObject)])
			[result addObject:contact];
	}
	
	return result;
}

/*!
 * @brief Returns a flat array of all metacontacts
 */
- (NSArray *)allMetaContacts
{
	return [metaContactDict allValues];
}

//Return a flat array of all the objects in a group on an account (and all subgroups, if desired)
- (NSArray *)allContactsInObject:(AIListObject<AIContainingObject> *)inGroup onAccount:(AIAccount *)inAccount
{
	NSParameterAssert(inGroup != nil);
	
	NSMutableArray	*contactArray = [NSMutableArray array];    
	
	for (AIListObject *object in inGroup) {
		if ([object conformsToProtocol:@protocol(AIContainingObject)]) {
			[contactArray addObjectsFromArray:[self allContactsInObject:(AIListObject<AIContainingObject> *)object
															  onAccount:inAccount]];
		} else if ([object isMemberOfClass:[AIListContact class]] && (!inAccount || ([(AIListContact *)object account] == inAccount)))
			[contactArray addObject:object];
	}
	
	return contactArray;
}

//Return a flat array of all the bookmarks in a group on an account (and all subgroups, if desired)
- (NSArray *)allBookmarksInObject:(AIListObject<AIContainingObject> *)inGroup
{
	NSParameterAssert(inGroup != nil);
	
	NSMutableArray	*bookmarkArray = [NSMutableArray array];    
	
	for (AIListObject *object in inGroup) {
		if ([object conformsToProtocol:@protocol(AIContainingObject)]) {
			[bookmarkArray addObjectsFromArray:[self allBookmarksInObject:(AIListObject<AIContainingObject> *)object]];
		} else if ([object isKindOfClass:[AIListBookmark class]]) {
			[bookmarkArray addObject:object];
		}
	}
	
	return bookmarkArray;
}

- (NSArray *)allBookmarks
{
	NSMutableArray *result = [NSMutableArray array];
	
	/** Could be perfected I'm sure */
	for(AIContactList *clist in contactLists) {
		[result addObjectsFromArray:[self allBookmarksInObject:clist]];
	}
	
	return result;	
}

#pragma mark Contact List Menus

//Returns a menu containing all the groups within a group
//- Selector called on group selection is selectGroup:
//- The menu items represented object is the group it represents
- (NSMenu *)groupMenuWithTarget:(id)target
{
	NSMenu	*menu = [[NSMenu alloc] initWithTitle:@""];
	
	[menu setAutoenablesItems:NO];
	
	for(AIListGroup *group in self.allGroups) {
		if (group != self.offlineGroup) {
			NSMenuItem	*menuItem = [[NSMenuItem allocWithZone:[NSMenu menuZone]] initWithTitle:group.displayName
													target:target
													action:@selector(selectGroup:)
												 keyEquivalent:@""];
			[menuItem setRepresentedObject:group];
			[menu addItem:menuItem];
			[menuItem release];
		}
	}
	
	return [menu autorelease];
}

#pragma mark Retrieving Specific Contacts

- (AIListContact *)contactWithService:(AIService *)inService account:(AIAccount *)inAccount UID:(NSString *)inUID
{
	if (!(inUID && [inUID length] && inService)) return nil; //Ignore invalid requests
	
	AIListContact	*contact = nil;
	NSString		*key = [AIListContact internalUniqueObjectIDForService:inService
															account:inAccount
																UID:inUID];
	contact = [contactDict objectForKey:key];
	if (!contact) {
		//Create
		contact = [[AIListContact alloc] initWithUID:inUID account:inAccount service:inService];
		
		//Check to see if we should add to a metaContact
		AIMetaContact *metaContact = [contactToMetaContactLookupDict objectForKey:[contact internalObjectID]];
		if (metaContact) {
			/* We already know to add this object to the metaContact, since we did it before with another object,
			 but this particular listContact is new and needs to be added directly to the metaContact
			 (on future launches, the metaContact will obtain it automatically since all contacts matching this UID
			 and serviceID should be included). */
			[self _performAddContact:contact toMetaContact:metaContact];
		}
		
		//Set the contact as mobile if it is a phone number
		if ([inUID characterAtIndex:0] == '+') {
			[contact setIsMobile:YES notify:NotifyNever];
		}
		
		//Add
		[contactDict setObject:contact forKey:key];

		//Do the update thing
		[contactPropertiesObserverManager _updateAllAttributesOfObject:contact];

		[contact release];
	}
	
	return contact;
}

- (void)accountDidStopTrackingContact:(AIListContact *)inContact
{
	[[inContact retain] autorelease];

	/* Remove after a short delay. Otherwise, the removal may be visible as the object remains in the contact
	 * list until a display delay is over, which would show up as the name going blank on metacontacts and other
	 * odd behavior.
	 *
	 * Of course, this really means that the object delay code is somehow failing to actually delay all updates.
	 * I can't figure out where or why, so this is a hack around it. Ugh. -evands 10/08
	 */
	for (AIListObject<AIContainingObject> *container in inContact.containingObjects) {
		[container performSelector:@selector(removeObjectAfterAccountStopsTracking:)
		 withObject:inContact
		 afterDelay:1];
	}
	
	[contactDict removeObjectForKey:inContact.internalUniqueObjectID];
}

- (AIListBookmark *)bookmarkForChat:(AIChat *)inChat
{
	AIListBookmark *bookmark = [bookmarkDict objectForKey:inChat.uniqueChatID];
	
	if (!bookmark) {
		bookmark = [[[AIListBookmark alloc] initWithChat:inChat] autorelease];
		[bookmarkDict setObject:bookmark forKey:inChat.uniqueChatID];
	}
	
	//Do the update thing
	[contactPropertiesObserverManager _updateAllAttributesOfObject:bookmark];
	
	return bookmark;
}

- (AIListContact *)existingContactWithService:(AIService *)inService account:(AIAccount *)inAccount UID:(NSString *)inUID
{
	if (inService && [inUID length]) {
		return [contactDict objectForKey:[AIListContact internalUniqueObjectIDForService:inService
											account:inAccount
											    UID:inUID]];
	}
	return nil;
}

/*!
 * @brief Return a set of all contacts with a specified UID and service
 *
 * @param service The AIService in question
 * @param inUID The UID, which should be normalized (lower case, no spaces, etc.) as appropriate for the service
 */
- (NSSet *)allContactsWithService:(AIService *)service UID:(NSString *)inUID
{
	NSMutableSet	*returnContactSet = [NSMutableSet set];

	for (AIAccount *account in [adium.accountController accountsCompatibleWithService:service]) {
		AIListContact *listContact = [self existingContactWithService:service
														account:account
															UID:inUID];
		
		if (listContact) {
			[returnContactSet addObject:listContact];
		}
	}
	
	return returnContactSet;
}

- (AIListObject *)existingListObjectWithUniqueID:(NSString *)uniqueID
{	
	//Contact
	for (AIListObject *listObject in contactDict.objectEnumerator) {
		if ([listObject.internalObjectID isEqualToString:uniqueID]) return listObject;
	}
	
	//Group
	for (AIListGroup *listObject in groupDict.objectEnumerator) {
		if ([listObject.internalObjectID isEqualToString:uniqueID]) return listObject;
	}
	
	//Metacontact
	for (AIMetaContact *listObject in metaContactDict.objectEnumerator) {
		if ([listObject.internalObjectID isEqualToString:uniqueID]) return listObject;
	}
	
	return nil;
}

/*!
 * @brief Get the best AIListContact to send a given content type to a contat
 *
 * The resulting AIListContact will be the most available individual contact (not metacontact) on the best account to
 * receive the specified content type.
 *
 * @result The contact, or nil if it is impossible to send inType to inContact
 */
- (AIListContact *)preferredContactForContentType:(NSString *)inType forListContact:(AIListContact *)inContact
{
	AIListContact   *returnContact = nil;
	
	if ([inContact isKindOfClass:[AIMetaContact class]] && [(AIMetaContact *)inContact uniqueContainedObjectsCount] > 1) {
		AIListObject	*preferredContact;
		
		/* If we've messaged this object previously, prefer the last contact we sent to if that
		 * contact is currently in the most-available status the metacontact can offer
		 */
		NSString *internalObjectID = [inContact preferenceForKey:KEY_PREFERRED_DESTINATION_CONTACT group:OBJECT_STATUS_CACHE];
		
		if ((internalObjectID) &&
			(preferredContact = [self existingListObjectWithUniqueID:internalObjectID]) &&
			([preferredContact isKindOfClass:[AIListContact class]]) &&
			([preferredContact statusSummary] == [inContact statusSummary]) &&
			([inContact isMobile] || ![preferredContact isMobile]) && //Either the parent contact is mobile (so that's the best we have), or the preferred is not.
			([(id<AIContainingObject>)inContact containsObject:preferredContact])) {

			returnContact = [self preferredContactForContentType:inType
												  forListContact:(AIListContact *)preferredContact];
        }
		
		/* If the last contact we sent to is not appropriate, use the following algorithm, which differs from -[AIMetaContact preferredContact]
		 * in that it doesn't "like" mobile contacts.
		 *
		 *  1) Prefer available contacts who are not mobile
		 *  2) If no available non-mobile contacts, use the first online contact
		 *  3) If no online contacts, use the metacontact's preferredContact
		 */
		if (!returnContact) {
			//Recurse into metacontacts if necessary
			AIListContact *firstAvailableContact = nil;
			AIListContact *firstNotOfflineContact = nil;
			
			for (AIListContact *thisContact in (id <AIContainingObject>)inContact) {
				AIStatusType statusSummary = [thisContact statusSummary];
				
				if ((statusSummary != AIOfflineStatus) && (statusSummary != AIUnknownStatus)) {
					if (!firstNotOfflineContact) {
						firstNotOfflineContact = thisContact;
					}
					
					if (statusSummary == AIAvailableStatus && ![thisContact isMobile]) {
						if (!firstAvailableContact) {
							firstAvailableContact = thisContact;
						}
						
						break;
					}
				}
			}
			
			returnContact = (firstAvailableContact ?
							 firstAvailableContact :
							 (firstNotOfflineContact ? firstNotOfflineContact : [(AIMetaContact *)inContact preferredContact]));
			
			returnContact = [self preferredContactForContentType:inType forListContact:returnContact];
		}
		
	} else {
		//This contact doesn't contain multiple contacts... but it might still be a metacontact. Do NOT proceed with a metacontact.
		if ([inContact respondsToSelector:@selector(preferredContact)])
			inContact = [inContact performSelector:@selector(preferredContact)];
		
		/* Find the best account for talking to this contact, and return an AIListContact on that account.
		 * We'll get nil if no account can send inType to inContact.
		 */
		AIAccount *account = [adium.accountController preferredAccountForSendingContentType:inType
																		 toContact:inContact];

		if (account) {
			if ([inContact account] == account) {
				returnContact = inContact;
			} else {
				returnContact = [self contactWithService:[inContact service]
												 account:account
													 UID:inContact.UID];
			}
		}
 	}

	return returnContact;
}

//Retrieve a list contact matching the UID and serviceID of the passed contact but on the specified account.
//In many cases this will be the same as inContact.
- (AIListContact *)contactOnAccount:(AIAccount *)account fromListContact:(AIListContact *)inContact
{
	if (account && ([inContact account] != account)) {
		return [self contactWithService:[inContact service] account:account UID:inContact.UID];
	} else {
		return inContact;
	}
}

//XXX - This is ridiculous.
- (AIListContact *)preferredContactWithUID:(NSString *)inUID andServiceID:(NSString *)inService forSendingContentType:(NSString *)inType
{
	AIService		*theService = [adium.accountController firstServiceWithServiceID:inService];
	AIListContact	*tempListContact = [[AIListContact alloc] initWithUID:inUID
																service:theService];
	AIAccount		*account = [adium.accountController preferredAccountForSendingContentType:CONTENT_MESSAGE_TYPE
																				 toContact:tempListContact];
	[tempListContact release];

	return [self contactWithService:theService account:account UID:inUID];
}


/*!
 * @brief Watch outgoing content, remembering the user's choice of destination contact for contacts within metaContacts
 *
 * If the destination contact's parent contact differs from the destination contact itself, the chat is with a metaContact.
 * If that metaContact's preferred destination for messaging isn't the same as the contact which was just messaged,
 * update the preference so that a new chat with this metaContact would default to the proper contact.
 */
- (void)didSendContent:(NSNotification *)notification
{
	AIChat			*chat = [[notification userInfo] objectForKey:@"AIChat"];
	AIListContact	*destContact = chat.listObject;
	AIListContact	*metaContact = destContact.metaContact;
	
	if (!metaContact) 
		return;
	
	NSString	*destinationInternalObjectID = [destContact internalObjectID];
	NSString	*currentPreferredDestination = [metaContact preferenceForKey:KEY_PREFERRED_DESTINATION_CONTACT group:OBJECT_STATUS_CACHE];
	
	if (![destinationInternalObjectID isEqualToString:currentPreferredDestination]) {
		[metaContact setPreference:destinationInternalObjectID
							forKey:KEY_PREFERRED_DESTINATION_CONTACT
							 group:OBJECT_STATUS_CACHE];
	}
}

#pragma mark Retrieving Groups

//Retrieve a group from the contact list (Creating if necessary)
- (AIListGroup *)groupWithUID:(NSString *)groupUID
{
	NSParameterAssert(groupUID != nil);
	
	//Return our root group if it is requested. 
	if ([groupUID isEqualToString:ADIUM_ROOT_GROUP_NAME])
		return [self contactList];
	
	AIListGroup		*group = nil;
	if (!(group = [groupDict objectForKey:[groupUID lowercaseString]])) {
		//Create
		group = [[AIListGroup alloc] initWithUID:groupUID];
		
		//Add
		[contactPropertiesObserverManager _updateAllAttributesOfObject:group];
		[groupDict setObject:group forKey:[groupUID lowercaseString]];
		
		//Add to the contact list
		[contactList addObject:group];
		[self _didChangeContainer:contactList object:group];
		[group release];
	}
	
	return group;
}

#pragma mark Contact list editing
- (void)removeListObjects:(NSArray *)objectArray
{	
	for (AIListObject *listObject in objectArray) {
		if ([listObject isKindOfClass:[AIMetaContact class]]) {
			NSSet	*objectsToRemove = nil;
			
			//If the metaContact only has one listContact, we will remove that contact from all accounts
			if ([(AIMetaContact *)listObject uniqueContainedObjectsCount] == 1) {
				AIListContact	*listContact = [[(AIMetaContact *)listObject uniqueContainedObjects] objectAtIndex:0];
				
				objectsToRemove = [self allContactsWithService:[listContact service] UID:listContact.UID];
			}
			
			//And actually remove the single contact if applicable
			if (objectsToRemove) {
				[self removeListObjects:[objectsToRemove allObjects]];
			}
			
			//Now break the metaContact down, taking out all contacts and putting them back in the main list
			[self breakdownAndRemoveMetaContact:(AIMetaContact *)listObject];				
			
		} else if ([listObject isKindOfClass:[AIListGroup class]]) {
			AIContactList	*containingObject = ((AIListGroup *)listObject).contactList;
			
			//If this is a group, delete all the objects within it
			[self removeListObjects:[(AIListGroup *)listObject containedObjects]];
			
			//Delete the list off of all active accounts
			for (AIAccount *account in adium.accountController.accounts) {
				if (account.online) {
					[account deleteGroup:(AIListGroup *)listObject];
				}
			}
			
			//Then, procede to delete the group
			[listObject retain];
			[containingObject removeObject:listObject];
			[groupDict removeObjectForKey:[listObject.UID lowercaseString]];
			[self _didChangeContainer:containingObject object:listObject];
			[listObject release];
			
		} else {
			AIAccount	*account = [(AIListContact *)listObject account];
			if (account.online) {
				[account removeContacts:[NSArray arrayWithObject:listObject]];
			}
		}
	}
}

- (void)requestAddContactWithUID:(NSString *)contactUID service:(AIService *)inService account:(AIAccount *)inAccount
{
	NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:contactUID
																	   forKey:UID_KEY];
	if (inService) [userInfo setObject:inService forKey:@"AIService"];
	if (inAccount) [userInfo setObject:inAccount forKey:@"AIAccount"];
	
	[adium.notificationCenter postNotificationName:Contact_AddNewContact
											  object:nil
											userInfo:userInfo];
}

//XXX multiple containers , needs to a) handle indices properly, and b) handle add vs move properly, c) not do the silly rewrapping of groups into sets of 1
- (void)moveListObjects:(NSArray *)objectArray intoObjects:(NSSet *)containers index:(NSUInteger)index
{		
	for (AIListObject<AIContainingObject> *group in containers) {
		[contactPropertiesObserverManager delayListObjectNotifications];

		if ([group respondsToSelector:@selector(setDelayContainedObjectSorting:)]) {
			[(id)group setDelayContainedObjectSorting:YES];
		}
		
		for (AIListObject *listObject in objectArray) {
			[self moveObject:listObject intoObjects:[NSSet setWithObject:group]];
			
			//Set the new index / position of the object
			[self _positionObject:listObject atIndex:index inObject:group];
		}
		
		[contactPropertiesObserverManager endListObjectNotificationsDelay];
		
		if ([group respondsToSelector:@selector(setDelayContainedObjectSorting:)]) {
			[(id)group setDelayContainedObjectSorting:NO];
		}
		
		/*
		 Resort the entire list if we are moving within or between AIListGroup objects
		 (other containing objects such as metaContacts will handle their own sorting).
		 */
		if ([group isKindOfClass:[AIListGroup class]]) {
			[self sortContactLists:[NSArray arrayWithObject:group]];
		}
	}
}

- (void)moveObject:(AIListObject *)listObject intoObjects:(NSSet *)containers
{
	//Move the object to the new group only if necessary
	if ([listObject.groups isEqual:containers]) return;
	AIListObject<AIContainingObject> *container = containers.anyObject;
	
	if ([container isKindOfClass:[AIContactList class]] &&
		[listObject isKindOfClass:[AIListGroup class]]) {
		NSParameterAssert(containers.count == 1); //groups can't be in multiple contact lists
		// Move contact from one contact list to another
		[((AIListGroup *)listObject).contactList moveGroup:(AIListGroup *)listObject to:(AIContactList *)containers.anyObject];

	} else if ([container isKindOfClass:[AIListGroup class]]) {
		//Move a contact into a new group
		if ([listObject isKindOfClass:[AIListBookmark class]]) {
			[self _moveContactLocally:(AIListBookmark *)listObject toGroups:containers];
			
		} else if ([listObject isKindOfClass:[AIMetaContact class]]) {
			//Move the meta contact to these new groups
			[self _moveContactLocally:(AIMetaContact *)listObject toGroups:containers];
			
			//This is a meta contact, move the objects within it.  listContacts will give us a flat array of AIListContacts.
			for (AIListContact *actualListContact in (AIMetaContact *)listObject) {
				//Only move the contact if it is actually listed on the account in question
				if (![actualListContact isStranger]) {
					[self _moveContactServerside:actualListContact toGroups:containers];
				}
			}
		} else if ([listObject isKindOfClass:[AIListContact class]]) {
			//Move the object
			if ([[(AIListContact *)listObject parentContact] isKindOfClass:[AIMetaContact class]]) {
				[self removeAllContactsMatching:(AIListContact *)listObject fromMetaContact:(AIMetaContact *)[(AIListContact *)listObject parentContact]];
			}
			
			[self _moveContactServerside:(AIListContact *)listObject toGroups:containers];

		} else {
			AILogWithSignature(@"I don't know what to do with %@",listObject);
		}
	} else if ([container isKindOfClass:[AIMetaContact class]]) {
		//Moving a contact into a meta contact
		NSParameterAssert([listObject isKindOfClass:[AIListContact class]]);
		NSParameterAssert(containers.count == 1);
		if (((AIListContact *)listObject).metaContact != container)
			[self addContact:(AIListContact*)listObject toMetaContact:(AIMetaContact *)container];
	}
}

//Move an object to another group
- (void)_moveContactServerside:(AIListContact *)listContact toGroups:(NSSet *)groups
{
	AIAccount	*account = listContact.account;
	if (account.online) {
		[account moveListObjects:[NSArray arrayWithObject:listContact] toGroups:groups];
	}
}

//Rename a group
- (void)_renameGroup:(AIListGroup *)listGroup to:(NSString *)newName
{
	//Since Adium has no memory of what accounts a group is on, we have to send this message to all available accounts
	//The accounts without this group will just ignore it
	for (AIAccount *account in adium.accountController.accounts) {
		[account renameGroup:listGroup to:newName];
	}
	
	//Remove the old group if it's empty
	if (listGroup.containedObjectsCount == 0) {
		[self removeListObjects:[NSArray arrayWithObject:listGroup]];
	}
}

//Position a list object within a group
- (void)_positionObject:(AIListObject *)listObject atIndex:(NSInteger)index inObject:(AIListObject<AIContainingObject> *)group
{
	if (index == 0) {
		//Moved to the top of a group.  New index is between 0 and the lowest current index
		listObject.orderIndex = group.smallestOrder / 2.0;
		
	} else if (index >= group.visibleCount) {
		//Moved to the bottom of a group.  New index is one higher than the highest current index
		listObject.orderIndex = group.largestOrder + 1.0;
		
	} else {
		//Moved somewhere in the middle.  New index is the average of the next largest and smallest index
		AIListObject	*previousObject = [group.containedObjects objectAtIndex:index-1];
		AIListObject	*nextObject = [group.containedObjects objectAtIndex:index];
		CGFloat nextLowest = previousObject.orderIndex;
		CGFloat nextHighest = nextObject.orderIndex;
		
		/* XXX - Fixme as per below
		 * It's possible that nextLowest > nextHighest if ordering is not strictly based on the ordering indexes themselves.
		 * For example, a group sorted by status then manually could look like (status - ordering index):
		 *
		 * Away Contact - 100
		 * Away Contact - 120
		 * Offline Contact - 110
		 * Offline Contact - 113
		 * Offline Contact - 125
		 * 
		 * Dropping between Away Contact and Offline Contact should make an Away Contact be > 120 but an Offline Contact be < 110.
		 * Only the sort controller knows the answer as to where this contact should be positioned in the end.
		 */
		listObject.orderIndex = (nextHighest + nextLowest) / 2.0;
	}
}

#pragma mark Detached Contact Lists

/*!
 * @returns Empty contact list
 */
- (AIContactList *)createDetachedContactList
{
	static NSInteger count = 0;
	AIContactList *list = [[AIContactList alloc] initWithUID:[NSString stringWithFormat:@"Detached%ld",count++]];
	[contactLists addObject:list];
	[list release];
	return list;
}

/*!
 * @brief Removes detached contact list
 */
- (void)removeDetachedContactList:(AIContactList *)detachedList
{
	[contactLists removeObject:detachedList];
}

@end

@implementation AIContactController (ContactControllerHelperAccess)
- (NSEnumerator *)contactEnumerator
{
	return [contactDict objectEnumerator];
}
- (NSEnumerator *)groupEnumerator
{
	return [groupDict objectEnumerator];
}
@end
