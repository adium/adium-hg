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

#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIListGroup.h>
#import <Adium/AISortController.h>
#import <AIUtilities/AIArrayAdditions.h>
#import <Adium/AIContactList.h>

static NSSet* visibleObjectCountProperty;

@implementation AIListGroup

//init
- (id)initWithUID:(NSString *)inUID
{
	if ((self = [super initWithUID:inUID service:nil])) {
		_containedObjects = [[NSMutableArray alloc] init];
		expanded = YES;

		//Default invisible
		if(!visibleObjectCountProperty)
			visibleObjectCountProperty = [[NSSet alloc] initWithObjects:@"VisibleObjectCount", nil];
		visible = NO;
	}
	
	return self;
}

- (void)dealloc
{
	[_containedObjects release]; _containedObjects = nil;
	
	[super dealloc];
}

/* An object ID generated by Adium that is shared by all objects which are, to most intents and purposes, identical to
 * this object.  Ths ID is composed of the service ID and UID, so any object with identical services and object ID's
 * will have the same value here.
 */
- (NSString *)internalObjectID
{
	if (!internalObjectID) {
		internalObjectID = [[AIListObject internalObjectIDForServiceID:@"Group" UID:[self UID]] retain];
	}
	return internalObjectID;
}

/*!
 * @brief Generate a special identifier for this group based upon its contents
 *
 * This is useful for storing preferences which are related not to the name of this group (which might be arbitrary) but
 * rather to its contents. The contact list root always returns its own UID, but other groups will have a different 
 * contentsBasedIdentifier depending upon what other objects they contain.
 */
- (NSString *)contentsBasedIdentifier
{
	NSArray *UIDArray = [[self.containedObjects valueForKey:@"UID"] sortedArrayUsingSelector:@selector(compare:)];
	NSString *contentsBasedIdentifier = [UIDArray componentsJoinedByString:@";"];
	if (![contentsBasedIdentifier length]) contentsBasedIdentifier = [self UID];

	return contentsBasedIdentifier;
}

//Visibility -----------------------------------------------------------------------------------------------------------
#pragma mark Visibility
/*
 The visible objects contained in a group are always sorted to the top.  This allows us to easily retrieve only visible
 objects without having to physically remove invisible objects from the group.
 */
- (NSUInteger) visibleCount
{
	NSUInteger visibleCount = 0;
	
	for (AIListObject *containedObject in self) {
		if (containedObject.visible)
			visibleCount++;
	}
	
	return visibleCount;
}

//Called when the visibility of an object in this group changes
- (void)visibilityOfContainedObject:(AIListObject *)inObject changedTo:(BOOL)inVisible
{
	//Sort the contained object to or from the bottom (invisible section) of the group
	[adium.contactController sortListObject:inObject];
	if(inVisible != self.visible)
		[self didModifyProperties:visibleObjectCountProperty silent:NO];
}

/*!
 * @brief Get the visibile object at a given index
 *
 * Hidden contacts will be sorted to the bottom of our contained objects array,
 * so we can just acccess the array directly
 */
- (AIListObject *)visibleObjectAtIndex:(NSUInteger)index
{
	AIListObject *obj = [self.containedObjects objectAtIndex:index];
	NSAssert5(obj.visible, @"Attempted to get visible object at index %i of %@, but %@ is not visible. With contained objects %@, visibility count is %i",
			  index, self, obj, self.containedObjects, self.visibleCount);
	return obj;
}

- (NSUInteger)visibleIndexOfObject:(AIListObject *)obj
{
	if(!obj.visible)
		return NSNotFound;
	return [self.containedObjects indexOfObject:obj];
}

//Object Storage ---------------------------------------------------------------------------------------------
#pragma mark Object Storage

@synthesize containedObjects = _containedObjects;

//Number of contained objects
- (NSUInteger)containedObjectsCount
{
    return self.containedObjects.count;
}

//Test for the presence of an object in our group
- (BOOL)containsObject:(AIListObject *)inObject
{
	return [self.containedObjects containsObject:inObject];
}

- (BOOL)containsMultipleContacts {
    return NO;
}

//Retrieve an object by index
- (id)objectAtIndex:(NSUInteger)index
{
    return [self.containedObjects objectAtIndex:index];
}

- (NSArray *)listContacts
{
	return self.containedObjects;
}

- (NSArray *)visibleListContacts
{
	return self.containedObjects;
}

//Remove all the objects from this group (PRIVATE: For contact controller only)
- (void)removeAllObjects
{
	//Remove all the objects
	while ([self.containedObjects count]) {
		[self removeObject:[self.containedObjects objectAtIndex:0]];
	}
}

//Retrieve a specific object by service and UID
- (AIListObject *)objectWithService:(AIService *)inService UID:(NSString *)inUID
{
	for (AIListObject *object in self.containedObjects) {
		if ([inUID isEqualToString:[object UID]] && [object service] == inService)
			return object;
	}
	
	return nil;
}

- (BOOL)canContainObject:(id)obj
{
	//todo: enforce metacontacts here, after making all contacts have a containing meta
	return [obj isKindOfClass:[AIListContact class]];
}

/*!
 * @brief Add an object to this group
 *
 * PRIVATE: For contact controller only. Sorting and visible count updating will be performed as needed.
 *
 * @result YES if the object was added (that is, was not already present)
 */
- (BOOL)addObject:(AIListObject *)inObject
{
	NSParameterAssert(inObject != nil);
	NSParameterAssert([self canContainObject:inObject]);
	BOOL success = NO;
	
	if (![self.containedObjects containsObjectIdenticalTo:inObject]) {
		//Add the object
		[inObject setContainingObject:self];
		[_containedObjects addObject:inObject];
		
		/* Sort this object on our own.  This always comes along with a content change, so calling contact controller's
		 * sort code would invoke an extra update that we don't need.  We can skip sorting if this object is not visible,
		 * since it will add to the bottom/non-visible section of our array.
		 */
		if ([inObject visible]) {
			[self sortListObject:inObject];
		}
		
		//
		[self setValue:[NSNumber numberWithInt:[self.containedObjects count]] 
					   forProperty:@"ObjectCount"
					   notify:NotifyNow];
		[self didModifyProperties:visibleObjectCountProperty silent:NO];
		
		success = YES;
	}
	
	return success;
}

//Remove an object from this group (PRIVATE: For contact controller only)
- (void)removeObject:(AIListObject *)inObject
{	
	if ([self.containedObjects containsObject:inObject]) {		
		//Remove the object
		if ([inObject containingObject] == self)
			[inObject setContainingObject:nil];
		[_containedObjects removeObject:inObject];
		//
		[self setValue:[NSNumber numberWithInt:[self.containedObjects count]]
					   forProperty:@"ObjectCount" 
					   notify:NotifyNow];
		[self didModifyProperties:visibleObjectCountProperty silent:NO];
	}
}

- (void)removeObjectAfterAccountStopsTracking:(AIListObject *)inObject
{
	[inObject setContainingObject:nil];
	[_containedObjects removeObject:inObject];
	
	//
	[self setValue:[NSNumber numberWithInt:[self.containedObjects count]]
	   forProperty:@"ObjectCount" 
			notify:NotifyLater];
	[self didModifyProperties:visibleObjectCountProperty silent:NO];	
}

//Sorting --------------------------------------------------------------------------------------------------------------
#pragma mark Sorting
//Resort an object in this group (PRIVATE: For contact controller only)
- (void)sortListObject:(AIListObject *)inObject
{
	AISortController *sortController = [AISortController activeSortController];
	[inObject retain];
	[_containedObjects removeObject:inObject];
	[_containedObjects insertObject:inObject 
						   atIndex:[sortController indexForInserting:inObject intoObjects:self.containedObjects]];
	[inObject release];
}

//Resorts the group contents (PRIVATE: For contact controller only)
- (void)sort
{	
	[_containedObjects sortUsingActiveSortController];
}

//Expanded State -------------------------------------------------------------------------------------------------------
#pragma mark Expanded State
//Set the expanded/collapsed state of this group (PRIVATE: For the contact list view to let us know our state)
- (void)setExpanded:(BOOL)inExpanded
{
	expanded = inExpanded;
	loadedExpanded = YES;
}
//Returns the current expanded/collapsed state of this group
- (BOOL)isExpanded
{
	if (!loadedExpanded) {
		loadedExpanded = YES;
		expanded = [[self preferenceForKey:@"IsExpanded"
									 group:@"Contact List"] boolValue];
	}

	return expanded;
}

- (BOOL)isExpandable
{
	return YES;
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id *)stackbuf count:(NSUInteger)len
{
	return [[self containedObjects] countByEnumeratingWithState:state objects:stackbuf count:len];
}

#pragma mark Applescript
- (NSScriptObjectSpecifier *)objectSpecifier
{
	NSScriptClassDescription *containerClassDesc = (NSScriptClassDescription *)[NSScriptClassDescription classDescriptionForClass:[NSApp class]];
	return [[[NSNameSpecifier alloc]
		   initWithContainerClassDescription:containerClassDesc
		   containerSpecifier:nil key:@"contactGroups"
		   name:[self UID]] autorelease];
}

- (NSArray *)contacts
{
	return self.containedObjects;
}
- (id)moveContacts:(AIListObject *)contact toIndex:(int)index
{
	[adium.contactController moveListObjects:[NSArray arrayWithObject:contact] intoObject:self index:index];
	return nil;
}

//inherit these
@dynamic largestOrder;
@dynamic smallestOrder;
@end
