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
- entry chunks, i.e. chunks created from entry files, declared in the `entry` configuration option
- async chunks, i.e. those created with the `import()` function
- chunks created automatically by webpack, e.g. when using [webpacks' `SplitChunksPlugin`](https://andreigatej.dev/blog/webpack-splitchunksplugin/)

<!--NOTE: -->
_I have written in detail about what chunks are in webpack in this [previous article](https://andreigatej.dev/blog/webpack-what-is-a-chunk/)._

### The `import()` function

When we talk about preloading chunks, it is somehow implied that we are talking about **async chunks**. This kind of chunks are created with the help of
the `import()` function, so it is worth spending a few minutes on this.

Whenever webpack detects a call to `import('file.js')`, webpack will automatically create a chunk that corresponds to `file.js`, such that, when that line that invokes the function
is reached, an actual HTTP request will be made and, through this, the file will be fetched and then integrated into the application.

Why is it needed to talk about this concept before introducing *chunk preloading*?

Preloading, in itself, it is a strategy to optimise the experience of the users on the Internet. It narrows down to giving the browser certain instructions that will fetch
assets with higher priority (typically, one would use that for resource that are critical to the first navigation to the website). 
When we take into account that `import()` essentially creates files (i.e. assets) that will be loaded at a later time, it makes sense to want to preload such resources with priority.

We will see how to actually instruct webpack to apply this resource hint in a browser context, as well as other underpinnings of preloading in the following sections.

_As a side note (and as you might have guessed probably), the `import()` function can also be used to achieve [lazy loading](https://www.youtube.com/watch?v=gttkoU8YTkI&list=PL1Qj0WoSxDryPzQ7ZrR6ymu7M5k3mwEiA&index=11)._

## Preloading chunks

As hinted at earlier, _preloading_ is one of the [resource hints](https://web.dev/learn/performance/resource-hints#preload) available.

Applying this to webpack, this means we can preload **async chunks** (e.g. other JavaScript files) as early as possible. What *preloading* means is that the file (i.e. the chunk)
will be **fetched** over the network, but **not executed** yet. Instead of being executed, it will be stored in the browser's cache (we will henceforth assume that the file in question is cacheable) until the line that calls
`import()` is be reached.

What this means, for example, is that if we have this line in a file named `a.js`:

```js
import(/* webpackPreload: true */ 'a1.js')
```

We would expect the file `a1.js` to be preloaded. However, as we will see, this will only happen under certain conditions. For instance,
if `a.js` is part of an *entry* chunk, then `a1.js` **can't be preloaded**. But, if we had something like this

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

The files or, to use webpack's parlance, are not containing any logic more complex that a few simple **dynamic imports**. This diagram describes how these modules are connected:

![module relation diagram](./images/module-relations-diagram.png) 

A few clarifications regarding the diagram above:

- the green bounding rectangles represent **async chunks**; these chunks are created because of the use of the `import()` function
- the gray bounding rectangle indicates an **entry chunk**, i.e. a chunk that will be invariably by the browser
- the yellow contained rectangles represent **modules** that are part of certain chunks
- `a.js` dynamically imports `a1.js` with `import(/* webpackChunkName: 'a1', webpackPreload: true */ "./a1")`; which means `a1.js` will be preloaded
- all dynamic imports are conditional, e.g. the `import()` function is called, for instance, on a button click; this is relevant because the dynamic chunks are not be loaded immediately

Upon page load, only the `index` chunk will be loaded.

What would happen if the line that calls `import('b.js')` is reached?
Since `b` is an async chunk, what happens is the `b.js` file will be fetched over the network (e.g. through an HTTP request) and then it will be immediately executed.

Let's see how things go if `import('a.js')` is reached. Firstly, the same thing will happen as for `b` - the `a` chunk will be fetched over the network and then executed.
However, because `a.js` has instructed webpack to **preload** `a1.js`, the `a1` chunk **will also be fetched** over the network, but not executed. Instead, it will be stored in the browser's cache:

![request for a1](./images/a1-req.png)

The `a1.js` file will be executed only when the line in `a.js` that dynamically imports `a1.js` is reached. Then, **instead of making an HTTP request**, the `a1.js` file will be retrieved right away from the cache and executed
This it the beauty of preloading assets in general.

In this small example, we only focused on preloading JavaScript files, but the concept should apply for other resources too, such as fonts, images, videos, etc.

_I walked through this example also in this [YouTube video](https://www.youtube.com/watch?v=RHZDvNyWa2Y)._

In the next section, we will take a look at a slightly more complicated example of preloading, an example I have named, perhaps lacking inspiration, *nested preloading*.

##  Nested preloading

Here is an interesting and practical question worth investigating: *What happens if a preloaded chunk also preloads other chunks?* 

Getting back to our diagram, there is just a simple addition: `a1.js` dynamically imports `a2.js` with the `webpackPrefetch: true` magic comment:

![nested preloading](./images/nested-preloading.png) 

When will `a2.js`'s chunk be fetched? Will it be fetched when the `a.js` file is executed? Or maybe not when `a.js` is executed?

When this question came to mind, I immediately became very intrigued. So intrigued that I had to [make a video](https://youtu.be/n5qT2Z-mrzY?si=JNtCkEnTQGaw-sId) about it where I explore my hypothesis and final result.

Let's take a step-by-step approach to the questions above.
Firstly and invariably, `index.js` will be fetched and executed in the browser. This is because `index.js` is an entry file (which makes the `index` chunk an *entry chunk*).
Then, when `a.js` is imported at a later time, because it preloads `a1.js`, the latter will only be fetched by the browser, but not executed. This will happen when the line in `a.js` that imports `a1.js` is reached.

However, what about the fact that `a1.js` (the module that has just been fetched by the browser) **also preloads** `a2.js`? Will `a2.js` be fetched now, too?

The answer is **no**. The explanation is straightforward: `a2.js` can't be fetched because this only happens when `a1.js` is executed by the browser, i.e. when it is actually required.
But, at this point, `a1.js` has **only** been fetched and not yet required. So, since `a1.js` is not executed -> `a2.js` can't be fetched.

What we have explored in this question was indeed not very complicated, but, in the next section, we will address a question that required some under-the-hood knowledge of webpack. Let's see what that is about.

## Not all chunks can be preloaded

- provide source code
- explanation
- webpack thread
