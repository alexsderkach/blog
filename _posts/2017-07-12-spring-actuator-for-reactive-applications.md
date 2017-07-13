---
layout: post
title:  "Spring Actuator for Reactive Applications"
comments: true
keywords: rxjava spring reactive
---

ertert
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

sdf