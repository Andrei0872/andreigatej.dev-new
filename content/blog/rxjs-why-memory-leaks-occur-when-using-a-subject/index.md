---
title: "RxJS: Why memory leaks occur when using a Subject"
date: 2021-02-13
draft: false
blog_tags: ["rxjs"]
discussion_id: null
description: "Understanding more about memory leaks"
---

_This article has been published on [indepth.dev](https://indepth.dev/posts/1433/rxjs-why-memory-leaks-occur-when-using-a-subject)._

## Introduction

It's not uncommon to see the words _unsubscribe_, _memory leaks_, _subject_ in the same phrase when reading upon RxJS-related materials. In this article, we're going to tackle this fact and by the end of it you should gain a better insight as to why memory leaks occur and why a simple `unsubscribe()` solves the problem. Although the reader should have some familiarity with RxJS, the necessary concepts will be clarified as things move on. If you want to learn more about RxJS subjects, [start here](https://indepth.dev/reference/rxjs/subjects).

_This article has been inspired by [this Stack Overflow answer](https://stackoverflow.com/questions/63257763/do-subscriptions-to-rxjs-subjects-cause-memory-leaks-if-not-unsubscribed-when-th/63258734#63258734)._

## Understanding the problem

Although the RxJS library can be used on its own or in conjunction with any library/framework, we'll discuss the problem in the context of Angular, just for convenience. This shouldn't be a problem, since the concepts are applicable in any case.

But first, let’s demonstrate a memory leak in pure RxJS and we will then expand upon that:

```ts
const source = new Subject();
 
let s = source.subscribe(v => console.log("subscriber 1: ", v));
 
source.next("1"); // logs: subscriber 1: 1
 
// this won't do anything
s = null
 
// notice we didn’t unsubscribe before
s = source.subscribe(v => console.log("subscriber 2: ", v));
 
source.next("2");
// logs:
// subscriber 1: 2 // !!! - this shouldn't be here
// subscriber 2: 2
```

_A StackBlitz app for the above snippet can be found [here](https://stackblitz.com/edit/rxjs-memory-leak-example?file=index.ts)._

In Angular, a common pattern is to inject services into components and subscribe to the observable properties exposed by those services:

```ts
class Service {
 private usersSrc = new Subject();
 users$ = this.usersSrc.asObservable();
}
```

Such services can be consumed like this:

```ts
class FooComponent {
 constructor (private service: Service) { }
  ngOnInit () {
   this.subscription = this.service.users$.subscribe(nextCb, errorCb, completeCb)
 }
}
```

As you know, a `Subject` is a special type of `Observable` and comes with some very interesting features. The most relevant for us is the fact that it can be subscribed to and it maintains a list of subscribers. The _subscription process_ deserves an article on its own, but for now it's important to understand that a subject, when its `subject.next()` method is invoked, it will send the value to all of the registered subscribers. Because a subscriber is registered when the `subscribe(nextCb, ...)` method is invoked, the value from the source will be available in the `nextCb`.

In other words, all callbacks are kept in the subject.

Now, when the component is destroyed(e.g due to navigating to another route), if we don't call `this.subscription.unsubscribe()`, that subscriber will still be part of that subscribers list. What `unsubscribe` really does is to remove that subscriber from that list. This is important, because the next time the component is created and that `ngOnInit` is called, a new subscriber will be added to the subscribers list, but the old one would still be there if `this.subscription.unsubscribe()` is not called.

Here is a simplified version of the case when a memory leak occurs:

```ts
// the Subject used in the service
let src = {
 subscribers: [],
 
 addSubscriber(cb) {
   this.subscribers.push(cb);
   return this.subscribers.length - 1;
 },
 
 removeSubscriber(idx) {
   this.subscribers.splice(idx, 1);
 },
 next(data) {
   this.subscribers.forEach(cb => cb(data));
 }
};
```

And this is how a simplified version of a component would look like:

```ts
// the component
class Foo {
 subIdx: number;
 constructor() {
   this.subIdx = src.addSubscriber(value => {
     console.log(value);
   });
 }
 
 onDestroy() {
   // the equivalent of `unsubscribe()`
   src.removeSubscriber(this.subIdx);
 }
}
 
// creating a new component
let foo = new Foo(); // Foo {subIdx: 0}
 
// sending data to subscribers
src.next("sending data for the first time");
// console output: `sending data for the first time`
 
// destroying the component - without calling `onDestroy`
foo = null;
 
src.next("sending data for the second time"); // the subscriber is still there
// console output: `sending data for the second time`
 
// registering a new instance - Foo {subIdx: 1}
// at this point, a new subscriber has been created
foo = new Foo();
 
src.next("sending data for the third time");
// console output: `sending data for the third time`
// console output: `sending data for the third time`
```

_You can also play around with the code above in this [StackBlitz](https://stackblitz.com/edit/memory-leaks-simplified-version?file=index.ts)._

After `src.next('test2')`, we can see `'foo'` being logged twice, which indicates a memory leak. Something very similar happens with Subjects and their subscribers.

Usually, this sort of problems take place when the source is infinite(it will not `complete`/`error`, like a global service that is used by components). But there are cases when unsubscribing is not necessary. For instance, when the Subject can no longer be referenced when its container is destroyed or nulled out, which is what happens with `ActivatedRoute` or form control's Subjects(`valueChanges`, `statusChanges`) when the component is destroyed.

## Conclusion

I hope that with this short article, the reason why memory leaks occur when using RxJS' Subjects is a bit more clearer. To summarize, it all comes down to the fact that a Subject keeps track of subscribers with the help of a list and when a subscriber shouldn't be there anymore, its `unsubscribe()` method should be called. Otherwise, there will be some unexpected results.

Thanks for reading!

