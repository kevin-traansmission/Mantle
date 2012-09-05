//
//  NSArray+MAVHigherOrderAdditions.m
//  Maverick
//
//  Created by Josh Vera on 12/7/11.
//  Copyright (c) 2012 GitHub. All rights reserved.
//
//  Portions copyright (c) 2011 Bitswift. All rights reserved.
//  See the LICENSE file for more information.
//

#import "NSArray+MAVHigherOrderAdditions.h"
#import "EXTScope.h"
#import <libkern/OSAtomic.h>

@implementation NSArray (MAVHigherOrderAdditions)

- (id)mav_filterUsingBlock:(BOOL(^)(id obj))block {
    return [self mav_filterWithOptions:0 usingBlock:block];
}

- (id)mav_filterWithOptions:(NSEnumerationOptions)opts usingBlock:(BOOL(^)(id obj))block {
    return [self mav_filterWithOptions:opts failedObjects:NULL usingBlock:block];
}

- (id)mav_filterWithFailedObjects:(NSArray **)failedObjects usingBlock:(BOOL(^)(id obj))block; {
    return [self mav_filterWithOptions:0 failedObjects:failedObjects usingBlock:block];
}

- (id)mav_filterWithOptions:(NSEnumerationOptions)opts failedObjects:(NSArray **)failedObjects usingBlock:(BOOL(^)(id obj))block; {
    NSIndexSet *successIndexes = [self indexesOfObjectsWithOptions:opts passingTest:^(id obj, NSUInteger idx, BOOL *stop) {
        return block(obj);
    }];

    if (opts & NSEnumerationReverse) {
        NSMutableArray *mutableSuccess = [[NSMutableArray alloc] initWithCapacity:[successIndexes count]];

        NSMutableArray *mutableFailed = nil;
        if (failedObjects != NULL) mutableFailed = [[NSMutableArray alloc] initWithCapacity:[self count] - [successIndexes count] - 1];

        [self enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(id obj, NSUInteger index, BOOL *stop){
            if ([successIndexes containsIndex:index])
                [mutableSuccess addObject:obj];
            else
                [mutableFailed addObject:obj];
        }];

        if (failedObjects != NULL) *failedObjects = [mutableFailed copy];

        return [mutableSuccess copy];
    } else {
        if (failedObjects != NULL) {
            NSUInteger totalCount = self.count;

            NSMutableIndexSet *failedIndexes = [[NSMutableIndexSet alloc] initWithIndexesInRange:NSMakeRange(0, totalCount)];
            [failedIndexes removeIndexes:successIndexes];

            *failedObjects = [self objectsAtIndexes:failedIndexes];
        }

        return [self objectsAtIndexes:successIndexes];
    }
}

- (id)mav_foldLeftWithValue:(id)startingValue usingBlock:(id (^)(id left, id right))block; {
    __block id value = startingValue;

    [self enumerateObjectsUsingBlock:^(id obj, NSUInteger index, BOOL *stop){
        value = block(value, obj);
    }];

    return value;
}

- (id)mav_foldRightWithValue:(id)startingValue usingBlock:(id (^)(id left, id right))block; {
    __block id value = startingValue;

    [self enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(id obj, NSUInteger index, BOOL *stop){
        value = block(obj, value);
    }];

    return value;
}

- (id)mav_mapUsingBlock:(id (^)(id obj))block; {
    return [self mav_mapWithOptions:0 usingBlock:block];
}

- (id)mav_mapWithOptions:(NSEnumerationOptions)opts usingBlock:(id (^)(id obj))block; {
    NSUInteger originalCount = [self count];

    BOOL concurrent = (opts & NSEnumerationConcurrent);
    BOOL reverse = (opts & NSEnumerationReverse);

    __strong volatile id *objects = (__strong id *)calloc(originalCount, sizeof(*objects));
    if (objects == NULL) {
        return nil;
    }

    // declare this variable way up here so that it can be used in the @onExit
    // block below (avoiding unnecessary iteration)
    __block NSUInteger actualCount = originalCount;

    @onExit {
        for (NSUInteger i = 0;i < actualCount;++i) {
            // nil out everything in the array to make sure ARC releases
            // everything appropriately
            objects[i] = nil;
        }

        free((void *)objects);
    };

    // if this gets incremented while enumerating, 'objects' contains some
    // (indeterminate) number of nil values, and must be compacted before
    // creating an NSArray
    volatile int32_t needsCompaction = 0;

    {
        // create a pointer outside of the block so that we don't have to use the
        // __block qualifier in order to pass this variable to atomic functions
        volatile int32_t *needsCompactionPtr = &needsCompaction;

        [self enumerateObjectsWithOptions:opts usingBlock:^(id obj, NSUInteger index, BOOL *stop){
            id result = block(obj);
            
            if (result == nil) {
                if (concurrent) {
                    // indicate that the array will need compaction, because it now has
                    // nil values in it
                    OSAtomicIncrement32(needsCompactionPtr);
                } else {
                    *needsCompactionPtr = 1;
                }

                return;
            }

            if (reverse)
                index = originalCount - index - 1;

            // only need to store into the array on success, since it was filled
            // with zeroes on allocation
            objects[index] = result;
        }];

        if (concurrent) {
            // finish all assignments into the 'objects' array and 'needsCompaction'
            // variable
            OSMemoryBarrier();
        }
    }

    if (needsCompaction) {
        for (NSUInteger index = 0;index < actualCount;) {
            if (objects[index]) {
                ++index;
                continue;
            }

            // otherwise, move down everything above
            memmove((void *)(objects + index), (void *)(objects + index + 1), sizeof(*objects) * (originalCount - index - 1));
            --actualCount;
        }
    }

    return [NSArray arrayWithObjects:(id *)objects count:actualCount];
}

- (id)mav_objectPassingTest:(BOOL (^)(id obj, NSUInteger index, BOOL *stop))predicate; {
    return [self mav_objectWithOptions:0 passingTest:predicate];
}

- (id)mav_objectWithOptions:(NSEnumerationOptions)opts passingTest:(BOOL (^)(id obj, NSUInteger index, BOOL *stop))predicate; {
    NSUInteger index = [self indexOfObjectWithOptions:opts passingTest:predicate];
    if (index == NSNotFound)
        return nil;
    else
        return [self objectAtIndex:index];
}

@end
