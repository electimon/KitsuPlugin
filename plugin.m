#import "../../srcs/HanamiPlugin.h"
#import "../../srcs/HanamiConfig.h"
#include <math.h>

static OFDictionary *dictionaryValue(id value) {
    return [value isKindOfClass:[OFDictionary class]] ? value : nil;
}

static OFString *stringValue(id value) {
    return [value isKindOfClass:[OFString class]] ? value : @"";
}

static OFString *numberValue(id value) {
    return [value isKindOfClass:[OFNumber class]] ? [value description] : @"";
}

static OFString *queryValue(OFString *value) {
    return [value stringByAddingPercentEncodingWithAllowedCharacters:[OFCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"]];
}

static OFDictionary *emptyResponse(void) {
    return @{@"title": @"", @"image_url": @"", @"url": @"", @"progress": @"",
             @"episode_count": @"", @"status": @"", @"updated_at": @"",
             @"rating": @"", @"synopsis": @"", @"available": @"0"};
}

@interface KitsuClient : OFObject <OFHTTPClientDelegate>
- (instancetype)initWithConfig:(HanamiConfig *)config;
- (OFDictionary *)lastResponse;
@end

@interface KitsuPlugin : OFObject <HanamiPlugin>
@end

Class HanamiPluginClass(void) {
    return [KitsuPlugin class];
}

@implementation KitsuClient {
    OFTimer *timer;
    OFTimer *requestTimer;
    OFHTTPClient *client;
    OFHTTPResponse *activeResponse;
    OFString *apiURL;
    OFString *username;
    OFString *userID;
    OFString *status;
    OFDictionary *lastResponse;
    OFMutableData *body;
    char buffer[4096];
    BOOL busy;
    BOOL resolvingUser;
}

- (instancetype)initWithConfig:(HanamiConfig *)config {
    self = [super init];
    self->username = [config valueForKey:@"username" defaultValue:@""];
    self->userID = [config valueForKey:@"user_id" defaultValue:@""];
    self->status = [config valueForKey:@"status" defaultValue:@"current"];
    self->apiURL = [config valueForKey:@"api_url" defaultValue:@"https://kitsu.app/api/edge"];
    self->lastResponse = emptyResponse();
    if (username.length < 1 && userID.length < 1) {
        OFLog(@"KitsuPlugin: Please set username or user_id in configs/kitsu.ini!");
        return nil;
    }
    if (![@[@"current", @"planned", @"completed", @"on_hold", @"dropped", @"all"] containsObject:status]) {
        OFLog(@"KitsuPlugin: Unknown library status: %@", status);
        return nil;
    }
    double interval = [[config valueForKey:@"refresh_interval" defaultValue:@"180"] doubleValue];
    if (!isfinite(interval) || interval < 30.0) {
        OFLog(@"KitsuPlugin: refresh_interval must be at least 30 seconds!");
        return nil;
    }
    self->client = [OFHTTPClient client];
    self->client.delegate = self;
    self->timer = [OFTimer scheduledTimerWithTimeInterval:interval repeats:YES block:^(OFTimer * _Nonnull timer){
        [self refresh];
    }];
    [self->timer fire];
    return self;
}

- (void)fail:(id)exception {
    OFLog(@"KitsuPlugin: Failed to refresh anime info: %@", exception);
    [requestTimer invalidate];
    requestTimer = nil;
    [activeResponse cancelAsyncRequests];
    activeResponse = nil;
    [client close];
    body = nil;
    busy = NO;
}

- (void)performRequest:(OFString *)path {
    OFHTTPRequest *request = [OFHTTPRequest requestWithIRI:[OFIRI IRIWithString:[apiURL stringByAppendingString:path]]];
    request.headers = @{@"Accept": @"application/vnd.api+json", @"Content-Type": @"application/vnd.api+json"};
    [requestTimer invalidate];
    requestTimer = [OFTimer scheduledTimerWithTimeInterval:20.0 repeats:NO block:^(OFTimer * _Nonnull timer){
        [self fail:@"Request timed out"];
    }];
    [client close];
    [client asyncPerformRequest:request];
}

- (void)refresh {
    if (busy)
        return;
    busy = YES;
    @try {
        resolvingUser = (userID.length < 1);
        if (resolvingUser)
            [self performRequest:[OFString stringWithFormat:@"/users?filter%%5Bslug%%5D=%@&page%%5Blimit%%5D=1", queryValue(username)]];
        else
            [self requestLibrary];
    } @catch (id exception) {
        [self fail:exception];
    }
}

- (void)requestLibrary {
    OFString *statusFilter = [status isEqual:@"all"] ? @"" : [OFString stringWithFormat:@"&filter%%5Bstatus%%5D=%@", queryValue(status)];
    [self performRequest:[OFString stringWithFormat:@"/library-entries?filter%%5BuserId%%5D=%@&filter%%5Bkind%%5D=anime%@&sort=-updatedAt&page%%5Blimit%%5D=1&include=anime", queryValue(userID), statusFilter]];
}

- (void)fillCache:(OFDictionary *)document {
    id entries = [document objectForKey:@"data"];
    if (![entries isKindOfClass:[OFArray class]])
        @throw [OFInvalidFormatException exception];
    if ([entries count] == 0) {
        @synchronized (self) {
            lastResponse = emptyResponse();
        }
        return;
    }
    OFDictionary *entry = dictionaryValue([entries firstObject]);
    OFDictionary *attributes = dictionaryValue([entry objectForKey:@"attributes"]);
    OFDictionary *relationships = dictionaryValue([entry objectForKey:@"relationships"]);
    OFDictionary *relationship = dictionaryValue([relationships objectForKey:@"anime"]);
    OFDictionary *reference = dictionaryValue([relationship objectForKey:@"data"]);
    OFString *animeID = stringValue([reference objectForKey:@"id"]);
    id included = [document objectForKey:@"included"];
    if (attributes == nil || animeID.length < 1 || ![included isKindOfClass:[OFArray class]])
        @throw [OFInvalidFormatException exception];
    OFDictionary *anime = nil;
    for (id object in included) {
        OFDictionary *resource = dictionaryValue(object);
        if ([[resource objectForKey:@"type"] isEqual:@"anime"] && [[resource objectForKey:@"id"] isEqual:animeID]) {
            anime = dictionaryValue([resource objectForKey:@"attributes"]);
            break;
        }
    }
    if (anime == nil)
        @throw [OFInvalidFormatException exception];
    OFString *title = stringValue([anime objectForKey:@"canonicalTitle"]);
    OFDictionary *titles = dictionaryValue([anime objectForKey:@"titles"]);
    if (title.length < 1)
        title = stringValue([titles objectForKey:@"en"]);
    if (title.length < 1)
        title = stringValue([titles objectForKey:@"en_jp"]);
    OFDictionary *poster = dictionaryValue([anime objectForKey:@"posterImage"]);
    OFString *imageURL = @"";
    for (OFString *size in @[@"medium", @"large", @"original", @"small", @"tiny"]) {
        imageURL = stringValue([poster objectForKey:size]);
        if (imageURL.length > 0)
            break;
    }
    OFString *slug = stringValue([anime objectForKey:@"slug"]);
    OFDictionary *response = @{
        @"title": title, @"image_url": imageURL,
        @"url": [OFString stringWithFormat:@"https://kitsu.app/anime/%@", queryValue(slug.length > 0 ? slug : animeID)],
        @"progress": numberValue([attributes objectForKey:@"progress"]),
        @"episode_count": numberValue([anime objectForKey:@"episodeCount"]),
        @"status": stringValue([attributes objectForKey:@"status"]),
        @"updated_at": stringValue([attributes objectForKey:@"updatedAt"]),
        @"rating": numberValue([attributes objectForKey:@"ratingTwenty"]),
        @"synopsis": stringValue([anime objectForKey:@"synopsis"]), @"available": @"1"
    };
    @synchronized (self) {
        lastResponse = response;
    }
}

- (void)consumeBody {
    OFDictionary *document = dictionaryValue([[OFString stringWithUTF8String:body.items length:body.count] objectByParsingJSON]);
    if (document == nil)
        @throw [OFInvalidFormatException exception];
    body = nil;
    if (resolvingUser) {
        id users = [document objectForKey:@"data"];
        if (![users isKindOfClass:[OFArray class]])
            @throw [OFInvalidFormatException exception];
        OFDictionary *user = dictionaryValue([users firstObject]);
        OFString *resolvedID = stringValue([user objectForKey:@"id"]);
        if (resolvedID.length < 1)
            @throw [OFInvalidFormatException exception];
        userID = resolvedID;
        resolvingUser = NO;
        [self requestLibrary];
    } else {
        [self fillCache:document];
        [requestTimer invalidate];
        requestTimer = nil;
        activeResponse = nil;
        [client close];
        busy = NO;
    }
}

- (void)client:(OFHTTPClient *)remoteClient didPerformRequest:(OFHTTPRequest *)request response:(OFHTTPResponse *)response exception:(id)exception {
    if (exception != nil) {
        [self fail:exception];
        return;
    }
    @try {
        if (response.statusCode != 200)
            @throw [OFInvalidServerResponseException exception];
        activeResponse = response;
        body = [OFMutableData data];
        // Read the body asynchronously too, so slow upstreams don't block Hanami.
        [response asyncReadIntoBuffer:buffer length:sizeof(buffer) handler:^bool(OFStream *stream, void *readBuffer, size_t length, id readException) {
            @try {
                if (readException != nil)
                    @throw readException;
                if (body.count + length > 1024 * 1024)
                    @throw [OFOutOfRangeException exception];
                [body addItems:readBuffer count:length];
                if (!stream.atEndOfStream)
                    return true;
                [self consumeBody];
            } @catch (id ex) {
                [self fail:ex];
            }
            return false;
        }];
    } @catch (id ex) {
        [self fail:ex];
    }
}

- (OFDictionary *)lastResponse {
    @synchronized (self) {
        return lastResponse;
    }
}

@end

@implementation KitsuPlugin {
    KitsuClient *client;
}

- (instancetype)init {
    self = [super init];
    self->client = [[KitsuClient alloc] initWithConfig:[HanamiConfig instanceFor:@"kitsu"]];
    if (client == nil)
        return nil;
    return self;
}

- (void)transformMap:(OFMutableDictionary *)varMap {
    OFDictionary *response = [client lastResponse];
    for (OFString *key in response)
        [varMap setObject:[stringValue([response objectForKey:key]) stringByXMLEscaping] forKey:[OFString stringWithFormat:@"$kitsu::%@", key]];
}

- (OFString *)name {
    return @"KitsuPlugin";
}

- (OFString *)author {
    return @"Renn";
}

- (OFString *)version {
    return @"1.0";
}

@end
