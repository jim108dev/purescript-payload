module Payload.Test.Unit.Trie where

import Prelude

import Data.Either (isLeft, isRight)
import Data.List (List(..), (:))
import Data.Maybe (Maybe(..))
import Data.Symbol (class IsSymbol, SProxy(..), reflectSymbol)
import Data.Tuple (Tuple(..))
import Payload.Server (pathToSegments)
import Payload.Trie (Trie(..))
import Payload.Trie as Trie
import Payload.Internal.UrlParsing (class ParseUrl, class ToSegments, Segment(Lit, Key, Multi), asSegments)
import Test.Unit (TestSuite, suite, test)
import Test.Unit.Assert as Assert

tests :: TestSuite
tests = do
  suite "(routing) Trie" do
    suite "fromFoldable" do
      test "single lit" do
        let folded = Trie.fromFoldable_ [ Tuple (Lit "users" : Nil) "getUsers" ]
        let manual = Trie { value: Nothing
                          , children: (Tuple
                              (Lit "users")
                              (Trie { value: Just "getUsers"
                                    , children: Nil })) : Nil }
        Assert.equal manual folded
      test "lit and key " do
        let folded = Trie.fromFoldable_ [ Tuple (Lit "users" : Key "id" : Nil) "getUser" ]
        let manual = Trie { value: Nothing, children:
                       (Tuple (Lit "users")
                              (Trie { value: Nothing
                                    , children:
                                      (Tuple (Key "id")
                                             (Trie { value: Just "getUser"
                                                   , children: Nil })) : Nil })) : Nil }
        Assert.equal manual folded
      test "single multi" do
        let folded = Trie.fromFoldable_ [ Tuple (Lit "GET" : Multi "all" : Nil) "getAll" ]
        let manual = Trie { value: Nothing
                          , children: (Tuple
                              (Lit "GET")
                              (Trie { value: Nothing
                                    , children: (Tuple
                                      (Multi "all")
                                      (Trie { value: Just "getAll"
                                            , children: Nil })) : Nil })) : Nil}
        Assert.equal manual folded
    suite "insert" do
      test "inserting different literals succeeds" do
        let trie = Trie.fromFoldable_ $
                   [ Tuple (Lit "GET" : Lit "products" : Lit "1" : Nil) "getProductById" ]
        Assert.assert "Expected insert to succeed"
          (isRight $ Trie.insert "getProductById2" (Lit "GET" : Lit "products" : Lit "2" : Nil) trie)
      test "inserting duplicate literals fails" do
        let trie = Trie.fromFoldable_ $
                   [ Tuple (Lit "GET" : Lit "products" : Lit "id" : Nil) "getProductById" ]
        Assert.assert "Expected insert to fail" $ isLeft
          (Trie.insert "getProductById2" (Lit "GET" : Lit "products" : Lit "id" : Nil) trie)
      test "inserting colliding keys fails" do
        let trie = Trie.fromFoldable_ $
                   [ Tuple (Lit "GET" : Lit "products" : Key "id" : Nil) "getProductById" ]
        Assert.assert "Expected insert to fail" $ isLeft $
          (Trie.insert "getProductById2" (Lit "GET" : Lit "products" : Key "productId" : Nil) trie)
      test "inserting colliding middle keys fails" do
        let trie = Trie.fromFoldable_ $
                   [ Tuple (Lit "GET" : Lit "products" : Key "id" : Lit "info" : Nil) "getProductById" ]
        Assert.assert "Expected insert to fail" $ isLeft $
          (Trie.insert "getProductById2" (Lit "GET" : Lit "products" : Key "productId" : Lit "info" : Nil) trie)
      test "inserting colliding multi matches fails" do
        let trie = Trie.fromFoldable_ $
                   [ Tuple (Lit "GET" : Lit "products" : Multi "any1" : Nil) "getProductById" ]
        Assert.assert "Expected insert to fail" $ isLeft $
          (Trie.insert "getProductById2" (Lit "GET" : Lit "products" : Multi "any2" : Nil) trie)
    suite "lookup" do
      test "nested" do
        let trie = Trie.fromFoldable_ $
                   [ Tuple (Lit "GET" : Lit "users" : Key "id" : Lit "posts" : Nil) "getUserPost"
                   , Tuple (Lit "GET" : Lit "users" : Key "id" : Nil) "getUser" ]
        Assert.equal
          ("getUserPost" : Nil)
          (Trie.lookup_ ["GET", "users", "12", "posts"] trie)
      test "multiple matches" do
        let trie = Trie.fromFoldable_ $
                   [ Tuple (Lit "GET" : Lit "users" : Key "id" : Nil) "getUserById"
                   , Tuple (Lit "GET" : Lit "users" : Lit "12" : Nil) "getSpecificUser"
                   , Tuple (Lit "GET" : Multi "any" : Nil) "getAny" ]
        Assert.equal
          ("getSpecificUser" : "getUserById" : "getAny" : Nil)
          (Trie.lookup_ ["GET", "users", "12"] trie)
      test "/" do
        let trie = Trie.fromFoldable_ $
                   [ Tuple (Lit "GET" : Nil) "getRoot"
                   , Tuple (Lit "GET" : Lit "users" : Lit "12" : Nil) "getSpecificUser"
                   , Tuple (Lit "GET" : Multi "any" : Nil) "getAny" ]
        Assert.equal
          ("getRoot" : Nil)
          (Trie.lookup_ ["GET"] trie)
      test "/products/<..multi> matches /products/12" do
        let trie = Trie.fromFoldable_ $
                   [ Tuple (Lit "GET" : Lit "products" : Key "id" : Nil) "getProduct"
                   , Tuple (Lit "GET" : Lit "products" : Lit "12" : Nil) "getSpecificProduct"
                   , Tuple (Lit "GET" : Lit "products" : Multi "any" : Nil) "getAnyAndAllProducts" ]
        Assert.equal
          ("getSpecificProduct" : "getProduct" : "getAnyAndAllProducts" : Nil)
          (Trie.lookup_ ["GET", "products", "12"] trie)
      test "/products/<..multi> does not match /products" do
        let trie = Trie.fromFoldable_ $
                   [ Tuple (Lit "GET" : Lit "products" : Nil) "allProducts"
                   , Tuple (Lit "GET" : Lit "products" : Key "id" : Nil) "getProduct"
                   , Tuple (Lit "GET" : Lit "products" : Lit "12" : Nil) "getSpecificProduct"
                   , Tuple (Lit "GET" : Lit "products" : Multi "any" : Nil) "getAnyAndAllProducts" ]
        Assert.equal
          ("allProducts" : Nil)
          (Trie.lookup_ ["GET", "products"] trie)
    suite "sorting" do
      test "sorts lit > key > multi" do
        let trie = Trie.fromFoldable_ $
                   [ Tuple (Lit "GET" : Lit "products" : Multi "any" : Nil) "getAnyAndAllProducts"
                   , Tuple (Lit "GET" : Lit "products" : Lit "12" : Nil) "getSpecificProduct"
                   , Tuple (Lit "GET" : Lit "products" : Key "id" : Nil) "getProduct" ]
        Assert.equal
          ("getSpecificProduct" : "getProduct" : "getAnyAndAllProducts" : Nil)
          (Trie.lookup_ ["GET", "products", "12"] trie)
      test "sorts lit > key > multi #2" do
        let trie = Trie.fromFoldable_ $
                   [ Tuple (Lit "GET" : Lit "products" : Nil) "getLit"
                   , Tuple (Lit "GET" : Multi "any" : Nil) "getAny"
                   , Tuple (Lit "GET" : Key "key" : Nil) "getKey" ]
        Assert.equal
          ("getLit" : "getKey" : "getAny" : Nil)
          (Trie.lookup_ ["GET", "products"] trie)
    suite "routing" do
      match (SProxy :: SProxy "/hello") "/hello" 
      noMatch (SProxy :: SProxy "/hello") "/hello/" 
  
      match (SProxy :: SProxy "/<a>") "/hello" 
      match (SProxy :: SProxy "/<a>") "/hi" 
      match (SProxy :: SProxy "/<a>") "/bobbbbbbbbbby" 
      match (SProxy :: SProxy "/<a>") "/weklsdfki" 
      noMatch (SProxy :: SProxy "/<a>") "/hello/" 
      noMatch (SProxy :: SProxy "/<a>") "/hello/asdf" 
  
      match (SProxy :: SProxy "/<a>/<b>") "/hello/" 
      match (SProxy :: SProxy "/<a>/<b>") "/hello/one" 
      match (SProxy :: SProxy "/<a>/<b>") "/hello/i" 
      noMatch (SProxy :: SProxy "/<a>/<b>") "/hello" 
      noMatch (SProxy :: SProxy "/<a>/<b>") "/hello/there/one" 
      noMatch (SProxy :: SProxy "/<a>/<b>") "/hello/there/" 
  
      match (SProxy :: SProxy "/users/<id>/posts") "/users/1/posts" 
      match (SProxy :: SProxy "/users/<id>/posts") "/users/sde9823lsdle/posts" 
      noMatch (SProxy :: SProxy "/users/<id>/posts") "/users/1/post" 
      noMatch (SProxy :: SProxy "/users/<id>/posts") "/user/1/posts" 
  
      match (SProxy :: SProxy "/users/<..rest>") "/users/1/posts" 
      match (SProxy :: SProxy "/users/<..rest>") "/users/foo/bar/baz/qux" 
      match (SProxy :: SProxy "/users/<..rest>") "/users/" 
      noMatch (SProxy :: SProxy "/users/<..rest>") "/users" 
  
      match (SProxy :: SProxy "/users/<id>/<..rest>") "/users/12/a/b/c" 
      match (SProxy :: SProxy "/users/<id>/<..rest>") "/users/12/" 
      match (SProxy :: SProxy "/users/<id>/<..rest>") "/users/asdf/a" 
      noMatch (SProxy :: SProxy "/users/<id>/<..rest>") "/users/asdf" 
  
      -- URLs should be URL-decoded before reaching the matcher
      match (SProxy :: SProxy "/hello there") "/hello there" 
      noMatch (SProxy :: SProxy "/hello there") "/hello%20there" 

match :: forall urlStr urlParts
  .  ParseUrl urlStr urlParts
  => ToSegments urlParts
  => IsSymbol urlStr
  => SProxy urlStr -> String -> TestSuite
match route reqPath = test ("✓ " <> reflectSymbol route <> " - " <> reqPath) $ do
  let lookedUp = testLookup route reqPath
  Assert.assert "Match failed, expected success" (lookedUp == ("handler" : Nil))

noMatch :: forall urlStr urlParts
  .  ParseUrl urlStr urlParts
  => ToSegments urlParts
  => IsSymbol urlStr
  => SProxy urlStr -> String -> TestSuite
noMatch route reqPath = test ("✘ " <> reflectSymbol route <> " - " <> reqPath ) $ do
  let lookedUp = testLookup route reqPath
  Assert.assert "Match succeeded, expected failure" (lookedUp == Nil)

testLookup :: forall urlStr urlParts
  .  ParseUrl urlStr urlParts
  => ToSegments urlParts
  => IsSymbol urlStr
  => SProxy urlStr -> String -> List String
testLookup route reqPath = Trie.lookup (pathToSegments reqPath) routingTrie
  where
    routeSegments = asSegments (SProxy :: SProxy urlStr)
    routingTrie = Trie.fromFoldable_ [ Tuple routeSegments "handler" ]