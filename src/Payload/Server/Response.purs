-- | This module contains various helpers for returning server
-- | responses.
module Payload.Server.Response
       ( status
       , setStatus
       , updateStatus
       , setBody
       , updateBody
       , setHeaders
       , updateHeaders

       , class ToSpecResponse
       , toSpecResponse
       , class EncodeResponse
       , encodeResponse

       , continue
       , switchingProtocols
       , processing
       , ok
       , created
       , accepted
       , nonAuthoritativeInformation
       , noContent
       , resetContent
       , partialContent
       , multiStatus
       , alreadyReported
       , imUsed
       , multipleChoices
       , movedPermanently
       , found
       , seeOther
       , notModified
       , useProxy
       , temporaryRedirect
       , permanentRedirect
       , badRequest
       , unauthorized
       , paymentRequired
       , forbidden
       , notFound
       , methodNotAllowed
       , notAcceptable
       , proxyAuthenticationRequired
       , requestTimeout
       , conflict
       , gone
       , lengthRequired
       , preconditionFailed
       , payloadTooLarge
       , uriTooLong
       , unsupportedMediaType
       , rangeNotSatisfiable
       , expectationFailed
       , imATeapot
       , misdirectedRequest
       , unprocessableEntity
       , locked
       , failedDependency
       , upgradeRequired
       , preconditionRequired
       , tooManyRequests
       , requestHeaderFieldsTooLarge
       , unavailableForLegalReasons
       , internalError
       , notImplemented
       , badGateway
       , serviceUnavailable
       , gatewayTimeout
       , httpVersionNotSupported
       , variantAlsoNegotiates
       , insufficientStorage
       , loopDetected
       , notExtended
       , networkAuthenticationRequired
       ) where

import Prelude

import Control.Monad.Except (ExceptT, throwError)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype, over)
import Data.Symbol (SProxy)
import Effect.Aff (Aff)
import Node.Stream as Stream
import Payload.Headers (Headers)
import Payload.Headers as Headers
import Payload.ResponseTypes (Empty(..), Failure(..), HttpStatus, Json(..), RawResponse, Response(..), ResponseBody(..), Result)
import Payload.Server.ContentType as ContentType
import Payload.Server.Status as Status
import Payload.TypeErrors (type (<>), type (|>))
import Prim.TypeError (class Fail, Quote, Text)
import Simple.JSON as SimpleJson
import Type.Equality (class TypeEquals)
import Unsafe.Coerce (unsafeCoerce)

status :: forall a. HttpStatus -> a -> Response a
status s body = Response { status: s, headers: Headers.empty, body }

setStatus :: forall a. HttpStatus -> Response a -> Response a
setStatus s = over Response (_ { status = s })

updateStatus :: forall a. (HttpStatus -> HttpStatus) -> Response a -> Response a
updateStatus f (Response res) = Response (res { status = f res.status })

setBody :: forall a b. b -> Response a -> Response b
setBody body = over Response (_ { body = body })

updateBody :: forall a b. (a -> b) -> Response a -> Response b
updateBody f (Response res) = Response (res { body = f res.body })

setHeaders :: forall a. Headers -> Response a -> Response a
setHeaders headers = over Response (_ { headers = headers })

updateHeaders :: forall a. (Headers -> Headers) -> Response a -> Response a
updateHeaders f (Response res) = Response (res { headers = f res.headers })

-- | This type class is for converting types which are compatible with
-- | the spec into the spec type.
-- | If the spec says one type is returned from an endpoint, a handler
-- | can either return that type directly or return another type from
-- | which that type can be produced (e.g. a full response with different
-- | headers or a different status code).
class ToSpecResponse (route :: Symbol) a b where
  toSpecResponse :: SProxy route -> a -> Result (Response b)

instance toSpecResponseEitherFailureVal
  :: EncodeResponse a
  => ToSpecResponse route (Either Failure a) a where
  toSpecResponse _ (Left err) = throwError err
  toSpecResponse _ (Right res) = pure (ok res)
else instance toSpecResponseEitherFailureResponse
  :: EncodeResponse a
  => ToSpecResponse route (Either Failure (Response a)) a where
  toSpecResponse _ (Left err) = throwError err
  toSpecResponse _ (Right res) = pure res
else instance toSpecResponseEitherResponseVal
  :: EncodeResponse err
  => ToSpecResponse route (Either (Response err) a) a where
  toSpecResponse _ (Left res) = do
    raw <- encodeResponse res
    throwError (Error raw) 
  toSpecResponse _ (Right res) = pure (ok res)
else instance toSpecResponseEitherResponseResponse
  :: EncodeResponse err
  => ToSpecResponse route (Either (Response err) (Response a)) a where
  toSpecResponse _ (Left res) = do
    raw <- encodeResponse res
    throwError (Error raw) 
  toSpecResponse _ (Right res) = pure res
else instance toSpecResponseEitherValVal ::
  ( EncodeResponse a
  , EncodeResponse err
  ) => ToSpecResponse route (Either err a) a where
  toSpecResponse _ (Left res) = do
    raw <- encodeResponse (internalError res)
    throwError (Error raw) 
  toSpecResponse _ (Right res) = pure (ok res)
else instance toSpecResponseEitherValResponse ::
  ( EncodeResponse a
  , EncodeResponse err
  ) => ToSpecResponse route (Either err (Response a)) a where
  toSpecResponse _ (Left res) = do
    raw <- encodeResponse (internalError res)
    throwError (Error raw) 
  toSpecResponse _ (Right res) = pure res
else instance toSpecResponseResponse
  :: EncodeResponse a
  => ToSpecResponse route (Response a) a where
  toSpecResponse _ res = pure res
else instance toSpecResponseIdentity
  :: EncodeResponse a
  => ToSpecResponse route a a where
  toSpecResponse _ res = pure (ok res)
else instance toSpecResponseFail ::
  ( Fail (Text "Could not match or convert handler response type to spec response type."
          |> Text ""
          |> Text "           Route: " <> Text docRoute
          |> Text "Handler response: " <> Quote a
          |> Text "   Spec response: " <> Quote b
          |> Text ""
          |> Text "Specifically, no type class instance was found for"
          |> Text ""
          |> Text "ToSpecResponse docRoute"
          |> Text "               " <> Quote a
          |> Text "               " <> Quote b
          |> Text ""
         )
  ) => ToSpecResponse docRoute a b where
  toSpecResponse res = unsafeCoerce res

-- | Types that can be encoded as response bodies and appear directly
-- | in API spec definitions.
class EncodeResponse r where
  encodeResponse :: Response r -> Result RawResponse
instance encodeResponseResponseBody :: EncodeResponse ResponseBody where
  encodeResponse = pure
else instance encodeResponseRecord ::
  ( SimpleJson.WriteForeign (Record r)
  ) => EncodeResponse (Record r) where
  encodeResponse (Response r) = encodeResponse (Response $ r { body = Json r.body })
else instance encodeResponseArray ::
  ( SimpleJson.WriteForeign (Array r)
  ) => EncodeResponse (Array r) where
  encodeResponse (Response r) = encodeResponse (Response $ r { body = Json r.body })
else instance encodeResponseJson ::
  ( SimpleJson.WriteForeign r
  ) => EncodeResponse (Json r) where
  encodeResponse (Response r@{ body: Json json }) = pure $ Response $
        { status: r.status
        , headers: Headers.setIfNotDefined "content-type" ContentType.json r.headers
        , body: StringBody (SimpleJson.writeJSON json) }
else instance encodeResponseString :: EncodeResponse String where
  encodeResponse (Response r) = pure $ Response
                   { status: r.status
                   , headers: Headers.setIfNotDefined "content-type" ContentType.plain r.headers
                   , body: StringBody r.body }
else instance encodeResponseStream ::
  ( TypeEquals (Stream.Stream r) (Stream.Stream (read :: Stream.Read | r')))
  => EncodeResponse (Stream.Stream r) where
  encodeResponse (Response r) = pure $ Response
                   { status: r.status
                   , headers: Headers.setIfNotDefined "content-type" ContentType.plain r.headers
                   , body: StreamBody (unsafeCoerce r.body) }
else instance encodeResponseMaybe :: EncodeResponse a => EncodeResponse (Maybe a) where
  encodeResponse (Response { body: Nothing }) = pure $ Response
                   { status: Status.notFound
                   , headers: Headers.empty
                   , body: EmptyBody }
  encodeResponse (Response r@{ body: Just body }) = encodeResponse $ Response
                   { status: r.status
                   , headers: r.headers
                   , body }
else instance encodeResponseEmpty :: EncodeResponse Empty where
  encodeResponse (Response r) = pure $ Response
                   { status: r.status
                   , headers: r.headers
                   , body: EmptyBody }


continue :: forall a. a -> Response a
continue = status Status.continue

switchingProtocols :: forall a. a -> Response a
switchingProtocols = status Status.switchingProtocols

processing :: forall a. a -> Response a
processing = status Status.processing

ok :: forall a. a -> Response a
ok = status Status.ok

created :: forall a. a -> Response a
created = status Status.created

accepted :: forall a. a -> Response a
accepted = status Status.accepted

nonAuthoritativeInformation :: forall a. a -> Response a
nonAuthoritativeInformation = status Status.nonAuthoritativeInformation

noContent :: forall a. a -> Response a
noContent = status Status.noContent

resetContent :: forall a. a -> Response a
resetContent = status Status.resetContent

partialContent :: forall a. a -> Response a
partialContent = status Status.partialContent

multiStatus :: forall a. a -> Response a
multiStatus = status Status.multiStatus

alreadyReported :: forall a. a -> Response a
alreadyReported = status Status.alreadyReported

imUsed :: forall a. a -> Response a
imUsed = status Status.imUsed

multipleChoices :: forall a. a -> Response a
multipleChoices = status Status.multipleChoices

movedPermanently :: forall a. a -> Response a
movedPermanently = status Status.movedPermanently

found :: forall a. a -> Response a
found = status Status.found

seeOther :: forall a. a -> Response a
seeOther = status Status.seeOther

notModified :: forall a. a -> Response a
notModified = status Status.notModified

useProxy :: forall a. a -> Response a
useProxy = status Status.useProxy

temporaryRedirect :: forall a. a -> Response a
temporaryRedirect = status Status.temporaryRedirect

permanentRedirect :: forall a. a -> Response a
permanentRedirect = status Status.permanentRedirect

badRequest :: forall a. a -> Response a
badRequest = status Status.badRequest

unauthorized :: forall a. a -> Response a
unauthorized = status Status.unauthorized

paymentRequired :: forall a. a -> Response a
paymentRequired = status Status.paymentRequired

forbidden :: forall a. a -> Response a
forbidden = status Status.forbidden

notFound :: forall a. a -> Response a
notFound = status Status.notFound

methodNotAllowed :: forall a. a -> Response a
methodNotAllowed = status Status.methodNotAllowed

notAcceptable :: forall a. a -> Response a
notAcceptable = status Status.notAcceptable

proxyAuthenticationRequired :: forall a. a -> Response a
proxyAuthenticationRequired = status Status.proxyAuthenticationRequired

requestTimeout :: forall a. a -> Response a
requestTimeout = status Status.requestTimeout

conflict :: forall a. a -> Response a
conflict = status Status.conflict

gone :: forall a. a -> Response a
gone = status Status.gone

lengthRequired :: forall a. a -> Response a
lengthRequired = status Status.lengthRequired

preconditionFailed :: forall a. a -> Response a
preconditionFailed = status Status.preconditionFailed

payloadTooLarge :: forall a. a -> Response a
payloadTooLarge = status Status.payloadTooLarge

uriTooLong :: forall a. a -> Response a
uriTooLong = status Status.uriTooLong

unsupportedMediaType :: forall a. a -> Response a
unsupportedMediaType = status Status.unsupportedMediaType

rangeNotSatisfiable :: forall a. a -> Response a
rangeNotSatisfiable = status Status.rangeNotSatisfiable

expectationFailed :: forall a. a -> Response a
expectationFailed = status Status.expectationFailed

imATeapot :: forall a. a -> Response a
imATeapot = status Status.imATeapot

misdirectedRequest :: forall a. a -> Response a
misdirectedRequest = status Status.misdirectedRequest

unprocessableEntity :: forall a. a -> Response a
unprocessableEntity = status Status.unprocessableEntity

locked :: forall a. a -> Response a
locked = status Status.locked

failedDependency :: forall a. a -> Response a
failedDependency = status Status.failedDependency

upgradeRequired :: forall a. a -> Response a
upgradeRequired = status Status.upgradeRequired

preconditionRequired :: forall a. a -> Response a
preconditionRequired = status Status.preconditionRequired

tooManyRequests :: forall a. a -> Response a
tooManyRequests = status Status.tooManyRequests

requestHeaderFieldsTooLarge :: forall a. a -> Response a
requestHeaderFieldsTooLarge = status Status.requestHeaderFieldsTooLarge

unavailableForLegalReasons :: forall a. a -> Response a
unavailableForLegalReasons = status Status.unavailableForLegalReasons

internalError :: forall a. a -> Response a
internalError = status Status.internalError

notImplemented :: forall a. a -> Response a
notImplemented = status Status.notImplemented

badGateway :: forall a. a -> Response a
badGateway = status Status.badGateway

serviceUnavailable :: forall a. a -> Response a
serviceUnavailable = status Status.serviceUnavailable

gatewayTimeout :: forall a. a -> Response a
gatewayTimeout = status Status.gatewayTimeout

httpVersionNotSupported :: forall a. a -> Response a
httpVersionNotSupported = status Status.httpVersionNotSupported

variantAlsoNegotiates :: forall a. a -> Response a
variantAlsoNegotiates = status Status.variantAlsoNegotiates

insufficientStorage :: forall a. a -> Response a
insufficientStorage = status Status.insufficientStorage

loopDetected :: forall a. a -> Response a
loopDetected = status Status.loopDetected

notExtended :: forall a. a -> Response a
notExtended = status Status.notExtended

networkAuthenticationRequired :: forall a. a -> Response a
networkAuthenticationRequired = status Status.networkAuthenticationRequired