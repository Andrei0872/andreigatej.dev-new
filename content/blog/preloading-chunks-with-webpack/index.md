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

As hinted at earlier, preloading is one of the [resource hints](https://web.dev/learn/performance/resource-hints#preload) available.

Applying this to webpack, this means we can preload **async chunks** (e.g. other JavaScript files) as early as possible. What *preloading* means is that the file (i.e. the chunk)
will be **fetched** over the network, but **not executed** yet. Instead of being executed, it will be stored in the browser's cache until the line that calls
`import()` is be reached.

What this means is that if we have this in a file named `a.js`:

```js
import(/* webpackPreload: true */ 'a1.js')
```

We would expect the file `a1.js` to be preloaded. However, as we will see, this will only happen under certain conditions. For instance,
if `a.js` is part of an *entry* chunk, then `a1.js` **can't be preloaded**. But, if we had something like this

```js
// index.js - entry file in webpack configuration.
import('a.js')

// a.js.
import(/* webpackPreload: true */ 'a1.js')
```

Then, when the dynamic import for `a.js` takes place, the chunk that corresponds to `a1.js` **will be preloaded**.

We will clarify these facts later on in the article. For now, let's get familiar with the demo application which will help us gain a better understanding of this topic:

```

```

- demo app
- diagram


##  'nested' preloading
##  ? under the hood
