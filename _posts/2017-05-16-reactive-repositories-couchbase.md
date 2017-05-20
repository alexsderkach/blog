---
layout: post
title:  "Reactive Repositories with Couchbase"
comments: true
keywords: rxjava java8 couchbase reactive
---
{% include image.html name="couchbase-logo.png" caption="Couchbase + RxJava" %}

## Blocking vs Non-blocking
Every call to third-party resource by its nature is asynchronous.
Your application could work in parallel, while that resource is processing the request.
But this call is usually blocking & synchronous, because our applications are using thread-per-request model.
It is simpler.

> We can convert asynchronous, non-blocking code to synchronous, blocking.

The problem raises, when your application is using event loop to process requests.
What if, it becomes necessary to use some library which provides a exclusively blocking API?

> There is no way to convert blocking code to non-blocking.

If you need to use blocking API, while your whole application is implemented using non-blocking approach, the solution is **allocate-thread-per-call-to-blocking-resource**.
But, if you're going to use this library often, you will face the same performance issues, which are placed by thread-per-request model.

Today, modern application are implemented using non-blocking approach, because there's too much communication with third-party resources, e.g. microservices.
Thus, the only, sane way to design an API is to make it non-blocking & asynchronous.
It provides better performance and scalability. Eventually, we can convert non-blocking to blocking, for apps that use synchronous approach.

## Couchbase in Game Development
**Couchbase** - the most common choice if you are going to build a video-game.
Each player has **unique** story. It perfectly fits in **Key-Document** model.
Games are mostly interactive. To be interactive, application must be responsive, must respond in timely manner.

Couchbase SDK is build using RxJava 1 & Ring Buffer, thus making *DB <-> Server* communication as fast as possible.

Could it be better? 
- By performance - arguably
- By usability - yes

All operations with data in this SDK are done via **Document** objects.
Every time we need to make any CRUD operation, we need to convert **DTO** to **Document**.
When you have variety of DTOs, and you need to perform the same set of operations with them, a common pattern arises.

> Use a repository to separate the logic that retrieves the data and maps it to the entity model from the business logic that acts on the model.

The most common operations, which are used in Couchbase Repository, are the following:
1. get
2. insert
3. remove
4. update
5. cas (insert or update)

Get implementation is simple. CAS operation is the tricky one. Others follow common logic.

## Building Reactive Repository Layer

First of all we need serialization/deserialization layer.
Couchbase provides an implementation of **Document** which contains JSON data in raw format - **RawJsonDocument**. 
It allows us to use Jackson, to convert DTO to String, and eventually to **RawJsonDocument**.

Converter will look like this:
{% highlight java linenos %}
@RequiredArgsConstructor
public class Converter<K, V> {

    private static final ObjectMapper OBJECT_MAPPER = new ObjectMapper();

    private final Class<V> clazz;
    private final Function<K, String> keyCreator;
    private final int expiry;

    public V from(RawJsonDocument document) {
        return deserialize(document.content(), clazz);
    }
    
    public RawJsonDocument document(K key) {
        return RawJsonDocument.create(keyCreator.apply(key));
    }

    public RawJsonDocument document(K key, V value) {
        return document(key, value, 0); // new documents have cas = 0
    }

    public RawJsonDocument document(K key, V value, long cas) {
        requireNonNull(key, "Key can't be null");
        requireNonNull(value, "Value can't be null");
        return RawJsonDocument
            .create(keyCreator.apply(key), expiry, serialize(value), cas);
    }
    
    @SneakyThrows
    private static String serialize(Object value) {
        return OBJECT_MAPPER.writeValueAsString(value);
    }

    @SneakyThrows
    private static <V> V deserialize(String content, Class<V> clazz) {
        return OBJECT_MAPPER.readValue(content, clazz);
    }
}
{% endhighlight %}

Then, lets define the template of repository.

{% highlight java linenos %}
public class CouchbaseRepository<K, V> {

    private final AsyncBucket bucket;
    private final Converter<K, V> converter;
    private final int maxRetry;
    private final int timeout;
    
    public Observable<V> get(K key) { ... }
    public Observable<V> insert(K key, V value) { ... }
    public Completable remove(K key) { ... }
    public Observable<V> update(K key, Function<Optional<V>, V> updateFunction) { ... }
    public Observable<V> cas(K key, Function<Optional<V>, V> updateFunction) { .. }

}
{% endhighlight %}

Now, lets implement operations.

### 1. get(K key)
Contract is the following: 
- If document exists, return it. 
- If document does not exist, return empty Observable.

{% highlight java linenos %}
public Observable<V> get(K key) {
    // get() will try to fetch RawJsonDocument, 
    // because converter created empty document of this type
    // if document does not exist, get() emits 0 items
    return bucket.get(converter.document(key))
        .compose(common(retryFunction()));         // common code
}
{% endhighlight %}

Common post processing code for observable with response looks like this:
{% highlight java linenos %}
private Observable.Transformer<RawJsonDocument, V> common(RetryWhenFunction retryWhenFunction) {
    return observable -> observable
        .timeout(timeout, TimeUnit.MILLISECONDS) // throw error in case of request timeout
        .map(converter::from)                    // deserialize
        .retryWhen(retryWhenFunction);           // retry in case of failure
}
{% endhighlight %}

Retry Function looks like this:

{% highlight java linenos %}
private RetryWhenFunction retryFunction() {
    return anyOf(TemporaryFailureException.class)
            .max(maxRetry)
            .build();
}
{% endhighlight %}

### 2. insert(K key, V value)
Contract is the following: 
- If document exists, throw **DocumentAlreadyExistsException**. 
- If document does not exist, return Observable with new value.

Code looks almost the same:
{% highlight java linenos %}
public Observable<V> insert(K key, V value) {
    return bucket.insert(converter.document(key, value))
        .compose(common(retryFunction()));         // common code
}
{% endhighlight %}


### 3. remove(K key)
Contract is the following: 
- If document was removed, complete. 
- If document does not exist, complete.

{% highlight java linenos %}
public Completable remove(K key) {
    return bucket.remove(converter.document(key))
         // complete if document does not exist
        .onErrorResumeNext(
            e -> e instanceof DocumentDoesNotExistException ? empty() : error(e)
        )
        .compose(common(retryFunction()))         // common code
        .toCompletable()
}
{% endhighlight %}

### 4. update(K key, Function<Optional\<V>, V> update)
Flow:
1. fetch document
2. convert document to value
3. apply a function to value
4. save new value
5. repeat from 1 if CAS mismatches

{% highlight java linenos %}
public Observable<V> update(K key, Function<Optional<V>, V> updateFunction) {
    return just(converter.document(key))
            .flatMap(bucket::get)
            .flatMap(doc -> just(converter.from(doc))
                .map(Optional::ofNullable)
                .map(updateFunction::apply)
                .map(value -> converter.document(key, value, doc.cas()))
                .flatMap(bucket::replace)
            )
            .compose(common(casRetryFunction())); // common code
}
{% endhighlight %}

Retry Function to recover from CAS mismatch looks like this:

{% highlight java linenos %}
private RetryWhenFunction casRetryFunction() {
    return anyOf(
            CASMismatchException.class,
            DocumentAlreadyExistsException.class,
            DocumentDoesNotExistException.class,
            TemporaryFailureException.class,
            DurabilityException.class
        )
        .max(maxRetry)
        .build();
}
{% endhighlight %}

### 5. cas(K key, Function<Optional\<V>, V> update)
Flow:
1. fetch document, if it exists continue with **update flow**
2. if document not found, use **insert flow**
3. repeat from 1 if CAS mismatches, or Document was inserted during update by someone else, or Document was removed during insert by someone else

{% highlight java linenos %}
public Observable<V> cas(K key, Function<Optional<V>, V> updateFunction) {
    return update(key, updateFunction)
        .switchIfEmpty(insert(key, updateFunction.apply(Optional.empty())))
        .retryWhen(casRetryFunction());           // retry in case of failure
}
{% endhighlight %}

---

## Conclusion
Couchbase is great choice for Game Dev, because it provides incredible performance and Key-Value model.
Under high-load, applications need to perform consistent modifications at persistence layer.
Pessimistic locking does not scale well, because it locks entry for modification. On the other hand, optimistic locking does not lock anything, thus has much better performance.
Couchbase provides optimistic locking capabilities, but they are oftenly forgotten.
We have implemented a Repository pattern for Couchbase layer, which provides CRUD operations + concurrent, safe updates via functions.
