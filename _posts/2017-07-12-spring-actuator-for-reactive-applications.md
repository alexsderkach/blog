---
layout: post
title:  "Spring Actuator for Reactive Applications"
comments: true
keywords: rxjava spring reactive
---

{% include image.html name="header.jpg" caption="Spring Boot Actuator + RxJava" %}

You've seen this piece of code, don't you?

{% highlight java linenos %}
@Service
class UserService {
    
    ...
    
    @Metered("UserService.register")
    public User register(RegistrationForm form) {
        validate(form);
        User user = createUser(form);
        return user;
    }
}
{% endhighlight %}

Every operation in this method is synchronous, and is executed sequentially.
Since next operation does not occur until previous is finished, we can easily calculate time of method execution with **Around Advice**:

*Execution time = TS of method return - TS of method call*

If we would like to count successful executions of method, we would use **After Returning Advice**.
If we would like to count failed executions of method, we would use **After Throwing Advice**.
Both advices will increment some counter.

But, what happens when we become reactive?

{% highlight java linenos %}
@Service
class UserService {
    
    ...
    
    @Metered("UserService.register")
    public Single<User> register(RegistrationForm form) {
        return validate(form)
              .andThen(createUser(form));
    }
}
{% endhighlight %}

Register 10K user, open [Spring Actuator's](https://docs.spring.io/spring-boot/docs/current/reference/html/production-ready-endpoints.html) */metrics* endpoint, and you will see the following:
{% highlight js linenos %}
{
    ...
    "timer.UserService.register.count": 10000,
    "timer.UserService.register.snapshot.75thPercentile": 0,
    "timer.UserService.register.snapshot.95thPercentile": 0,
    "timer.UserService.register.snapshot.98thPercentile": 0,
    "timer.UserService.register.snapshot.999thPercentile": 0,
    "timer.UserService.register.snapshot.99thPercentile": 0,
    "timer.UserService.register.snapshot.max": 0,
    "timer.UserService.register.snapshot.mean": 0,
    "timer.UserService.register.snapshot.median": 0,
    "timer.UserService.register.snapshot.min": 0,
    "timer.UserService.register.snapshot.stdDev": 0
    ...
}
{% endhighlight %}
{% include image.html name="flash.gif" caption="" %}

Is my code really that fast? Nope.

The problem with advices, is that they expect synchronous execution:
1. Save current timestamp
2. Call method & save result to variable
3. Calculate diff with timestamp in Step 1
4. Return result from Step 2

When these expectations are applied to reactive application, existing advices become useless - they monitor the synchronous part of reactive libraries - **chain creation**.
Of course the speed of creating a chain with 2 operations is < 1 millisecond.

To solve this problem, we need create an advice which will use action methods of the source:

- Single -> doOnError, doOnSuccess
- Completable -> doOnError, doOnCompleted
- Observable -> doOnError, doOnCompleted

If you would like to monitor execution time, number of successful calls, errors on some sub-sequence of operators, where last operator returns *Single*, first of all, you would need pointcuts:

{% highlight java linenos %}
@Aspect @Component @RequiredArgsConstructor
public class RxMeteredAspect {

    private final GaugeService gaugeService;        // Actuator's bean for storage and analysis of values
    private final CounterService counterService;    // Actuator's bean for monitoring counters
    
    ...
    
    @Pointcut("@annotation(Metered)")               // Everything with @Metered annotation
    public void metered() {
    }

    @Pointcut("execution(public rx.Single *(..))")  // Every public method which returns Single
    public void single() {
    }
    
    ...
    
}
{% endhighlight %}

Then, you can implement an advice with created pointcuts:

{% highlight java linenos %}
    ...
    
    @Around("metered() && single()")
    public Object profileSingle(ProceedingJoinPoint proceedingJoinPoint) {
        RxMetered annotation = getAnnotation(proceedingJoinPoint);          // extract annotation from method
        String metricName = annotation.value();                             // extract name for metric
        return fromCallable(System::currentTimeMillis)                      // create lazy timestamp provider
            .flatMap(startTs -> ((Single) proceedingJoinPoint.proceed())    // call method which we're monitoring
                // track time + number of successful executions
                .doOnSuccess(result -> {
                    if (annotation.timed()) {
                        // no need to increment counter, since timer.* generates counters too
                        gaugeService.submit("timer." + metricName, currentTimeMillis() - startTs);
                    } else {
                        counterService.increment("meter." + metricName);
                    }
                })
                // track number of failed executions
                .doOnError(e -> counterService.increment("meter." + metricName + ".errorCount"))
            );
    }
    
    ...
{% endhighlight %}

Execute 3 requests and open */metrics* endpoint again. You will see realistic results:
{% highlight js linenos %}
{
    ...
    "timer.UserService.register.count": 3,
    "timer.UserService.register.snapshot.75thPercentile": 31,
    "timer.UserService.register.snapshot.95thPercentile": 31,
    "timer.UserService.register.snapshot.98thPercentile": 31,
    "timer.UserService.register.snapshot.999thPercentile": 38,
    "timer.UserService.register.snapshot.99thPercentile": 31,
    "timer.UserService.register.snapshot.max": 341,
    "timer.UserService.register.snapshot.mean": 31,
    "timer.UserService.register.snapshot.median": 31,
    "timer.UserService.register.snapshot.min": 31,
    "timer.UserService.register.snapshot.stdDev": 8
    ...
}
{% endhighlight %}

The same can be implemented for any class, of any reactive library, since all of them provide action methods.

## Conclusion
Spring has a big ecosystem and is currently moving towards reactive paradigm.
Users are already familiar and very comfortable with declarative capabilities of this framework.
Reactive paradigm is absolutely a different way of developing applications when compared to existing Spring Applications.
Could Spring stay as declarative as it is now, and make a shift?
It could, but still requires a little bit of development.