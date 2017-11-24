---
layout: post
title:  "Kotlin Decorators"
comments: true
keywords: kotlin patterns
---
2 years ago, I was working for a small company as Java dev.
My place was situated very closely to a different team, who were doing a Python project.
Every week someone from their team was screening a candidate.
A question, which I would hear everytime was: "What is a decorator in Python?"

For Python, it is not exactly the same thing as [Decorator pattern](https://en.wikipedia.org/wiki/Decorator_pattern), but a syntactic sugar, which allows to alter functions and methods.

{% highlight python linenos %}
def p_decorate(func):
   def func_wrapper(text):
       return "A+{0}".format(func(text))
   return func_wrapper

@p_decorate
def get_text(text):
   return "B+{0}".format(text)

print get_text("C")

# Outputs A+B+C
{% endhighlight %}

In Java, the same is usually achieved with AOP.

For Kotlin you could expect the same answer, but Kotlin is more expressive than Java.

Lets say, we have the same function which returns text, as in Python example.
{% highlight kotlin linenos %}

fun getText(name: String) = "B+$name"

fun main(args: Array<String>) = println(getText("C"))

// Outputs B+C
{% endhighlight %}

What we need next, is a high-order function.
It is a function that takes functions as parameters, or returns a function.

{% highlight kotlin linenos %}
inline fun prefix(f: () -> String) = "A+${f()}"
{% endhighlight %}

Additionally, in Kotlin, if a function takes another function as the last parameter, the lambda expression argument can be passed outside the parenthesized argument list.

This means, that we could just wrap a body of a function in **prefix { ... }**, in order to add some behavior to it.

{% highlight kotlin linenos %}
fun main(args: Array<String>) = println(getText("C"))

inline fun prefix(f: () -> String) = "A+${f()}"
fun getText(name: String) = prefix { "B+$name" }

{% endhighlight %}

## Additional reading

[https://kotlinlang.org/docs/reference/lambdas.html](https://kotlinlang.org/docs/reference/lambdas.html)

[http://kotlinlang.org/docs/reference/grammar.html#callSuffix](http://kotlinlang.org/docs/reference/grammar.html#callSuffix)

