---
layout: post
title:  "Comparing Java 8, RxJava, Reactor"
comments: true
keywords: rxjava java8 reactor
---
People often ask me:
> Why should I bother using RxJava or Reactor, if I can achive the same with Streams, CompletableFutures or Optionals?

{% include image.html name="promo.jpg" caption="Reactive Streams against the world" %}

The problem is, most of the time you are solving simple tasks, and you really don't need those libraries. But, when things get more complex, you have to write some freaky piece of code. Then this piece of code becomes more & more complex and hard to maintain. RxJava and Reactor come with a lot of handy features, which would cover your demands for many years ahead. Let's define 8 criteria, which would help us understand the difference between standard features and these libraries:
1. Composable
2. Lazy
3. Reusable
4. Asynchronous
5. Cacheable
6. Push or Pull
7. Backpressure
8. Operator fusion

And lets define classes which we will compare:
1. CompletableFuture
2. Stream
3. Optional
4. Observable (RxJava 1)
5. Observable (RxJava 2)
6. Flowable (RxJava 2)
7. Flux (Reactor Core)

Ready, steady, go!

---

## Composable
All of these classes are composable and allow as to think functionally. That's why we love them.

__CompletableFuture__ - a lot of `.then*()` methods which allow to build a pipeline, that can pass nothing or single value + throwable from stage to stage.

__Stream__ - lots of chainable operators which allow to transform input. Can pass N values from stage to stage.

__Optional__ - a few intermediate operators: `.map()`, `.flatMap()`, `.filter()`.

__Observable, Flowable, Flux__ - same as __Stream__

---

## Lazy

__CompletableFuture__ - not lazy, since it's just a holder of asynchronous result. These object are created to represent the work, that has already been started. It knows nothing about the work, but the result. Therefore, there is no way to go upstream and start executing pipeline from top to bottom. Next stage is executed when result is set into `CompletableFuture`. 

__Stream__ - all intermediate operations are lazy. All terminal operations, trigger computation.

__Optional__ - not lazy, all operations take place immediately.

__Observable, Flowable, Flux__ - nothing happens until there is a subscriber.

---

## Reusable

__CompletableFuture__ - can be reusable, since it's just a wrapper around a value. But with caution, since this wrapper is mutable. If you're sure that no-one will call `.obtrude*()` on it, it is safe. 

__Stream__ - not reusable. As [Java Doc states](https://docs.oracle.com/javase/8/docs/api/java/util/stream/Stream.html): 
> A stream should be operated on (invoking an intermediate or terminal stream operation) only once. A stream implementation may throw IllegalStateException if it detects that the stream is being reused. However, since some stream operations may return their receiver rather than a new stream object, it may not be possible to detect reuse in all cases.

__Optional__ - totally reusable, because it's immutable and all work happens eagerly.

__Observable, Flowable, Flux__ - reusable by design. All stages start execution from initial point, when there is a subscriber.

---

## Asynchronous

__CompletableFuture__ - well, the whole point of this class is to chain work asynchronously. `CompletableFuture` represents a work, that is associated with some `Executor`. If you didn't specify executor explicitly when creating a task, a common `ForkJoinPool` is used. This pool could be obtained via `ForkJoinPool.commonPool()` and by default it creates as many threads as many hardware threads your system has (usually number of cores, double it if your cores support hyperthreading). However, you can set the number of threads in this pool with JVM option: `-Djava.util.concurrent.ForkJoinPool.common.parallelism=?` or supply custom `Executor`, each time you create a stage of work. 

__Stream__ - no way to create asynchronous processing, but can do computations in parallel by creating parallel stream - `stream.parallel()`.

__Optional__ - nope, it's just a container.

__Observable, Flowable, Flux__ - targeted for building asynchronous systems, but synchronous by default. `subscribeOn` and `observeOn` allow you to control the invocation of the subscription and the reception of notifications (what thread will call `onNext` / `onError` / `onCompleted` on your observer).

With `subscribeOn` you decide on what `Scheduler` the `Observable.create` is executed. Even if you're not calling create yourself, there is an internal equivalent to it.
Example:
{% highlight java linenos %}
Observable
  .fromCallable(() -> {
    log.info("Reading on thread: " + currentThread().getName());
    return readFile("input.txt");
  })
  .map(text -> {
    log.info("Map on thread: " + currentThread().getName());
    return text.length();
  })
  .subscribeOn(Schedulers.io()) // <-- setting scheduler
  .subscribe(value -> {
     log.info("Result on thread: " + currentThread().getName());
  });
{% endhighlight %}
Outputs:
{% highlight any %}
Reading file on thread: RxIoScheduler-2
Map on thread: RxIoScheduler-2
Result on thread: RxIoScheduler-2
{% endhighlight %}

Conversely, `observeOn()` controls which `Scheduler` is used to invoke downstream stages occurring after `observeOn()`.
Example:
{% highlight java linenos %}
Observable
  .fromCallable(() -> {
    log.info("Reading on thread: " + currentThread().getName());
    return readFile("input.txt");
  })
  .observeOn(Schedulers.computation()) // <-- setting scheduler
  .map(text -> {
    log.info("Map on thread: " + currentThread().getName());
    return text.length();
  })
  .subscribeOn(Schedulers.io()) // <-- setting scheduler
  .subscribe(value -> {
     log.info("Result on thread: " + currentThread().getName());
  });
{% endhighlight %}
Outputs:
{% highlight any %}
Reading file on thread: RxIoScheduler-2
Map on thread: RxComputationScheduler-1
Result on thread: RxComputationScheduler-1
{% endhighlight %}

---

## Cacheable

What is the difference between reusable and cacheable? Lets say we have pipeline `A`, and re-use it two times to create pipelines `B = A + 🔴` and `C = A + 🔵` from it.
* If `B` & `C` complete successfully, then class is reusable.
* If `B` & `C` complete successfully and every stage of pipeline `A` is invoked only once, then class is cacheable. To be cacheable, class must be reusable.

__CompletableFuture__ - same answer as for reusability.

__Stream__ - no way to cache intermediate result, unless invoke terminal operation.

__Optional__ - 'cacheable', because all work happens eagerly.

__Observable, Flowable, Flux__ - not cached by default. But you can convert `A` to cached by calling  `.cache()` on it.

{% highlight java linenos %}
Observable<Integer> work = Observable.fromCallable(() -> {
  System.out.println("Doing some work");
  return 10;
});
work.subscribe(System.out::println);
work.map(i -> i * 2).subscribe(System.out::println);
{% endhighlight %}
Outputs:
{% highlight any %}
Doing some work
10
Doing some work
20
{% endhighlight %}
With `cache()`:
{% highlight java linenos %}
Observable<Integer> work = Observable.fromCallable(() -> {
  System.out.println("Doing some work");
  return 10;
}).cache(); // <- apply caching
work.subscribe(System.out::println);
work.map(i -> i * 2).subscribe(System.out::println);
{% endhighlight %}
Outputs:
{% highlight any %}
Doing some work
10
20
{% endhighlight %}

---

## Push or Pull
__Stream__ & __Optional__ are pull based. You pull the result from pipeline by calling different methods (`.get()`, `.collect()`, etc.).
Pull is often associated with blocking, synchronous and that is fair. You call a method and thread starts waiting for the data to arrive. Thread is blocked until arrival. 

__CompletableFuture__, __Observable__, __Flowable__, __Flux__ are push based. You subscribe to pipeline and you will get notified when there is something to process.
Push is often associated with non-blocking, asynchronous. You can do anything while the pipeline is executing in some thread. You've already described a code to execute and notification will trigger execution of this code as next stage.

---

## Backpressure

___In order to have back-pressure, pipeline must be push-based.___

__Backpressure__ describes a situation in pipeline, when some asynchronous stages can't process the values fast enough and need a way to tell the upstream producing stage to slow down.
It's unacceptable for stage to fail, because there's too much data.
{% include image.html name="backpressure.jpg" caption="Backpressure" %}

* __Stream__ & __Optional__ don't support this, since they are pull based.
* __CompletableFuture__ doesn't need to solve it, since it produces 0 or 1 result.

__Observable (RxJava 1)__, __Flowable__, __Flux__ - solve it. Common strategies are:
* __Buffering__ - buffer all `onNext` values until the downstream consumes it.
* __Drop Recent__ - drop the most recent `onNext` value if the downstream can't keep up.
* __Use Latest__ - supply only the latest `onNext` value, overwriting any previous value if the downstream can't keep up.
* __None__ - `onNext` events are written without any buffering or dropping.
* __Exception__ - signal an exception in case the downstream can't keep up.

__Observable (RxJava 2)__ - doesn't solve it. Many users of RxJava 1 used `Observable` for events that cannot reasonably be backpressured or didn't use strategies to resolve it, which cased unexpected exceptions. Therefore, ___RxJava 2___ created clear separation between backpressured (`Flowable`) and non-backpressured (`Observable`) classes.

---

## Operator Fusion

The idea is to modify the chain of stages at various lifecycle points, in order to remove overhead created by architecture of library.
All these optimizations are done internally, so that everything is transparent for end-user.

Only __RxJava 2__ & __Reactor__ support it, but differently.
In general, there are 2 types of optimizations:
- Macro-fusion - replacing 2+ subsequent operators with a single operator.
{% include image.html name="macro-fusion.png" caption="Macro-fusion" %}
- Micro-fusion - operators that end in an output queue and operators starting with a front-queue could share the same queue instance.
As an example, instead of calling `request(1)` and then handling `onNext()`:
{% include image.html name="micro-fusion-1.png" caption="Micro-fusion" %}
subscriber can poll for value from parent observable:
{% include image.html name="micro-fusion-2.png" caption="Micro-fusion" %}

More detailed information can be found here: [Part 1](http://akarnokd.blogspot.com/2016/03/operator-fusion-part-1.html) & [Part 2](http://akarnokd.blogspot.com/2016/04/operator-fusion-part-2-final.html)

---

# Conclusion
{% include image.html name="conclusion.png" caption="Comparison" %}

`Stream`, `CompletableFuture` and `Optional` were created to solve specific problems. And they are really good at solving these problems.
If they cover your needs, you are good to go.

However, different problems have different complexity and some of them require new techniques.
__RxJava & Reactor__ are universal tools, that will help you to solve your problems declaratively, instead of creating ___'a hack'___ with tools that weren't designed to solve such problems. 