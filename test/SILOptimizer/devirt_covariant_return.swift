// RUN: %target-swift-frontend -Xllvm -new-mangling-for-tests -Xllvm -sil-full-demangle -O -Xllvm -disable-sil-cm-rr-cm=0  -primary-file %s -emit-sil -sil-inline-threshold 1000 -sil-verify-all | %FileCheck %s

// Make sure that we can dig all the way through the class hierarchy and
// protocol conformances with covariant return types correctly. The verifier
// should trip if we do not handle things correctly.
//
// As a side-test it also checks if all allocs can be promoted to the stack.

// CHECK-LABEL: sil hidden @_T023devirt_covariant_return6driveryyF : $@convention(thin) () -> () {
// CHECK: bb0
// CHECK: alloc_ref [stack]
// CHECK: alloc_ref [stack]
// CHECK: alloc_ref [stack]
// CHECK: function_ref @unknown1a : $@convention(thin) () -> ()
// CHECK: apply
// CHECK: function_ref @defenestrate : $@convention(thin) () -> ()
// CHECK: apply
// CHECK: function_ref @unknown2a : $@convention(thin) () -> ()
// CHECK: apply
// CHECK: apply
// CHECK: function_ref @unknown3a : $@convention(thin) () -> ()
// CHECK: apply
// CHECK: apply
// CHECK: dealloc_ref [stack]
// CHECK: dealloc_ref [stack]
// CHECK: dealloc_ref [stack]
// CHECK: tuple
// CHECK: return

@_silgen_name("unknown1a")
func unknown1a() -> ()
@_silgen_name("unknown1b")
func unknown1b() -> ()
@_silgen_name("unknown2a")
func unknown2a() -> ()
@_silgen_name("unknown2b")
func unknown2b() -> ()
@_silgen_name("unknown3a")
func unknown3a() -> ()
@_silgen_name("unknown3b")
func unknown3b() -> ()
@_silgen_name("defenestrate")
func defenestrate() -> ()

class B<T> {
  // We do not specialize typealias's correctly now.
  //typealias X = B
  func doSomething() -> B<T> {
    unknown1a()
    return self
  }

  // See comment in protocol P
  //class func doSomethingMeta() {
  //  unknown1b()
  //}

  func doSomethingElse() {
    defenestrate()
  }
}

class B2<T> : B<T> {
  // When we have covariance in protocols, change this to B2.
  // We do not specialize typealias correctly now.
  //typealias X = B
  override func doSomething() -> B2<T> {
    unknown2a()
    return self
  }

  // See comment in protocol P
  //override class func doSomethingMeta() {
  //  unknown2b()
  //}
}

class B3<T> : B2<T> {
  override func doSomething() -> B3<T> {
    unknown3a()
    return self
  }
}

func WhatShouldIDo<T>(_ b : B<T>) -> B<T> {
  b.doSomething().doSomethingElse()
  return b
}

func doSomethingWithB<T>(_ b : B<T>) {
  
}

struct S {}

func driver() -> () {
  let b = B<S>()
  let b2 = B2<S>()
  let b3 = B3<S>()

  WhatShouldIDo(b)
  WhatShouldIDo(b2)
  WhatShouldIDo(b3)
}

driver()

public class Bear {
  public init?(fail: Bool) {
    if fail { return nil }
  }

  // Check that devirtualizer can handle convenience initializers, which have covariant optional
  // return types.
  // CHECK-LABEL: sil @_T023devirt_covariant_return4BearC{{[_0-9a-zA-Z]*}}fc
  // CHECK: checked_cast_br [exact] %{{.*}} : $Bear to $PolarBear
  // CHECK: upcast %{{.*}} : $Optional<PolarBear> to $Optional<Bear>
  // CHECK: }
  public convenience init?(delegateFailure: Bool, failAfter: Bool) {
    self.init(fail: delegateFailure)
    if failAfter { return nil }
  }
}

final class PolarBear: Bear {

  override init?(fail: Bool) {
    super.init(fail: fail)
  }

  init?(chainFailure: Bool, failAfter: Bool) {
    super.init(fail: chainFailure)
    if failAfter { return nil }
  }
}




class Payload {
  let value: Int32
  init(_ n: Int32) {
    value = n
  }

  func getValue() -> Int32 {
    return value
  }
}

final class Payload1: Payload {
  override init(_ n: Int32) {
    super.init(n)
  }
}

class C {
   func doSomething() -> Payload? {
      return Payload(1)
   }
}


final class C1:C {
   // Override base method, but return a non-optional result
   override func doSomething() -> Payload {
      return Payload(2)
   }
}

final class C2:C {
   // Override base method, but return a non-optional result of a type,
   // which is derived from the expected type.
   override func doSomething() -> Payload1 {
      return Payload1(2)
   }
}

// Check that the Optional return value from doSomething
// gets properly unwrapped into a Payload object and then further
// devirtualized.
// CHECK-LABEL: sil hidden @_T023devirt_covariant_return7driver1s5Int32VAA2C1CFTf4d_n
// CHECK: integer_literal $Builtin.Int32, 2
// CHECK: struct $Int32 (%{{.*}} : $Builtin.Int32)
// CHECK-NOT: class_method
// CHECK-NOT: function_ref
// CHECK: return
func driver1(_ c: C1) -> Int32 {
  return c.doSomething().getValue()
}

// Check that the Optional return value from doSomething
// gets properly unwrapped into a Payload object and then further
// devirtualized.
// CHECK-LABEL: sil hidden @_T023devirt_covariant_return7driver3s5Int32VAA1CCFTf4g_n
// CHECK: bb{{[0-9]+}}(%{{[0-9]+}} : $C2):
// CHECK-NOT: bb{{.*}}:
// check that for C2, we convert the non-optional result into an optional and then cast.
// CHECK: enum $Optional
// CHECK-NEXT: upcast
// CHECK: return
func driver3(_ c: C) -> Int32 {
  return c.doSomething()!.getValue()
}

public class D {
  let v: Int32
  init(_ n: Int32) {
    v = n
  }
}

public class D1 : D {

  public func foo() -> D? {
    return nil
  }

  public func boo() -> Int32 {
    return foo()!.v
  }
}

let sD = D(0)

public class D2: D1 {
   // Override base method, but return a non-optional result
   override public func foo() -> D {
     return sD
   }
}

// Check that the boo call gets properly devirtualized and that
// that D2.foo() is inlined thanks to this.
// CHECK-LABEL: sil hidden @_T023devirt_covariant_return7driver2s5Int32VAA2D2CFTf4g_n
// CHECK-NOT: class_method
// CHECK: checked_cast_br [exact] %{{.*}} : $D1 to $D2
// CHECK: bb2
// CHECK: global_addr
// CHECK: load
// CHECK: ref_element_addr
// CHECK: bb3
// CHECK: class_method
// CHECK: }
func driver2(_ d: D2) -> Int32 {
  return d.boo()
}

class AA {
}

class BB : AA {
}

class CCC {
  @inline(never)
  func foo(_ b: BB) -> (AA, AA) {
    return (b, b)
  }
}

class DDD : CCC {
  @inline(never)
  override func foo(_ b: BB) -> (BB, BB) {
    return (b, b)
  }
}


class EEE : CCC {
  @inline(never)
  override func foo(_ b: BB) -> (AA, AA) {
    return (b, b)
  }
}

// Check that c.foo() is devirtualized, because the optimizer can handle the casting the return type
// correctly, i.e. it can cast (BBB, BBB) into (AAA, AAA)
// CHECK-LABEL: sil hidden @_T023devirt_covariant_return37testDevirtOfMethodReturningTupleTypesAA2AAC_ADtAA3CCCC_AA2BBC1btFTf4gg_n
// CHECK: checked_cast_br [exact] %{{.*}} : $CCC to $CCC
// CHECK: checked_cast_br [exact] %{{.*}} : $CCC to $DDD
// CHECK: checked_cast_br [exact] %{{.*}} : $CCC to $EEE
// CHECK: class_method
// CHECK: }
func testDevirtOfMethodReturningTupleTypes(_ c: CCC, b: BB) -> (AA, AA) {
  return c.foo(b)
}


class AAAA {
}

class BBBB : AAAA {
}

class CCCC {
  let a: BBBB
  var foo : (AAAA, AAAA) {
    @inline(never)
    get {
      return (a, a)
    }
  }
  init(x: BBBB) { a = x }
}

class DDDD : CCCC {
  override var foo : (BBBB, BBBB) {
    @inline(never)
    get {
      return (a, a)
    }
  }
}

// Check devirtualization of methods with optional results, where
// optional results need to be casted.
// CHECK-LABEL: sil @{{.*}}testOverridingMethodWithOptionalResult
// CHECK: checked_cast_br [exact] %{{.*}} : $F to $F
// CHECK: checked_cast_br [exact] %{{.*}} : $F to $G
// CHECK: switch_enum
// CHECK: checked_cast_br [exact] %{{.*}} : $F to $H
// CHECK: switch_enum
public func testOverridingMethodWithOptionalResult(_ f: F) -> (F?, Int)? {
  return f.foo()
}


public class F {
  @inline(never)
  public func foo() -> (F?, Int)? {
    return (F(), 1)
  }
}

public class G: F {
  @inline(never)
  override public func foo() -> (G?, Int)? {
    return (G(), 2)
  }
}

public class H: F {
  @inline(never)
  override public func foo() -> (H?, Int)? {
    return nil
  }
}
