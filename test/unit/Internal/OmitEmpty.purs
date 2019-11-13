module Payload.Test.Unit.Internal.OmitEmpty where

import Prelude

import Payload.Internal.OmitEmpty (omitEmpty)
import Test.Unit (TestSuite, suite, test)
import Test.Unit.Assert as Assert

tests :: TestSuite
tests = do
  suite "OmitEmpty" do
    test "removes empty record field" do
      Assert.equal { foo: { a: "foo" } } (omitEmpty { foo: { a: "foo" }, bar: {} })
    test "removes all empty record fields" do
      Assert.equal
        { foo: { a: "foo" }, qux: { q: "q" } }
        (omitEmpty { foo1: {}, foo: { a: "foo" }, bar: {}, qux: { q: "q" } })
    test "ignores non-record fields" do
      Assert.equal { foo: "a", bar: 1 } (omitEmpty { foo: "a", bar: 1 })
