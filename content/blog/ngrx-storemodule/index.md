---
title: "Understanding the magic behind StoreModule of NgRx (@ngrx/store)"
date: 2020-04-07
draft: false
blog_tags: ["angular", "ngrx"]
discussion_id: null
description: "Understanding the magic behind StoreModule of NgRx (@ngrx/store)"
---


_This article has been published on [indepth.dev](https://indepth.dev/posts/1199/understanding-the-magic-behind-ngrx-store)._

## Introduction

I was writing this article as I was going through the source code trying to understand how the main entities of the `@ngrx/store` module are tied together. As a result I found a bunch of interesting stuff related to each component of the module and this is what I'll be describing in this article. We’re going to examine each entity in detail and I'll explain its role in the overall architecture.

Before diving in, let’s quickly recap what the main entities are:

*   **State:** a data structure where the internal state of the application is kept
*   **Store**: a bridge between the data consumer and the state
*   **Actions**: a mechanism that triggers state changes
*   **Reducers**: a mechanism that performs state changes by writing into state
*   **Meta-reducers**: a mechanism to hook into the action -> reducer pipeline

We'll start with actions.

## Actions

Actions can be thought of as instructions for reducers and they also represent the base of an effect. They are usually dispatched from the view layer (a smart component, a service etc.) or from effects.

### Creating actions

Actions can be created in 3 ways:

```ts
const action = createAction('[Entity] simple action');
action();
```

```ts
const action = createAction('[Entity] simple action', props<{ name: string, age: number, }>());
action({ name: 'andrei', age: 18 });
```

```ts
const action = createAction('action',(u: User, prefix: string) => ({ name: `${prefix}${u.name}` }) );
const u: User = { /* ... */ };
action(u, '@@@@');
```

In each case, the return value of the function will be an object that will contain at least this property: `{ type: T }`.

Also, the type (first argument of `createAction`) will be attached as property to the function. This is useful to know when reducers are created.

```ts
function defineType<T extends string>(
  type: T,
  creator: Creator
): ActionCreator<T> {
  return Object.defineProperty(creator, 'type', {
    value: type,
    writable: false,
  });
}
```

### TypeScript’s magic

Now are going to reveal what important role TypeScript plays here. Ever wondered, for example, why is the `props()` function useful? Let's find out!

The `createAction` function comes with 3 overloads:

```ts
export declare interface TypedAction<T extends string> extends Action {
  readonly type: T;
}

export type ActionCreator<
  T extends string = string,
  C extends Creator = Creator
> = C & TypedAction<T>;

export function createAction<T extends string>(
  type: T
): ActionCreator<T, () => TypedAction<T>>;
export function createAction<T extends string, P extends object>(
  type: T,
  config: Props<P> & NotAllowedCheck<P>
): ActionCreator<T, (props: P & NotAllowedCheck<P>) => P & TypedAction<T>>;
export function createAction<
  T extends string,
  P extends any[],
  R extends object
>(
  type: T,
  creator: Creator<P, R> & NotAllowedCheck<R>
): FunctionWithParametersType<P, R & TypedAction<T>> & TypedAction<T>;
```

which implies that the function’s body will have to contain a few type guards in order to get the types right.

`ActionCreator<T, C>` represents a function of type `C` that has a readonly property `type` of type `T`. The `type` can also be used to discriminate unions.

Let’s examine each overload.

### `createAction` with only `type` parameter

```ts
const action = createAction('[Entity] simple action');
action(); // { type: [Entity] simple action }
```

corresponds to this overload:

```ts
export function createAction<T extends string>(
  type: T
): ActionCreator<T, () => TypedAction<T>>;
```

We can deduce from the above snippet that the return type will be a function which will return an object with a property `type`.

Here’s the type guard which reveals that:

```ts
export function createAction<T extends string, C extends Creator>(
  type: T,
  config?: { _as: 'props' } | C
): ActionCreator<T> {
  
  const as = config ? config._as : 'empty';
  
  switch (as) {
    case 'empty':
      return defineType(type, () => ({ type }));
    /* ... */
  }
}
```

where `defineType` will attach the property `type` to the function(in this case `() => ({ type })`).

### `createAction` with props

This approach can be used when you want to dispatch an action that contains some data which is valuable to the reducer(e.g `userActions.add({ name, age })`).

```ts
const action = createAction('[Entity] simple action', props<{ name: string, age: number, }>());
action({ name: 'andrei', age: 18 });
```

What `props<T>()` does is to return an object with a predefined key(`_as: 'props'`) and with a key of type `T` which is useful for type inference.

```ts
export function props<P extends object>(): Props<P> {
  return { _as: 'props', _p: undefined! };
}

export interface Props<T> {
  _as: 'props';
  _p: T;
}
```

This is how the overload looks:

```ts
export function createAction<T extends string, P extends object>(
  type: T,
  config: Props<P> & NotAllowedCheck<P>
): ActionCreator<T, (props: P & NotAllowedCheck<P>) => P & TypedAction<T>>;
```

`config` will be an instance of `props<P>()`, which allows `P` to be inferred and to be used in `(props: P & NotAllowedCheck<P>) => P & TypedAction<T>>`.

`ActionCreator<T, (props: P & NotAllowedCheck<P>) => P & TypedAction<T>>` will be a function that can be called with one argument(an object), whose type will be `P`(inferred from `props<P>()`) and whose return type will be an object that contains all the properties of `P`(`P` is an object) and the `type` property(`TypedAction<T>`).

Here’s how `createAction` establishes this:


```ts
export function createAction<T extends string, C extends Creator>(
  type: T,
  config?: { _as: 'props' } | C
): ActionCreator<T> {
  if (typeof config === 'function') {
  /* ... */
  // `config._as` - returned from `props()`
  const as = config ? config._as : 'empty';
  
  switch (as) {
    /* ... */
    case 'props':
      return defineType(type, (props: object) => ({
        ...props,
        type,
      }));
    /* ... */
  }
}
```

### `createAction` with a function

This comes in handy when you want to modify the data before it reaches the reducer. Or you might simply want to determine the action’s data based on some more complicated logic.  

```ts
const action = createAction(
  'action', 
  (u: User, prefix: string) => ({ name: `${prefix}${u.name}` }) 
);
const u: User = { /* ... */ };
action(u, '@@@@');
```

The overload for this looks as follows:

```ts
export function createAction<
  T extends string,
  P extends any[],
  R extends object
>(
  type: T,
  creator: Creator<P, R> & NotAllowedCheck<R>
): FunctionWithParametersType<P, R & TypedAction<T>> & TypedAction<T>;
```

`Creator<P, R>` is simply a function takes up a parameter of type `P` and returns an object of type `R`. This will allow us to infer the `P` and `R` types. `NotAllowedCheck<R>` makes sure that the `creator` is not an existing action or an array. It must be a function that receives some arguments and based on them, it returns an object that represents the action's data.

  
`FunctionWithParametersType<P, R & TypedAction<T>> & TypedAction<T>;` means that the return type must be a function whose arguments are of type `P`(inferred from `Creator<P, R>`), which returns an object of type `R`(also inferred from `Creator<P, R>`) and has a property `type`.

This is what happens inside `createAction`:

```ts
export function createAction<T extends string, C extends Creator>(
  type: T,
  config?: { _as: 'props' } | C
): ActionCreator<T> {
  if (typeof config === 'function') {
    return defineType(type, (...args: any[]) => ({
      // `config(...args)` will return an object
      ...config(...args),
      type, // The `type` property is always returned
    }));
  }

  /* ... */
}
```

## Reducers

Reducers are pure functions that are responsible for state changes.

Here’s the interface that describes the shape of a reducer:

```ts
export interface ActionReducer<T, V extends Action = Action> {
  (state: T | undefined, action: V): T;
}
```

As you can see, a reducer takes 2 parameters: the current `state` and the current `action` that has been dispatched.

### Providing reducers

Reducers can be provided in two ways:

*   an object whose values are reducers created with the help of `createReducer`

    ```ts
    StoreModule.forRoot({ foo: fooReducer, user: UserReducer })
    ```

    Each key represents a slice of the store.

*   an injection token

    ```ts
    const REDUCERS_TOKEN = new InjectionToken('REDUCERS');

    @NgModule({
      imports: [
        StoreModule.forRoot(REDUCERS_TOKEN)
      ],
      providers: [
        { provide: REDUCERS_TOKEN, useValue: { foo: fooReducer } }
      ],
    }) /* ... */
    ```

### How are reducers set up?

Let’s assume reducers are provided this way:

```ts
StoreModule.forRoot({ entity: entityReducer })
```

`StoreModule.forRoot` will return a `ModuleWithProviders` object which contains, among others, these providers:

```ts
/* ... */
{
  provide: _REDUCER_FACTORY,
  useValue: config.reducerFactory
    ? config.reducerFactory
    : combineReducers,
},
{
  provide: REDUCER_FACTORY,
  deps: [_REDUCER_FACTORY, _RESOLVED_META_REDUCERS],
  useFactory: createReducerFactory,
},
/* ... */
```

As you can see, unless you provide a custom reducer factory, the `combineReducers` function will be used instead(we'll have a look at it in a moment). `createReducerFactory` is mainly used to add the **meta-reducers**.

The `REDUCER_FACTORY` token will only be injected in `ReducerManager` class:

```ts
export class ReducerManager /* ... */ {
  constructor(
    @Inject(INITIAL_STATE) private initialState: any,
    @Inject(INITIAL_REDUCERS) private reducers: ActionReducerMap<any, any>,
    @Inject(REDUCER_FACTORY)
    private reducerFactory: ActionReducerFactory<any, any>
  ) {
    super(reducerFactory(reducers, initialState));
  }
  /* ... */
}
```

As soon as that happens, the `createReducerFactory` function will be invoked, meaning that `reducerFactory` property will hold its return value, which is a function that takes an object of reducers(the `reducers` parameter below) and, optionally, the `initialState`:

```ts
export function createReducerFactory<T, V extends Action = Action>(
  reducerFactory: ActionReducerFactory<T, V>,
  metaReducers?: MetaReducer<T, V>[]
): ActionReducerFactory<T, V> {
  if (Array.isArray(metaReducers) && metaReducers.length > 0) {
    (reducerFactory as any) = compose.apply(null, [
      ...metaReducers,
      reducerFactory,
    ]);
  }

  // `ReducerManager.reducerFactory` will hold this function! - it is immediately invoked in the constructor
  return (reducers: ActionReducerMap<T, V>, initialState?: InitialState<T>) => {
    const reducer = reducerFactory(reducers);
    return (state: T | undefined, action: V) => {
      // This function is the value resulted from `super(reducerFactory(reducers, initialState));`(takes place inside `ReducerManager`'s constructor)
      state = state === undefined ? (initialState as T) : state;
      return reducer(state, action);
    };
  };
}
```

Invoking `super(reducerFactory(reducers, initialState))` will combine all the reducers into one object, whose keys represent the store's slices key corresponds to a reducer:

```ts
export function combineReducers(
  reducers: any,
  initialState: any = {}
): ActionReducer<any, Action> {
  const reducerKeys = Object.keys(reducers);
  const finalReducers: any = {};

  for (let i = 0; i < reducerKeys.length; i++) {
    const key = reducerKeys[i];
    if (typeof reducers[key] === 'function') {
      finalReducers[key] = reducers[key];
    }
  }

  /* 
  Remember from the previous snippet: `const reducer = reducerFactory(reducers)`
  Now, the `reducer` will be the below function.
  */
  return function combination(state, action) {
    state = state === undefined ? initialState : state;
    let hasChanged = false;
    const nextState: any = {};
    for (let i = 0; i < finalReducerKeys.length; i++) {
      const key = finalReducerKeys[i];
      const reducer: any = finalReducers[key];
      const previousStateForKey = state[key];
      const nextStateForKey = reducer(previousStateForKey, action);

      nextState[key] = nextStateForKey;
      hasChanged = hasChanged || nextStateForKey !== previousStateForKey;
    }
    return hasChanged ? nextState : state;
  };
}
```

Additionally, we can see in the above snippet why the stored data must be immutable. If a reducer returned the same reference of an object, but with a property changed, this would not be reflected into the UI as `nextStateForKey !== previousStateForKey` would fail.

The gist resides in this snippet:

```ts
/* ... */
// The below function is the result of 
// `@Inject(REDUCER_FACTORY) private reducerFactory: ActionReducerFactory<any, any>`
return (reducers: ActionReducerMap<T, V>, initialState?: InitialState<T>) => { // #Fn1
  const reducer = reducerFactory(reducers); // <-
  return (state: T | undefined, action: V) => { // #Fn2
    state = state === undefined ? (initialState as T) : state;
    // `reducer` = `combination` function; when called, will iterate over the existing reducers
    // and will call them with the current `state` and `action`
    return reducer(state, action); 
  };
};
```

`_super(reducerFactory(reducers, initialState))_` _will cause the above_ `_reducerFactory_` _to be called, which will eventually combine all the reducers_.

After `reducerFactory` is called in `const reducer = reducerFactory(reducers)`, the `reducer` will act on behalf of `combination` function. When invoked, it will iterate over the reducers and invoke them with the given `state` and `action`.

The function in which `reducer` is invoked will be called every time an action is dispatched, meaning that the reducers will be combined(on `Fn1` call) once. Of course, if other reducers are added/removed later, the reducer object will be re-created properly(`Fn1` called again).

### createReducer helper  

In order to create reducers that will handle state changes, we can use the `createReducer()` function.

It receives these arguments: the `initialState` and an indefinite number of `on` functions whose type will depend on the type of `initialState`.

**The `on` functions are an alternative for using the `switch` statement.** An `on` function can receive multiple action creators(results of [`createAction`](https://github.com/Andrei0872/my-dev-notes/blob/master/articles/ngrx/ngrx-store.md#creating-actions)) and the actual reducer as the last argument.

It will return an object `{ types: string[], reducer: ActionReducer<S> }`, where `types` is the type of each provided action creator and reducer is a pure function which handles state changes based on the action and has this signature: `(state: T | undefined, action: V): T;`.

```ts
export interface On<S> {
  reducer: ActionReducer<S>;
  types: string[];
}

export interface OnReducer<S, C extends ActionCreator[]> {
  (state: S, action: ActionType<C[number]>): S; // `ActionType` - Will infer the type of the action
}

export function on<C1 extends ActionCreator, S>(
  creator1: C1,
  reducer: OnReducer<S, [C1]>
): On<S>;
/* ... Overloads ... */
export function on(
  ...args: (ActionCreator | Function)[]
): { reducer: Function; types: string[] } {
  const reducer = args.pop() as Function;
  const types = args.reduce(
    // `creator.type` is a property directly attached to the function so that
    // it can be easily accessed(`createAction` is responsible for that)
    (result, creator) => [...result, (creator as ActionCreator).type],
    [] as string[]
  );
  return { reducer, types };
}
```

The `createReducer` function will create a private `Map<string, ActionReducer<S, A>>` object, where the key is the `type` of the action, and the value is the corresponding reducer. It will also return a function whose arguments will be a given state and an action. Because it is a closure, it has access to the `Map` object.

This function will be invoked every time an action is dispatched and what will do is to get the reducer based on the action type. Then, if the reducer is found, it will be called and will potentially return a new state.

```ts
export interface ActionReducer<T, V extends Action = Action> {
  (state: T | undefined, action: V): T;
}

export function createReducer<S, A extends Action = Action>(
initialState: S,
...ons: On<S>[]
): ActionReducer<S, A> {
  const map = new Map<string, ActionReducer<S, A>>();
  for (let on of ons) {
    for (let type of on.types) {
      if (map.has(type)) {
        const existingReducer = map.get(type) as ActionReducer<S, A>;
        const newReducer: ActionReducer<S, A> = (state, action) =>
          on.reducer(existingReducer(state, action), action);
        map.set(type, newReducer);
      } else {
        map.set(type, on.reducer);
      }
    }
  }

  return function(state: S = initialState, action: A): S {
    // This is the body of `_counterReducer` function from below
    const reducer = map.get(action.type);
    return reducer ? reducer(state, action) : state;
  };
}
```

For instance, the `Map` object for the following `createReducer` reducer

```ts
const increment = createAction('increment');
const decrement = createAction('decrement');
const reset = createAction('reset');

const _counterReducer = createReducer(initialState,
  on(increment, state => state + 1 /* reducer#1 */),
  on(decrement, state => state - 1 /* reducer#2 */),
  on(reset, state => 0 /* reducer#3 */),
);

export function counterReducer(state, action) {
  return _counterReducer(state, action);
}
```

will look like this:

```ts
{
  key: "increment"
  value: ƒ (state) // reducer#1
},
{
  key: "decrement"
  value: ƒ (state) // reducer#2
},
{
  key: "reset"
  value: ƒ (state) // reducer#3
}
```

The `createReducer`'s returned function

```ts
return function(state: S = initialState, action: A): S {
  const reducer = map.get(action.type);
  return reducer ? reducer(state, action) : state;
};
```
will be called from `combination` function's body:

```ts
return function combination(state, action) {
  for (let i = 0; i < finalReducerKeys.length; i++) {
    /* ... */
    const reducer: any = finalReducers[key];
    const nextStateForKey = reducer(previousStateForKey, action); // <- Here!

    /* ... */
  }
  /* ... */
};
```

The `on` function can _bind_ a reducer to multiple actions. Then, in the reducer, with the help of discriminated unions, we can perform the appropriate state change depending on action.

```ts
const a1 = createAction('a1', props<{ name: string }>());
const a2 = createAction('a2', props<{ age: number }>());

const initialState = /* ... */;

const reducer = createReducer(
  initialState,
  on(a1, a2, (state, action) => {
    if (action.type === 'a1') {
      action.name
    } else {
      action.age
    }
  }),
)
```

Here’s why this is possible:

```ts
export function on<C1 extends ActionCreator, C2 extends ActionCreator, S>(
  creator1: C1,
  creator2: C2,
  reducer: OnReducer<S, [C1, C2]>
): On<S>;

// `C[number]` will result in a union
export interface OnReducer<S, C extends ActionCreator[]> {
  (state: S, action: ActionType<C[number]>): S;
}
```

Also, it is worth mentioning that the entire State type will be inferred from what is being passed as `initialState`:

```ts
export function createReducer<S, A extends Action = Action>(
  initialState: S,
  ...ons: On<S>[]
): ActionReducer<S, A> { /* ... */ }
```

[_TypeScript Playground_](https://www.typescriptlang.org/play/#code/JYOwLgpgTgZghgYwgAgIILMA9iZBvAKGWSgjgBMcAbAT2TBoAcIAuZAZzClAHMBuAgF8CBUJFiIUqAIz4i9Jq2QByONOUAaeSDgBbJZ24h+QkWOjwkaAExziDZm1XXN8uDyUgArroBG0AWECBxQAcQgwAFUQbBAAHlRkCAAPSBBydjQMWIBtAF0APmQAXjQc7z9oPIFgxWRo2JLkcKiYnDicmQ0bQpqEHE5kLDYGnCbCe0UnNVdiHX1p9NJgWeQAejXkdyVpawBmZABaIugoLCghIA).

Another great feature that `createReducer` comes with is composability. You can use the same action with multiple reducers. What this means is that an `n`th `on`'s reducer state which has an action `a` will be result of the `n-1`th `on`'s reducer that has the same action `a`:

```ts
export function createReducer<S, A extends Action = Action>(
  initialState: S,
  ...ons: On<S>[]
): ActionReducer<S, A> {
  const map = new Map<string, ActionReducer<S, A>>();
  for (let on of ons) {
    for (let type of on.types) {
      if (map.has(type)) {
        // Getting the previous reducer(`n-1`)
        const existingReducer = map.get(type) as ActionReducer<S, A>;

        // The new reducer's state will be the result of the previous reducer's result
        // n = n(n-1(state, action),  action)
        const newReducer: ActionReducer<S, A> = (state, action) =>
          on.reducer(existingReducer(state, action), action);
        map.set(type, newReducer);
      } else { /* ... */ }
    }
  }

  return function(state: S = initialState, action: A): S { /* ... */ };
}
```
Here’s an example:

```ts
const a1 = createAction('a1');
const a2 = createAction('a2');

const reducer = createReducer(
  0,
  on(a1, state => state + 2 /* reducer1 */),
  on(a1, state => state ** 2 /* reducer2 */),
  on(a1, state => state * 10 /* reducer3 */)
);

console.log(reducer(undefined, a1)); // 40

// The above is similar to this:
reducer3(reducer2(reducer1(0)));
```

## Store

This is one of the `ngrx/store`'s foundations. This is not the place where the information is kept, but rather a bridge between the data consumer (a smart component) and the place where the information is kept (the `State` entity).

```ts
export class Store<T> extends Observable<T> implements Observer<Action> {
  constructor(
    state$: StateObservable,
    private actionsObserver: ActionsSubject,
    private reducerManager: ReducerManager
  ) {
    super();

    this.source = state$;
  }
  
  /* ... */
}
```

From the above snippet we can tell that the `Store` class is a hot observable because the data it emits comes from outside, namely `state$`. This means that every time the `source` (`state$`) emits, the `Store` class will send the value to _its subscribers_. This is possible because `state$` extends `BehaviorSubject` and by setting this as a source to any other observable, whenever that observable is subscribed to, that observer(subscriber) will be added to the subscribers list maintained by the `BehaviorSubject`. Here’s an example which illustrates these facts:

```ts
const s = new Subject();

class Custom extends Observable<any> {
  constructor () {
    super();
    
    // By doing this, every time you do `customInstance.subscribe(subscriber)`,
    // the subscriber wll be part of the subject's subscribers list
    this.source = s;
  }
}

const obs$ = new Custom();

// The subject has no subscribers at this point
s.next('no');

// The subject has one subscriber now
obs$.subscribe(console.log);

// `s.next()` -> sending values to the active subscribers
timer(1000)
  .subscribe(() => s.next('john'));

timer(2000)
  .subscribe(() => s.next('doe'));
```

[_StackBlitz._](https://medium.com/r/?url=https%3A%2F%2Fstackblitz.com%2Fedit%2Fmanual-set-source%3Ffile%3Dindex.ts)

It is worth noticing the presence of `ActionsSubject`, with which we are able to push values in the action stream whenever the `Store.dispatch` is called.

```ts
dispatch<V extends Action = Action>(
  action: V /* ... type check here - skipped for brevity ... */
) {
  this.actionsObserver.next(action);
}
```

You can think of this `Store` class as a dispatcher, because it can dispatch actions with `Store.dispatch(action)`, but you can also think of it as a data receiver, because you can be notified about changes in the state is by subscribing to a `Store` instance(`Store.subscribe()`).

```markdown
allows consumer ↔️ state communication
        ⬆️
        |
        |
-----------      newState          -----------                         
|         | <-------------------   |         |                         
|         |  Store.source=$state   |         |
|         |                        |         | <---- storing data 
|  Store  |      Action            |  State  |                         
|         | -------------------->  |         |
|         |   Store.dispatch()     |         |          
-----------                        ----------- 
                                   |        ⬆️
                          Action   |        | newState
                                   |        |
                                   ⬇️        |
                                  ------------- 
                                  |           | 
                                  |  Reducer  | <---- state changes
                                  |           | 
                                  -------------
```

So, the `State` class is the place where _actions meet reducers_, where the reducers are called with the existing state and based on the action, it will generate and emit a new state through the `Store`(because the `Store`'s source is the `State` itself).

```ts
export class State<T> extends BehaviorSubject<any> implements OnDestroy {
  constructor(
    actions$: ActionsSubject,
    reducer$: ReducerObservable,
    scannedActions: ScannedActionsSubject,
    @Inject(INITIAL_STATE) initialState: any
  ) { 
    /* ... */ 

    this.stateSubscription = stateAndAction$.subscribe(({ state, action }) => {
      this.next(state); // Emitting the new state
      scannedActions.next(action);
    });
  }
  /* ... */
}
```

I’d see the `Store` class as some sort of middleman between the `Model`(the place where the data is actually stored) and the `Data Consumer`:

`Data Consumer` -> `Model`: `Store.dispatch()`  
`Model` -> `Data Consumer`: `Store.subscribe()`

As a side note, `Store` can not only be used as an observable, but also as an observer(e.g: when intercepting actions emitted by the effects).

```ts
next(action: Action) {
  this.actionsObserver.next(action);
}

error(err: any) {
  this.actionsObserver.error(err);
}

complete() {
  this.actionsObserver.complete();
}
```

This might also come in handy when you can’t know which action and when you’ll want to dispatch.

```ts
const actions$ = of(FooActions.add({ age: 18, name: 'andrei' }));

actions$.subscribe(this.store)
```

### Selecting from the Store

Because `Store`'s source is `State` , which is where the data is kept, selecting from the store and receiving eventual updates is a seamless operation.

We can use both `Store.select('path' | customSelector)`:

```ts
export class Store<T> /* ... */ {
  select<Props = any, K = any>(
    pathOrMapFn: ((state: T, props?: Props) => K) | string,
    ...paths: string[]
  ): Observable<any> {
    return (select as any).call(null, pathOrMapFn, ...paths)(this);
  }
}

export function select<T, Props, K>(
  pathOrMapFn: ((state: T, props?: Props) => any) | string,
  propsOrPath?: Props | string,
  ...paths: string[]
) {
  return function selectOperator(source$: Observable<T>): Observable<K> {
    let mapped$: Observable<any>;

    /* ... Important logic here ... */

    return mapped$.pipe(distinctUntilChanged());
  };
}
```

or `Store.pipe(select('path') | select(customSelector))`. As you can see, both approaches will make use of the `select` function and will return an observable.

Assuming you have have a state that complies with this interface:

```ts
interface AppState { foo: Foo; }

interface Foo {
  fooUsers: User[];
  prop1: string;
  prop2: number;
}

interface User { name: string; age: number; }
```

you could inject the store like this:

```ts
export class SmartComponent {
  constructor (private store: Store<AppState>) { }
}
```

There are a couple of ways to fetch data from the store.

#### Provide the path of the slice we’re interested in with the help of a sequence of string values

```ts
this.store.select('foo', 'fooUsers', /* ... */)
  .subscribe(console.log)
```

The `select` function is filled up with multiple overloads:

```ts
export function select<
  T,
  a extends keyof T,
  b extends keyof T[a],
  c extends keyof T[a][b],
  d extends keyof T[a][b][c],
  e extends keyof T[a][b][c][d]
>(
  key1: a,
  key2: b,
  key3: c,
  key4: d,
  key5: e
): (source$: Observable<T>) => Observable<T[a][b][c][d][e]>;
```

where `T` is the generic type parameter passed into `Store`: `export class Store<T> extends Observable<T>`. In this case, it's `AppState`. `foo` must be a key of `AppState`(the `T`), `fooUsers` must be a key of `AppState['foo']` and so forth...

Under the hood the mapping is done with the help of the `pluck` operator, which provides a declarative way to select properties from objects:

```ts
export function select<T, Props, K>(
  pathOrMapFn: ((state: T, props?: Props) => any) | string,
  propsOrPath?: Props | string,
  ...paths: string[]
) {
  return function selectOperator(source$: Observable<T>): Observable<K> {
    let mapped$: Observable<any>;
    
    if (typeof pathOrMapFn === 'string') {
      const pathSlices = [<string>propsOrPath, ...paths].filter(Boolean);
      mapped$ = source$.pipe(pluck(pathOrMapFn, ...pathSlices));
    } 
    
    /* ... */
  }
}
```

#### Provide a custom operator that will do the mapping

```ts
export function select<T, Props, K>(
  mapFn: (state: T, props: Props) => K,
  props?: Props
): (source$: Observable<T>) => Observable<K>;
```

This is similar to the previous approach, but instead of listing the properties, you provide a custom operator and optionally another argument(`props`). `props` may contain some data that is not part of the store and you can use it to alter the shape of the state.

Another great benefit of this approach is that it can be used in conjunction with custom selectors, provided by the `createSelector()` function(you find more about `createSelector` in the following section).

`createSelector` will return a `MemoizedSelector`/`MemoizedSelectorWithProps` which extends the base `Selector`.

```ts
export function createSelector(
  ...input: any[]
): MemoizedSelector<any, any> | MemoizedSelectorWithProps<any, any, any> { /* ... */ }

export interface MemoizedSelector<
  State,
  Result,
  ProjectorFn = DefaultProjectorFn<Result>
> extends Selector<State, Result> {
  release(): void;
  /* ... */
}
```

Put differently, it returns a selector(a function that accepts a state and returns something that depends on that state) or a selector with props(similar to a selector, but it can also receive some `props`).  
This is useful to know because when using a custom selector, the magic is achieved with the `map` operator:

```ts
export function select<T, Props, K>(
  pathOrMapFn: ((state: T, props?: Props) => any) | string, // <- Complies with `MemoizedSelector` | `MemoizedSelectorWithProps`
  propsOrPath?: Props | string,
  ...paths: string[]
) {
  return function selectOperator(source$: Observable<T>): Observable<K> {
    let mapped$: Observable<any>;

    /* ... */

    if (typeof pathOrMapFn === 'function') {
      mapped$ = source$.pipe(
        map(source => pathOrMapFn(source, <Props>propsOrPath))
      );
    }

    /* ... */
  };
}
```

An example could look like this:

```ts
export function select<T, Props, K>(
  pathOrMapFn: ((state: T, props?: Props) => any) | string, // <- Complies with `MemoizedSelector` | `MemoizedSelectorWithProps`
  propsOrPath?: Props | string,
  ...paths: string[]
) {
  return function selectOperator(source$: Observable<T>): Observable<K> {
    let mapped$: Observable<any>;

    /* ... */

    if (typeof pathOrMapFn === 'function') {
      mapped$ = source$.pipe(
        map(source => pathOrMapFn(source, <Props>propsOrPath))
      );
    }

    /* ... */
  };
}
```

#### Use custom selectors

Sometimes you might want to have more control on the situation. In this case, we can use the `createSelector` function which can take a bunch of selectors and lastly, a projection function. The selectors will allow us to select certain slices from the store, whereas the last provided function will give the shape of the emitted value(i.e: the state object), based on the existing selectors. It will then project the value into the stream so the subscribers can consume it.

This feature is strongly based on the power of pure functions. Because selectors must be pure functions, memoization can take place, which prevents us from redoing the same task multiple times if the same arguments are provided.

A selector might look like this:

```ts
export type Selector<T, V> = (state: T) => V;
```

or it might receive some `props` object that contains data which is not part of store, but might influence the final shape of the stream's values:

```ts
export type SelectorWithProps<State, Props, Result> = (
  state: State,
  props: Props
) => Result;
```

As you can notice, there is no hint that indicates that the above selector can be memoized.

A memoized selector, which can be the result of `createSelector`, looks like this:

```ts
export interface MemoizedSelector<
  State,
  Result,
  ProjectorFn = DefaultProjectorFn<Result>
> extends Selector<State, Result> {
  release(): void;
  projector: ProjectorFn;
  setResult: (result?: Result) => void;
  clearResult: () => void;
}

export type DefaultProjectorFn<T> = (...args: any[]) => T;
```

*   projector is just the projection function mentioned before, it computes the shape of the data based on the selectors
*   `release()` - release the memozied value from memory

There is also `MemoizedSelectorWithProps<State, Props, Result>` which simply extends `SelectorWithProps`, but has the same methods as `MemoizedSelector`.

```ts
export function createSelector(
  ...input: any[]
): MemoizedSelector<any, any> | MemoizedSelectorWithProps<any, any, any> {
  return createSelectorFactory(defaultMemoize)(...input);
}
```

`defaultMemoize` will take a projection function and will provide a way to memoize it:

```ts
export function defaultMemoize(
  projectionFn: AnyFn,
  isArgumentsEqual = isEqualCheck,
  isResultEqual = isEqualCheck
): MemoizedProjection {
  let lastArguments: null | IArguments = null;
  let lastResult: any = null;
  let overrideResult: any;

  // Release value from memory 
  function reset() {
    lastArguments = null;
    lastResult = null;
  }

  function setResult(result: any = undefined) { overrideResult = { result }; }

  function clearResult() { overrideResult = undefined; }

  function memoized(): any {
    if (overrideResult !== undefined) {
      return overrideResult.result;
    }

    // First time the function is invoked
    if (!lastArguments) {
      // Call the projection function with the provided arguments
      lastResult = projectionFn.apply(null, arguments as any);
      lastArguments = arguments;
      return lastResult;
    }

    // If the arguments are not different than the previous ones
    // there is no need to re-compute the results
    if (!isArgumentsChanged(arguments, lastArguments, isArgumentsEqual)) {
      return lastResult;
    }

    // If we reached this point, it means the arguments were different
    // which requires a new computation of the result
    const newResult = projectionFn.apply(null, arguments as any);
    lastArguments = arguments;

    if (isResultEqual(lastResult, newResult)) {
      return lastResult;
    }

    lastResult = newResult;

    return newResult;
  }

  return { memoized, reset, setResult, clearResult };
}
```

The memoization happens in the `memoized` function. It is deliberately declared as a function declaration in order to gain access to the `arguments` special variable. Arrow functions don't have it!

Consider this example:

```ts
function isEqualCheck(a: any, b: any): boolean {
  return a === b;
}

function sum (a, b) { return a + b; };

const memoizedSum = defaultMemoize(sum, isEqualCheck, isEqualCheck);

/* 
  `sum` is executed

  if (!lastArguments) { // <-- `lastArguments = null`
    // Call the projection function with the provided arguments
    lastResult = projectionFn.apply(null, arguments as any);
    lastArguments = arguments;
    return lastResult;
  }
*/
memoizedSum.memoized(1, 3);

/*
 `sum` will not be executed again as it would be called with the same parameters

 if (!isArgumentsChanged(arguments, lastArguments, isArgumentsEqual)) {
    return lastResult;
  }
*/
memoizedSum.memoized(1, 3);
```

`defaultMemoize` is one of the building blocks of `createSelector` and it is where the memoization happens. However, when using `createSelector`, the memoization can occur in 2 places:

*   at state level — when the selector receives the same state

```ts
const incomingState = {
  user: {
    hobbies: [ {name: 'a', recent: true}, { name: 'b', recent: false } ],
  },
  otherProperty: 'foo',
};

const userSelector = (s: typeof incomingState) => s.user

const userRecentHobbiesSelector = createSelector(
  (u: typeof incomingState.user) => u.hobbies, // Selector
  hobbies => hobbies.filter(h => h.recent), // Projection Function
);

// Similar to `this.store.pipe(select(/* ... */))`
merge(
  of(incomingState),
  // Receiving an update sometime in the future
  of({ ...incomingState, otherProperty: 'bar' }).pipe(delay(500))
)
  .pipe(
    pluck('user'),
    select(userRecentHobbiesSelector),
  )
  .subscribe(console.log)
```

In the above example the log would be updated only once, because when the data comes the second time, `userRecentHobbiesSelector` would try to find out whether the new data is different than the previous one. If it's not, it's going to return the memoized value(the previous value). This also means that `userRecentHobbiesSelector`'s projection function will be called only once.

*   at projection function level — when the projection function is called with the same selectors.

Even though the state object might have changed due to some other updates, it does not mean that some selectors’ return values did as well.

A selector created by `createSelector` can use the memoized value when updating a slice of the store that is not relevant for the projection function of that selector.

```ts
interface User { name: string; age: number; isOk: boolean; }

interface State {
  users: User[];
  shouldShow: boolean;
  notRelevantProperty: string;
}

const usersSelector = (s: State) => s.users;

const userProjectionFn = (users: User[]) => {
  return users.filter(u => u.isOk);
};

const okUsersSelector = createSelector(
  usersSelector,
  userProjectionFn,
);

let dummyState: State = {
  shouldShow: true,
  users: [
    { name: 'a', age: 1, isOk: true },
    { name: 'b', age: 2, isOk: false },
    { name: 'c', age: 3, isOk: false },
    { name: 'd', age: 4, isOk: true },
  ],
  notRelevantProperty: 'not relevant'
};

// First time the selector is used with this state object
// The returned value will be memoized
console.log(okUsersSelector(dummyState));

// Although the `dummyState` object changed its reference
// `dummyState.users` did not, meaning that `userProjectionFn` should use the memoized value
// because `usersSelector` will return the same `users` object
dummyState = {
  ...dummyState,
  notRelevantProperty: 'not relevant - updated!',
};

console.log(okUsersSelector(dummyState));
```

This happens because you’d usually run more complex logic inside the projection function, whereas a selector should only return a property’s value(a piece of the state), which is not an expensive operation.

These features are brought together with the `createSelectorFactory`:

```ts
export function createSelector(
  ...input: any[]
): MemoizedSelector<any, any> | MemoizedSelectorWithProps<any, any, any> {
  return createSelectorFactory(defaultMemoize)(...input); // `input` - the sequence of selectors followed by the projection function
}
```

```ts
export function createSelectorFactory(
  memoize: MemoizeFn,
  options: SelectorFactoryConfig<any, any> = {
    stateFn: defaultStateFn,
  }
) {
  return function(
    ...input: any[]
  ): MemoizedSelector<any, any> | MemoizedSelectorWithProps<any, any, any> {
    let args = input;
    if (Array.isArray(args[0])) {
      const [head, ...tail] = args;
      args = [...head, ...tail];
    }

    const selectors = args.slice(0, args.length - 1);
    
    // The projection function is always the last argument provided
    const projector = args[args.length - 1];

    // `createSelector()` allows for composability
    // In `createSelector()` you can use selectors resulted from `createSelector()` as well
    const memoizedSelectors = selectors.filter(
      (selector: any) =>
        selector.release && typeof selector.release === 'function'
    );

    // Memoizing the projector
    // If the selectors's return values are not different
    // There is no need to re-run the projector function
    // which might contain expensive logic
    // In this case, `memoize === `defaultMemoize`
    const memoizedProjector = memoize(function(...selectors: any[]) {
      return projector.apply(null, selectors);
    });

    const memoizedState = defaultMemoize(function(state: any, props: any) {
      return options.stateFn.apply(null, [
        state,
        selectors,
        props,
        memoizedProjector,
      ]);
    });

    // Releasing the value from memory
    function release() {
      memoizedState.reset();
      memoizedProjector.reset();

      // Releasing the selectors that were created by `createSelector()`
      memoizedSelectors.forEach(selector => selector.release());
    }

    return Object.assign(memoizedState.memoized, {
      release,
      projector: memoizedProjector.memoized,
      setResult: memoizedState.setResult,
      clearResult: memoizedState.clearResult,
    });
  };
}
```

`options.stateFn` maps to `defaultStateFn`

```ts
if (props === undefined) {
  const args = (<Selector<any, any>[]>selectors).map(fn => fn(state));
  return memoizedProjector.memoized.apply(null, args);
}

// `props` - available in each provided selector as the second argument
const args = (<SelectorWithProps<any, any, any>[]>selectors).map(fn =>
  fn(state, props)
);
// `props` - available in the projector as well
return memoizedProjector.memoized.apply(null, [...args, props]);
```

which is where the selectors are invoked. `memoizedProjector.memoized` will make sure that if the arguments(selectors' return values) are not different than the previous ones, it will not call the projector again and will return the memoized value.  
Also, from the above snippets we can tell that the function returned from `createSelector()` and be called with 2 arguments: `state` and `props`, where `props` could be any data which does not necessarily belong to the store, but can influence the shape of the projector's output.

```ts
const incomingState = {
  user: {
    hobbies: [ {name: 'a', recent: true}, { name: 'b', recent: false } ],
  },
  otherProperty: 'foo',
};

const userSelector = (s: typeof incomingState) => s.user

const userRecentHobbiesSelector = createSelector(
  (u: typeof incomingState.user, props) => (console.log('props', props),u.hobbies),
  (hobbies, props) => hobbies.filter(h => h.recent).map(h => `${props.prefix}${h.name}${props.suffix}`),
);

const props = {
  prefix: '@@@@@',
  suffix: '______',
};

merge(
  of(incomingState),
  of({ ...incomingState, otherProperty: 'bar' }).pipe(delay(500))
)
  .pipe(
    pluck('user'),
    select(userRecentHobbiesSelector, props),
  )
  .subscribe(console.log)
```

We can tell from the above 2 snippets that `props` are available both in selectors and projection function.

`select` is the same function that is used in `Store.select`:

```ts
/* ... Inside `select` ... */
if (typeof pathOrMapFn === 'string') {
  const pathSlices = [<string>propsOrPath, ...paths].filter(Boolean);
  mapped$ = source$.pipe(pluck(pathOrMapFn, ...pathSlices));
} else if (typeof pathOrMapFn === 'function') {
  mapped$ = source$.pipe(
    map(source => pathOrMapFn(source, <Props>propsOrPath))
  );
}
```

## How does the memoization actually work?

In order to get a better understanding of how this process works, let’s have a look at its foundation:

```ts
// createSelectorFactory's returned function body: createSelector(...inputs) { return createSelectorFactory(defaultMemoize)(...input); }

let args = input;
const selectors = args.slice(0, args.length - 1);
const projector = args[args.length - 1];
const memoizedSelectors = selectors.filter(
  (selector: any) =>
    selector.release && typeof selector.release === 'function'
);

// By default, `memoize === defaultMemoize`
const memoizedProjector = memoize(function(...selectors: any[]) {
  return projector.apply(null, selectors);
});

const memoizedState = defaultMemoize(function(state: any, props: any) {
  return options.stateFn.apply(null, [
    state,
    selectors,
    props,
    memoizedProjector,
  ]);
});

function release() {
  memoizedState.reset();
  memoizedProjector.reset();

  memoizedSelectors.forEach(selector => selector.release());
}

return Object.assign(memoizedState.memoized, {
  release,
  projector: memoizedProjector.memoized,
  setResult: memoizedState.setResult,
  clearResult: memoizedState.clearResult,
});
```

It will return a function(`memoizedState.memoized`) that can be called with 2 arguments: `state` and `props`. `memoizedState.memoized` is the result of `createSelector()`.

Whenever `memoizedState.memoized` is called, it will verify if there is any difference between the current function's arguments and previous ones. If that's the case, it will call the callback function provided to `defaultMemoize`:

```ts
export function defaultMemoize(projectionFn: AnyFn, /* ... */): MemoizedProjection { /* ... */ }
export type MemoizedProjection = {
  memoized: AnyFn; // <-- Here is where the memoization happens
  reset: () => void;
  setResult: (result?: any) => void;
  clearResult: () => void;
};

function memoized(): any {
  if (overrideResult !== undefined) {
    return overrideResult.result;
  }

  if (!lastArguments) {
    lastResult = projectionFn.apply(null, arguments as any);
    lastArguments = arguments;
    return lastResult;
  }

  if (!isArgumentsChanged(arguments, lastArguments, isArgumentsEqual)) {
    return lastResult;
  }

  const newResult = projectionFn.apply(null, arguments as any);
  lastArguments = arguments;

  if (isResultEqual(lastResult, newResult)) {
    return lastResult;
  }

  lastResult = newResult;

  return newResult;
}
```

The `projectionFn` for `memoizedState` is:

```ts
// #1
function(state: any, props: any) {
  return options.stateFn.apply(null, [
    state,
    selectors,
    props,
    memoizedProjector,
  ]);
}
```

whereas for `memoizedProject` is:

```ts
// #2
function(...selectors: any[]) {
  return projector.apply(null, selectors);
}
```

Consider this example:

```ts
const state = {
  status: 'ok',
  actions: [ {name:'a1', status: 'ok'}, {name:'a2', status: 'denied'} ],
};

const actionsOfCrtStatusSelector = createSelector(
  s => s.status,
  s => s.actions,
  (status, actions) => actions.filter(a => a.status === status),
);

// `actionsOfCrtStatusSelector` = `memoizedState.memoized`
actionsOfCrtStatusSelector(state);
```

Here’s what happens after the selector is called with a `state`:

*   `actionsOfCrtStatusSelector(state)` equals to `memoizedState.memoized(state)`
*   `memoizedState.memoized` will check if the `state` argument is different than the previous one, but since it's the first call, these lines of `memoized` will be reached:

```ts
if (!lastArguments) {
  // Call the function and memoize its result
  lastResult = projectionFn.apply(null, arguments as any);
  lastArguments = arguments;
  return lastResult;
}
```

where `projectionFn` is `#1`(from above).  When invoked, it will call `options.stateFn` which looks like this:

it is where all the selectors are invoked:

*   `memoizedProjector.memoized` will be called with the selectors' results(and optionally a `props` object). since it is the first time `memoizedProjector.memoized` is invoked, it will call its projection function(`#2`):

```ts
if (!lastArguments) {
  // Call the function and memoize its result
  lastResult = projectionFn.apply(null, arguments as any);
  lastArguments = arguments;
  return lastResult;
}

// `projectionFn` from above
function(...selectors: any[]) {
  return projector.apply(null, selectors);
}

// `projector`
(status, actions) => actions.filter(a => a.status === status),
```

_Note: even though arrow functions do not have_ `_this_` _nor_ `_arguments_` _available,_ `_call()_`_,_ `_bind()_`_,_ `_apply()_` _can be used to pass arguments._

The flow, in this case, would look as follows:

```ts
memoizedProjector = memoize(/* #2 */function(...selectors: any[]) {
  return projector.apply(null, selectors);
});

memoizedState = defaultMemoize(/* #1 */function(state: any, props: any) {
  return options.stateFn.apply(null, [
    state,
    selectors,
    props,
    memoizedProjector,
  ]);
});
```

```markdown
memoizedState.memoized(state) ---compare crtArgs with prevArgs---> #1(state) -> invoke selectors with the given `state` ----selectorResults---> memoizedProjector(selectorResults) ---compare crtArgs with prevArgs---> #2(selectorResults)
```

After the first call, `memoizedState.memoized(state)` will be the result of `#2(selectorResults)`.

On subsequent calls, `memoizedState.memoized(state)` will not necessarily follow the same path.  
For example, `state` is the same object, it will stop here, since `prevArgs`(previous state) equals to `crtArgs`(current state):

```markdown
memoizedState.memoized(state) ---compare crtArgs with prevArgs---> prevArgs
```

This also justifies why we should always strive for immutability.  
Imagine you have a custom selector, which takes a `userSelector` created by `createSelector()` that depends on `feat.users`. When adding a new user to `feat.users`, if you're not creating a new reference of that array, the projection function of `userSelector` will return the memoized value, because the reference would be same.

## State

Among other traits, this is the place where the application’s information is kept.

```ts
constructor(
  actions$: ActionsSubject,
  reducer$: ReducerObservable,
  scannedActions: ScannedActionsSubject,
  @Inject(INITIAL_STATE) initialState: any
) { /* ... */ }
```

*   `actions$`: a `BehaviorSubject` that will emit every time an action is dispatched(i.e: `store.dispatch(newAction())`)
*   `reducer$`: a `BehaviorSubject` whose values are functions that, when invoked, will iterate over all the registered reducers and will execute them with the current state and the action that caused the function's invocation
*   `scannedActions`: used to inform other entities(e.g: `effects`) that some action occurred

None of the above parameters have access modifiers, which indicates that most of the logic will happen inside the `constructor`:

```ts
constructor (/* ... */) {
  super(initialState);

  const actionsOnQueue$: Observable<Action> = actions$.pipe(
    observeOn(queueScheduler)
  );
  const withLatestReducer$: Observable<
    [Action, ActionReducer<any, Action>]
  > = actionsOnQueue$.pipe(withLatestFrom(reducer$));

  const seed: StateActionPair<T> = { state: initialState };
  const stateAndAction$: Observable<{
    state: any;
    action?: Action;
  }> = withLatestReducer$.pipe(
    scan<[Action, ActionReducer<T, Action>], StateActionPair<T>>(
      reduceState,
      seed
    )
  );

  this.stateSubscription = stateAndAction$.subscribe(({ state, action }) => {
    this.next(state);
    scannedActions.next(action);
  });
}
```

This is the place where `actions` are intercepted and applied to the existing reducers. After the reducers are called with the new action, the resulted state will be sent to the consumers. In this case, it is the `Store` entity, because it acts as a middleman between the consumer(e.g: a component, a service) and the `State`(the model, where the information is stored). This can be seen from this line of `Store` class: `this.source = state$;`.

```ts
const withLatestReducer$: Observable<
    [Action, ActionReducer<any, Action>]
  > = actionsOnQueue$.pipe(withLatestFrom(reducer$));
```

Will make sure that although `actionsOnQueue$` emits, if `reducer$` didn't, no values will be pushed forwards into the stream. If both emitted, the values will be emitted only if the observable which emits again is `actionsOnQueue$`. This way, if reducers are added/removed later, each new action will be applied to the _most up to date_ reducers object.

```markdown
-A---A--A--A-----A--> actionsOnQueue$
       /  /    /
      |  /    /
------R------R------> reducer$
```

```ts
const seed: StateActionPair<T> = { state: initialState };
const stateAndAction$: Observable<{
  state: any;
  action?: Action;
}> = withLatestReducer$.pipe(
  scan<[Action, ActionReducer<T, Action>], StateActionPair<T>>(
    reduceState,
    seed
  )
);

export function reduceState<T, V extends Action = Action>(
  stateActionPair: StateActionPair<T, V> = { state: undefined },
  [action, reducer]: [V, ActionReducer<T, V>]
): StateActionPair<T, V> {
  const { state } = stateActionPair;
  return { state: reducer(state, action), action };
}
```

`reducer`, when called, will loop through the provided reducers and will call them with the existing state and with the current action. It will eventually return a new state which will be pushed forwards into the stream:

```ts
this.stateSubscription = stateAndAction$.subscribe(({ state, action }) => {
  this.next(state);
  scannedActions.next(action); // Send the action to the effects
});
```

As mentioned before, this stream is the source of the `Store` entity, which is how the data consumers can be notified of new state changes.

## Meta-reducers

Simply put, meta-reducers are functions that receive a reducer and return a reducer. Additionally, in the same way that interceptors act on an HTTP request, meta-reducers can add behavior before and after a reducer is invoked.

### Setting up meta-reducers

```ts
export class StoreModule {
  static forRoot(
    reducers,
    config: RootStoreConfig<any, any> = {}
  ): ModuleWithProviders<StoreRootModule> {
    return {
      ngModule: StoreRootModule,
      providers: [
        /* ... */
        {
          provide: USER_PROVIDED_META_REDUCERS,
          useValue: config.metaReducers ? config.metaReducers : [],
        },
        {
          provide: _RESOLVED_META_REDUCERS,
          deps: [META_REDUCERS, USER_PROVIDED_META_REDUCERS],
          useFactory: _concatMetaReducers,
        },
        {
          provide: REDUCER_FACTORY,
          deps: [_REDUCER_FACTORY, _RESOLVED_META_REDUCERS],
          useFactory: createReducerFactory,
        },
        /* ... */
      ]
    }
  }
}
```

`_RESOLVED_META_REDUCERS` when injected in `createReducerFactory`, it will be an array resulted from merging the built-in meta-reducers with the custom ones.

There are 3 built-in meta-reducers: `immutabilityCheckMetaReducer`, `serializationCheckMetaReducer` and `inNgZoneAssertMetaReducer`.

`createReducerFactory` will return a function that will be called with 2 arguments: `reducers` and `initialState`. At the beginning, when the app is barely loaded, the function will be called with the arguments provided in `StoreModule.forRoot({ reducers, }, { initialState })`. When called, it will create a chain(_sort of linked list_) of meta-reducers, whose extremity is going to be the reducer. This way, each meta-reducer can add behavior before and after the reducer's invocation.  
The reason it returns that function is that `createReducerFactory` will be called when `REDUCER_FACTORY` is injected in `ReducerManager` class. `ReducerManager` will keep reducers up to date when features are added/removed. So, for instance, when a feature comes with its reducer, `ReducerManager` will combine the existing reducer with the new one.

```ts
addReducers(reducers: { [key: string]: ActionReducer<any, any> }) {
  this.reducers = { ...this.reducers, ...reducers };
  this.updateReducers(Object.keys(reducers));
}
```

then it will re-create the chain, so that meta-reducers can be applied properly:

```ts
private updateReducers(featureKeys: string[]) {
  this.next(this.reducerFactory(this.reducers, this.initialState)); // <- re-create the chain
  this.dispatcher.next(<Action>{
    type: UPDATE,
    features: featureKeys,
  });
}
```

```ts
export function createReducerFactory<T, V extends Action = Action>(
  reducerFactory: ActionReducerFactory<T, V>,
  metaReducers?: MetaReducer<T, V>[]
): ActionReducerFactory<T, V> {
  // Setting up the `chain` - not created yet!
  if (Array.isArray(metaReducers) && metaReducers.length > 0) {
    (reducerFactory as any) = compose.apply(null, [
      ...metaReducers,
      reducerFactory,
    ]);
  }

  return (reducers: ActionReducerMap<T, V>, initialState?: InitialState<T>) => {
    const reducer = reducerFactory(reducers); // <- chain created
    return (state: T | undefined, action: V) => {
      state = state === undefined ? (initialState as T) : state;
      return reducer(state, action);
    };
  };
}
```

The gist resides in `compose`:

```ts
export function compose(...functions: any[]) {
  return function(arg: any) {
    if (functions.length === 0) {
      return arg;
    }

    const last = functions[functions.length - 1];
    const rest = functions.slice(0, -1);

    return rest.reduceRight((composed, fn) => fn(composed), last(arg));
  };
}
```

where `functions` is an array of meta-reducers followed by the function that will combine the reducers in a single reducer object and `arg` will be reducers that will have to be combined.

This could be visualized as follows:

```markdown
// m-r -> meta-reducer

const myMetaReducer = (reducer) => (state, action) => {
  /* Logic before reducer's invocation */
  
  const result = reducer(state, action); // Invoke the reducer -> will return the new state

  /* Logic after reducer's invocation */

  return result; // Return it so other meta-reducers can access the new produced state
}

rest.reduceRight((composed, fn) => fn(composed), last(arg)); // <- `last(args)` will create the reducers object

                       |
                       |
                       ⬇️

----------   reducer()    ----------   reducer()    -------------  
|        |--------------->|        |--------------->|           | 
|  m-r1  |                |  m-r2  |                |  reducer  |   <- // new state is produced
|        |<---------------|        |<---------------|           |   
----------    newState    ----------    newState    -------------     
    |
    |  // returned reducer; when called, it will in turn call the reducer received as an argument;
    |  // that argument 'points' to the previous reducer in the chain
    ⬇️
  reducer(state, action)
```

### Providing custom meta-reducers

Armed with the knowledge from the previous section, we can now explore how to use custom meta-reducers.

```ts
export class StoreModule {
  static forRoot(
    reducers,
    config: RootStoreConfig<any, any> = {}
  ): ModuleWithProviders<StoreRootModule> {
    return {
      ngModule: StoreRootModule,
      providers: [
        /* ... */
        {
          provide: USER_PROVIDED_META_REDUCERS,
          useValue: config.metaReducers ? config.metaReducers : [],
        },
        {
          provide: _RESOLVED_META_REDUCERS,
          deps: [META_REDUCERS, USER_PROVIDED_META_REDUCERS],
          useFactory: _concatMetaReducers,
        },
        /* ... */
      ]
    }
  }
}
/* ... */
export function _concatMetaReducers(
  metaReducers: MetaReducer[],
  userProvidedMetaReducers: MetaReducer[]
): MetaReducer[] {
  return metaReducers.concat(userProvidedMetaReducers);
}
```

### `config.metaReducers`

`RootStoreConfig`(from above) extends `StoreConfig`:

```ts
export interface StoreConfig<T, V extends Action = Action> {
  initialState?: InitialState<T>;
  reducerFactory?: ActionReducerFactory<T, V>;
  metaReducers?: MetaReducer<T, V>[];
}
```

Which means we can provide a custom meta-reducer like this:

```ts
StoreModule.forRoot(
  reducersMap,
  { metaReducers, }
)
```

where `metaReducers` is an array of `MetaReducer`:

```ts
const myMetaReducer: MetaReducer = (reducer: ActionReducer<any, any>) => {
  return (state, action) => {
    console.log('before', action, state);

    const result = reducer(state, action);

    console.log('after', result);

    return result;
  }
}

export const metaReducers: MetaReducer[] = [myMetaReducer];
```

### Injecting dependencies into a meta-reducer

Sometimes we might want to inject dependencies in our meta-reducers. We can take advantage of the `META_REDUCER` multi provider token.

We can inject dependencies by registering the meta-reducer as factory provider with the help of `META_REDUCER`.

For example, we can have something like this:

```ts
export const metaReducerWithDepFactory: (d: any) => MetaReducer = 
  (logger: LogService) => reducer => (state, action) => {
  console.log('meta reducer with dep!', logger, action)

  return reducer(state, action);
}
```

and we can register it this way:

```ts
{
  provide: META_REDUCERS,
  multi: true,
  useFactory: metaReducerWithDepFactory,
  deps: [LogService]
}
```

You can play around with this example [here](https://ng-run.com/edit/ufX1KYcBMOmV0sp78k7A?open=app%2Ffoo.meta-reducer.ts).

Furthermore, for a better visualization of how things are organized, you can put some breakpoints in your **ng-run** tab:

*   `foo.meta-reducer.ts`: line 5
*   `utils.ts`: line 32 -> the `combination(state, action)` function is where the combined reducers are iterated over and invoked
*   `foo.meta-reducer.ts`: line 7

## Using Features

Adding a feature module to a root module (where all the reducers reside) can be seen as adding a decoupled slice of cake back to its initial plate. The initial plate can be thought of as the root module and the slice of cake as the feature module. What this means is that there will still be a single source of truth(_the plate_) but each slice(feature module) can have its own _decorations_(meta-reducers, reducers).

### Registering feature modules

Registering a feature can be achieved with:

```ts
Store.forFeature(featureName, reducer: ActionReducerMap | ActionReducer, config)
```

where `reducer` is either an object of reducers(`ActionReducerMap`) or a function `ActionReducer`.You can register multiple feature modules at once.

Suppose you have something like this:

```ts
StoreModule.forRoot({ foo: fooReducer }),
StoreModule.forFeature('awesome-feat', { feat: featReducer }), // `reducer` - ActionReducerMap
StoreModule.forFeature('counter', counterReducer), // `reducer` - function
```

After the initialization, our store should look like this:

```ts
{
  'foo': /* ... */,
  'awesome-feat': /* ... */,
  'counter': /* ... */,
}
```

Let’s find out how that happens. It all starts in `StoreFeatureModule`, where all the provided configurations are collected:

```ts
export class StoreFeatureModule /* ... */ {
  constructor(
  @Inject(_STORE_FEATURES) private features: StoreFeature<any, any>[],
  @Inject(FEATURE_REDUCERS) private featureReducers: ActionReducerMap<any>[],
  private reducerManager: ReducerManager,
  root: StoreRootModule
  ) {
    const feats = features.map((feature, index) => { /* ... */ });

    reducerManager.addFeatures(feats);
  }
}
```

Once everything(initialState, reducers, meta-reducers) is gathered in once place(`feats` array), `ReducerManager` comes in to play. `ReducerManager.addFeatures` will sort out the features' reducers. Remember that a feature module's reducer can be either a function or an object of reducers(_functions_).

```ts
addFeatures(features: StoreFeature<any, any>[]) {
  const reducers = features.reduce(
    (
      reducerDict,
      { reducers, reducerFactory, metaReducers, initialState, key }
    ) => {
      const reducer =
        typeof reducers === 'function'
          ? createFeatureReducerFactory(metaReducers)(reducers, initialState)
          : createReducerFactory(reducerFactory, metaReducers)(
              reducers,
              initialState
            );

      reducerDict[key] = reducer;
      return reducerDict;
    },
    {} as { [key: string]: ActionReducer<any, any> }
  );

  this.addReducers(reducers);
}
```

If it is an object of reducers (`{ feat: featReducer }`), it will follow the same steps as the ones described in "How are reducers set up?" section above. More concisely, the `awesome-feat`'s reducer will be a function that accepts `state` and `action` as arguments and, when invoked, will iterate over the feature's registered reducers(in this case `feat`, which was created by `createReducer`) and will call them with the given arguments. This is actually the `combination` function:

```ts
/* ... */
return function combination(state, action) {
  state = state === undefined ? initialState : state;
  let hasChanged = false;
  const nextState: any = {};
  for (let i = 0; i < finalReducerKeys.length; i++) {
    const key = finalReducerKeys[i];
    const reducer: any = finalReducers[key];
    const previousStateForKey = state[key];
    const nextStateForKey = reducer(previousStateForKey, action);

    nextState[key] = nextStateForKey;
    hasChanged = hasChanged || nextStateForKey !== previousStateForKey;
  }
  return hasChanged ? nextState : state;
};
```

If instead the provided feature reducer is function(created by `createReducer`), it will simply invoke it with the `state` and `action` arguments. As with the other approach, the meta-reducer chain will still be created, but the way it is created it slightly different.

That's because when a single function is provided, it means it can't be something more than that, it can't be an object of reducers, so there is no need to create another function that, when called, will iterate over the object of reducers and invoke them(which is what happens when an object of reducers is provided).

```ts
export function createFeatureReducerFactory<T, V extends Action = Action>(
  metaReducers?: MetaReducer<T, V>[]
): (reducer: ActionReducer<T, V>, initialState?: T) => ActionReducer<T, V> {
  // Pretty similar to the other approach, except that here there is no `combineReducers` function
  // because the reducer is one single function
  // as opposed to an object of reducers
  const reducerFactory =
    Array.isArray(metaReducers) && metaReducers.length > 0
      ? compose<ActionReducer<T, V>>(...metaReducers)
      : (r: ActionReducer<T, V>) => r;

  return (reducer: ActionReducer<T, V>, initialState?: T) => {
    reducer = reducerFactory(reducer);

    return (state: T | undefined, action: V) => {
      state = state === undefined ? initialState : state;
      return reducer(state, action);
    };
  };
}
```

After the reducers have been created accordingly, the single source of truth(the object) will have to be updated:

```ts
addReducers(reducers: { [key: string]: ActionReducer<any, any> }) {
  this.reducers = { ...this.reducers, ...reducers };
  this.updateReducers(Object.keys(reducers));
}

updateReducers(featureKeys: string[]) {
  this.next(this.reducerFactory(this.reducers, this.initialState));
  /* ... */
}
```

`this.next(this.reducerFactory(this.reducers, this.initialState))` will make sure that whenever actions are dispatched, the reducer of each slice will be invoked(including the new slices added). This is how the store is kept update to date every time a new feature is added/removed.

**That's it, folks! Thanks for reading!**
