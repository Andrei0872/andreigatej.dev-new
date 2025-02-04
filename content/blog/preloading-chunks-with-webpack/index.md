---
title: "Preloading chunks with webpack"
date: 2025-01-25T18:39:38+02:00
draft: false
blog_tags: ["webpack"]
summary: How to preload chunks with webpack, as well as some not-so-obvious features
gh_link: null
discussion_id: null
weight: null
description: Using webpack to preload chunks in order to improve the user experience

---

## Introduction

Webpack is a well-established web bundler that is widely known (among other things) for its rich set of features.

One of the many cool aspects of webpack that I would like to focus on in this article is the concept of **preloading**, i.e. what it is, why it is needed and how it works.

Before jumping into the actual topic, we first have to quickly cover some preliminary notions in order to get the most out of this writing.

## Prerequisites

### What is a chunk?

When talking about webpack, the concept of a *chunk* can be hardly skipped over.

In simple terms, a chunk is a file that is created as a result of the bundling process. 
This generated file contains modules (which can be thought of as the initial files and their entire chains of dependencies), as well some *runtime code*, which is code added by webpack in order to achieve *its magic*.

There are multiple kind of chunks:
- entry chunks, i.e. chunks created from entry files, declared in the [`entry` configuration option](https://github.com/Andrei0872/understanding-webpack/blob/master/examples/chunk-preload/webpack.config.js#L9)
- async chunks, i.e. those created with the `import()` function
- chunks created automatically by webpack, e.g. when using [webpacks' `SplitChunksPlugin`](https://andreigatej.dev/blog/webpack-splitchunksplugin/)

<!--NOTE: -->
_I have written in more detail about what chunks are in webpack in this [previous article](https://andreigatej.dev/blog/webpack-what-is-a-chunk/)._

### The `import()` function

When we talk about preloading chunks, it is somehow implied that we are talking about **async chunks**. This kind of chunks are created with the help of
the `import()` function, so it is worth spending a few minutes on this.

Whenever webpack detects a call to `import('file.js')`, webpack will automatically create a chunk that corresponds to `file.js`, such that, when that line that invokes the function
is reached, an actual HTTP request will be made and, through this, the file will be fetched and then integrated into the application.

Why is it needed to talk about this concept before introducing *chunk preloading*?

Preloading, in itself, it is a strategy to optimise the experience of the users on the Internet. It narrows down to giving the browser certain instructions that will fetch
assets with higher priority (typically, one would use that for resource that are critical to the first navigation to the website). 
When we take into account that `import()` essentially creates files (i.e. assets) that will be loaded at a later time, it makes sense to sometimes want to preload such resources with priority.

We will see how to actually instruct webpack to apply this resource hint in a browser context, as well as other underpinnings of preloading in the following sections.

_As a side note (and as you might have guessed probably), the `import()` function can also be used to achieve [lazy loading](https://www.youtube.com/watch?v=gttkoU8YTkI&list=PL1Qj0WoSxDryPzQ7ZrR6ymu7M5k3mwEiA&index=11)._

## Preloading chunks

As hinted at earlier, _preloading_ is one of the [resource hints](https://web.dev/learn/performance/resource-hints#preload) available.

Applying this to webpack, this means we can preload **async chunks** (e.g. other JavaScript files) as early as possible. What *preloading* means is that the file (i.e. the chunk)
will be **fetched** over the network, but **not executed** yet. Instead of being executed, it will be stored in the browser's cache (we will henceforth assume that the file in question is cacheable) until the line that calls
`import()` is be reached.

We can tell webpack to preload an async chunk by using the `webpackPreload` magic comment in the `import()` function.
So, if we have this line in a file named `a.js`:

```js
// a.js
import(/* webpackPreload: true */ 'a1.js')
```

We would expect the file `a1.js` to be preloaded. However, as we will see, this will only happen under certain conditions. For instance,
if `a.js` is part of an *entry* chunk (e.g. for instance, as `index.js` is [here](https://github.com/Andrei0872/understanding-webpack/blob/master/examples/chunk-preload/webpack.config.js#L9)), then `a1.js` **can't be preloaded**. But, if we had something like this

```js
// index.js - entry file, mentioned in webpack configuration.
import('a.js')

// a.js.
import(/* webpackPreload: true */ 'a1.js')
```

Then, when the dynamic import for `a.js` takes place, the chunk that corresponds to `a1.js` **will be preloaded**.

We will clarify these facts later on in the article. For now, let's get familiar with the [demo application](https://github.com/Andrei0872/understanding-webpack/tree/master/examples/chunk-preload) which will help us gain a better understanding of this topic:

```
├── a1.js
├── a2.js
├── a.js
├── b.js
├── index.js
└── webpack.config.js
```

The only relevant information with respect to the wepback configuration is that the `index.js` file is the value of the [`entry` option](https://webpack.js.org/concepts/entry-points/).

The files - or, to use webpack's parlance, _modules_ - are not containing any logic more complex that a few simple **dynamic imports**. This diagram describes how these modules are connected: ![module relation diagram](./images/module-relations-diagram.png) 

A few clarifications regarding the diagram above:

- the green bounding rectangles represent **async chunks**; these chunks are created because of the use of the `import()` function
- the gray bounding rectangle indicates an **entry chunk**, i.e. a chunk that will be invariably by the browser
- the yellow contained rectangles represent **modules** that are part of certain chunks
- `a.js` dynamically imports `a1.js` with `import(/* webpackChunkName: 'a1', webpackPreload: true */ "./a1")`; which means `a1.js` will be preloaded
- all dynamic imports are conditional, e.g. the `import()` function is called, for instance, on a button click; this is relevant because the dynamic chunks are not be loaded immediately

Upon page load, only the `index` chunk will be loaded.

What would happen if the line that calls `import('b.js')` is reached?
Since `b` is an async chunk, what happens is the `b.js` file will be fetched over the network (e.g. through an HTTP request) and then it will be immediately executed.
This means there is no preloading involved and, as a result, the user might need to wait for the network request to complete, as well for parsing and executing the file.
**However**, this does not mean the *preload* resource hint should be overused - there could be downsides to it, too, such as cache pollution or redundantly used bandwidth.  
So, we should always choose our tools wisely!

When importing `a.js`, because it has instructed webpack to **preload** `a1.js`, the `a1` chunk **will also be fetched** over the network, but not executed. Instead, it will be stored in the browser's cache:

![request for a1](./images/a1-req.png)

The `a1.js` file will be executed only when the line in `a.js` that dynamically imports `a1.js` is reached. Then, **instead of making an HTTP request**, the `a1.js` file will be retrieved right away from the cache and executed
This it the beauty of preloading assets, in general.

In this small example, we only focused on preloading JavaScript files, but the concept should apply for other resources too, such as fonts, images, videos, etc.

_I walked through this example also in this [YouTube video](https://www.youtube.com/watch?v=RHZDvNyWa2Y)._

In the next section, we will take a look at a slightly more complicated example of preloading, an example I have named, perhaps lacking inspiration, *nested preloading*.

##  Nested preloading

Here is an interesting and practical question worth investigating: *What happens if a preloaded chunk also preloads other chunks?* 

Getting back to our diagram, there is just a simple addition: `a1.js` dynamically imports `a2.js` with the `webpackPreload: true` magic comment:

![nested preloading](./images/nested-preloading.png) 

When will `a2.js`'s chunk be fetched? Will it be fetched when the `a.js` file is executed? Or maybe not when `a.js` is executed?

When this question came to mind, I immediately became very intrigued. So intrigued that I had to [make a video](https://youtu.be/n5qT2Z-mrzY?si=JNtCkEnTQGaw-sId) about it where I explore my hypothesis and final result.

Let's take a step-by-step approach to the questions above.
Firstly and invariably, `index.js` will be fetched and executed in the browser. This is because `index.js` is an entry file (which makes the `index` chunk an *entry chunk*).
Then, when `a.js` is imported at a later time, because it preloads `a1.js`, the latter will only be fetched by the browser, but not executed. The file will be executed when the line in `a.js` that imports `a1.js` is reached.

However, what about the fact that `a1.js` (the module that has just been fetched by the browser) **also preloads** `a2.js`? Will `a2.js` be fetched now, too?

The answer is **no**. The explanation is straightforward: `a2.js` can't be fetched because this only happens when `a1.js` is executed by the browser, i.e. when it is actually required.
But, at this point, `a1.js` has **only** been fetched and not yet required. So, since `a1.js` is not executed -> `a2.js` can't be fetched.

What we have explored in this section was indeed not very complicated, but, in the next one, we will address a question that requires some under-the-hood knowledge of webpack. Let's see what that is about!

## Not all chunks can be preloaded

Although it may sound counter-intuitive, it is true - **not all async chunks** can be preloaded.

Coming back to our demo application, [let's try preloading `a.js` from `index.js`](https://github.com/Andrei0872/understanding-webpack/blob/master/examples/chunk-preload/index.js#L1-L5):

```js
import(/* webpackChunkName: 'a', webpackPreload: true */ "./a.js")
```

If we reload the browser, we will see no HTTP request for the `a.js` in the network tab, which means the file has not been preloaded.

But, why is that? Why can't `a.js` be preloaded?

Let's bring back the diagram, with a small modification included:

![preloading the chunk a](./images/preloading-a-chunk.png) 

One thing that stands out from this diagram is that an *entry chunk* dynamically imports an *async chunk*.
And this is, actually, the reason as to why the `a` chunk can't be preloaded - its **parent chunk** is an entry chunk.

Now, another question emerges - why can't an entry chunk preload an async chunk?
After some research, I have found [this comment](https://github.com/jantimon/html-webpack-plugin/issues/1317#issuecomment-704870353) on an issue:

> When using preload you must use the script (call import()) within a few seconds [...] So only use preload when the imported module is mandatory for correct function of the app and the app is useless without it.

To my understanding, if a chunk is **critical to an entry chunk** (this is what is being indicated by using the *preload* resource hint), then the async chunk can be statically imported. 
It it different if an async chunk needs has other async chunks that are critical for the functionality of the former, because one can't know for sure when the async chunk is actually loaded/needed.

If you are curious to read the source code that is responsible for all of this magic, you can start from [here](https://github.com/webpack/webpack/blob/main/lib/prefetch/ChunkPrefetchPreloadPlugin.js#L46-L48).
I have also created a [repo](https://github.com/Andrei0872/understanding-webpack) where you can find debugging instructions for exploring webpack via the debugger.

## Conclusion

In this article, we have been reminded, first of all, of what *preloading* means - it is a browser resource hint that allows us to fetch resources with priority, as soon as possible.

Then, we have learned about what preloading really means in the context of webpack, the essential role of the `import()` function, what *entry chunks* are, what *async chunks* are and how the ways these are connected influence the preloading behaviour.

Thank you for reading!
