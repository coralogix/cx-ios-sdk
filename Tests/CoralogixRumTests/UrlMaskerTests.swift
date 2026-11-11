//
//  UrlMaskerTests.swift
//  Coralogix
//
//  The cases are the browser SDK's url-masking suite, ported so every RUM SDK masks a given URL
//  the same way.
//

import XCTest
import CoralogixInternal
@testable import Coralogix

final class UrlMaskerTests: XCTestCase {

    private let R = UrlMasker.redacted
    private let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"

    // MARK: - Masks secrets by default

    func test_masksSecretsByDefault() {
        let cases: [(String, String, String)] = [
            ("a token in the URL of an iframe a login flow loads",
             "https://users.api.example.com/v1/sessions/accounts-cookie/callback?token=\(jwt)",
             "https://users.api.example.com/v1/sessions/accounts-cookie/callback?token=\(R)"),
            ("an OAuth authorization-code callback, state included",
             "https://app.example.com/callback?code=4%2F0AX4XfWh&state=af0ifjsldkj&scope=email",
             "https://app.example.com/callback?code=\(R)&state=\(R)&scope=email"),
            ("implicit-flow tokens in the fragment",
             "https://app.example.com/cb#access_token=ya29.a0AfH6&token_type=Bearer&expires_in=3599&id_token=\(jwt)",
             "https://app.example.com/cb#access_token=\(R)&token_type=\(R)&expires_in=3599&id_token=\(R)"),
            ("a silent-login iframe: state and the OIDC nonce",
             "https://login.example.com/authorize?client_id=abc&prompt=none&state=af0ifjsl&nonce=n-0S6_WzA2Mj",
             "https://login.example.com/authorize?client_id=abc&prompt=none&state=\(R)&nonce=\(R)"),
            ("an anti-forgery token named like WordPress's _wpnonce",
             "https://site.example.com/wp-admin/post.php?post=12&action=trash&_wpnonce=a1b2c3",
             "https://site.example.com/wp-admin/post.php?post=12&action=trash&_wpnonce=\(R)"),
            ("state used as a filter too (accepted: the same rule in every SDK)",
             "https://shop.example.com/stores?state=CA&city=Miami",
             "https://shop.example.com/stores?state=\(R)&city=Miami"),
            ("the OIDC session_state",
             "https://app.example.com/cb?code=abc&session_state=xyz.123",
             "https://app.example.com/cb?code=\(R)&session_state=\(R)"),
            ("an S3 SigV4 presigned URL",
             "https://b.s3.amazonaws.com/f.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAEXAMPLE%2F20261108%2Fus-east-1%2Fs3%2Faws4_request&X-Amz-Date=20261108T000000Z&X-Amz-Expires=900&X-Amz-Security-Token=FwoGZXIvYXdz&X-Amz-Signature=abc123",
             "https://b.s3.amazonaws.com/f.pdf?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=\(R)&X-Amz-Date=20261108T000000Z&X-Amz-Expires=900&X-Amz-Security-Token=\(R)&X-Amz-Signature=\(R)"),
            ("an S3 v2 presigned URL",
             "https://b.s3.amazonaws.com/f?AWSAccessKeyId=AKIAEXAMPLE&Expires=1793918439&Signature=vjbyPxybd%2FZ",
             "https://b.s3.amazonaws.com/f?AWSAccessKeyId=\(R)&Expires=1793918439&Signature=\(R)"),
            ("an Azure SAS signature",
             "https://acct.blob.core.windows.net/c/f?sv=2022-11-02&sp=r&se=2026-11-09&sig=AbC%2Bd%3D",
             "https://acct.blob.core.windows.net/c/f?sv=2022-11-02&sp=r&se=2026-11-09&sig=\(R)"),
            ("a Google Cloud Storage signed URL",
             "https://storage.googleapis.com/b/o?X-Goog-Algorithm=GOOG4-RSA-SHA256&X-Goog-Credential=sa%40p.iam&X-Goog-Signature=9f8e",
             "https://storage.googleapis.com/b/o?X-Goog-Algorithm=GOOG4-RSA-SHA256&X-Goog-Credential=\(R)&X-Goog-Signature=\(R)"),
            ("a CloudFront signed URL",
             "https://d1.cloudfront.net/v.mp4?Expires=1793918439&Signature=abc~def&Key-Pair-Id=K2JCJMDEHXQW5F",
             "https://d1.cloudfront.net/v.mp4?Expires=1793918439&Signature=\(R)&Key-Pair-Id=K2JCJMDEHXQW5F"),
            ("a Firebase password-reset link",
             "https://app.firebaseapp.com/__/auth/action?mode=resetPassword&oobCode=ABC123&apiKey=AIzaSyEXAMPLE&lang=en",
             "https://app.firebaseapp.com/__/auth/action?mode=resetPassword&oobCode=\(R)&apiKey=\(R)&lang=en"),
            ("a JWT in the path",
             "https://app.example.com/reset-password/\(jwt)",
             "https://app.example.com/reset-password/\(R)"),
            ("a magic-link token hash",
             "https://app.example.com/auth/confirm?token_hash=pkce_abc&type=magiclink",
             "https://app.example.com/auth/confirm?token_hash=\(R)&type=magiclink"),
            ("credentials written into the URL",
             "https://admin:hunter2@internal.example.com/x",
             "https://\(R)@internal.example.com/x"),
            ("a session id rewritten into the path",
             "https://shop.example.com/cart;jsessionid=A1B2C3?item=5",
             "https://shop.example.com/cart;jsessionid=\(R)?item=5"),
            ("the query of a hash route",
             "https://app.example.com/index#/reset?token=abc&lang=en",
             "https://app.example.com/index#/reset?token=\(R)&lang=en"),
            ("every spelling of an API key",
             "https://api.example.com/v1?api_key=1&apiKey=2&x-api-key=3&format=json",
             "https://api.example.com/v1?api_key=\(R)&apiKey=\(R)&x-api-key=\(R)&format=json"),
            ("a Shopify HMAC",
             "https://app.example.com/install?hmac=abc&shop=s.myshopify.com&timestamp=1",
             "https://app.example.com/install?hmac=\(R)&shop=s.myshopify.com&timestamp=1"),
            ("a SAML response",
             "https://sp.example.com/acs?SAMLResponse=PHNhbWxwOlJlc3BvbnNl&RelayState=%2Fhome",
             "https://sp.example.com/acs?SAMLResponse=\(R)&RelayState=%2Fhome"),
            ("a CAS ticket",
             "https://app.example.com/login?ticket=ST-1-abc",
             "https://app.example.com/login?ticket=\(R)"),
            ("a password",
             "https://app.example.com/login?user=bob&password=hunter2",
             "https://app.example.com/login?user=bob&password=\(R)"),
            ("a token in an encoded return URL",
             "https://sso.example.com/login?next=%2Freset%3Ftoken%3Dabc123%26lang%3Den",
             "https://sso.example.com/login?next=%2Freset%3Ftoken%3D\(R)%26lang%3Den"),
            ("a JWT in an encoded redirect",
             "https://sso.example.com/go?to=https%3A%2F%2Fx.com%2Fcb%3Fid%3D\(jwt)",
             "https://sso.example.com/go?to=https%3A%2F%2Fx.com%2Fcb%3Fid%3D\(R)"),
            ("a whole unencoded redirect URL held by a sensitive param",
             "https://x.com/a?token=abc/def?x=1&lang=en",
             "https://x.com/a?token=\(R)&lang=en"),
            ("a bare code param, which may be a promo code (accepted false positive)",
             "https://shop.example.com/cart?code=SAVE10",
             "https://shop.example.com/cart?code=\(R)"),
            ("a token inside an unencoded redirect held by a harmless param (stricter than the browser SDK)",
             "https://a.com/cb?redirect=https://b.com/x?token=abc",
             "https://a.com/cb?redirect=https://b.com/x?token=\(R)"),
            ("a token inside an unencoded route between harmless params",
             "https://a.com/cb?a=1&next=/reset?token=abc&b=2",
             "https://a.com/cb?a=1&next=/reset?token=\(R)&b=2"),
            ("a token whose encoded name is itself percent-escaped",
             "https://sso.example.com/login?next=%2Freset%3F%74oken%3Dabc%26lang%3Den",
             "https://sso.example.com/login?next=%2Freset%3F%74oken%3D\(R)%26lang%3Den"),
            ("a JWT with an empty payload",
             "https://a.com/cb?redirect=eyJhbGciOiJIUzI1NiJ9.e30.ZRrHA1JJJW8opsbCGfG_HACGpVUMN_a9IV7pAx_Zmeo",
             "https://a.com/cb?redirect=\(R)"),
            ("the ticket's acceptance URL",
             "https://api.example.com/callback?code=abc&foo=1#access_token=xyz",
             "https://api.example.com/callback?code=\(R)&foo=1#access_token=\(R)"),
        ]
        for (name, url, expected) in cases {
            XCTAssertEqual(UrlMasker.mask(url), expected, name)
        }
    }

    // MARK: - Leaves ordinary URLs untouched

    func test_leavesOrdinaryUrlsUntouched() {
        let cases: [(String, String)] = [
            ("names that only contain a short sensitive name", "https://shop.example.com/cart?promo_code=SAVE10&zipcode=33147"),
            ("names that start like auth", "https://blog.example.com/posts?author=john&authuser=0"),
            ("a cache-busted asset", "https://cdn.example.com/app.3f9a1c.js?v=1.2.3"),
            ("a search page", "https://shop.example.com/search?q=shoes&page=2&sort=desc"),
            ("an empty fragment", "https://app.example.com/index#"),
            ("a hash route without params", "https://app.example.com/#/expenses/123"),
            ("a relative URL", "/api/v1/items?page=2"),
            ("a data URL", "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="),
            ("malformed percent-encoding", "https://x.com/a?%E0%A4%A=1&b=%ZZ"),
            ("an empty sensitive value", "https://x.com/a?token=&b=1"),
            ("a name too long to be a real one", "https://x.com/a?\(String(repeating: "token", count: 20))=1"),
            ("an empty string", ""),
            ("a screen name", "CheckoutViewController"),
        ]
        for (name, url) in cases {
            XCTAssertEqual(UrlMasker.mask(url), url, name)
        }
    }

    // MARK: - Mode

    private let modeUrl = "https://x.com/orders?code=abc&page=2&sort=date#/expenses?y=1"

    func test_mode_mask_isTheDefaultAndHidesOnlySensitiveValues() {
        let masked = "https://x.com/orders?code=\(R)&page=2&sort=date#/expenses?y=1"
        XCTAssertEqual(UrlMasker.mask(modeUrl), masked)
        XCTAssertEqual(UrlMasker.mask(modeUrl, options: UrlMaskingOptions(mode: .mask)), masked)
    }

    func test_mode_maskAll_hidesEveryValueAndKeepsNamesAndRoute() {
        XCTAssertEqual(UrlMasker.mask(modeUrl, options: UrlMaskingOptions(mode: .maskAll)),
                       "https://x.com/orders?code=\(R)&page=\(R)&sort=\(R)#/expenses?y=\(R)")
    }

    func test_mode_dropQuery_removesQueryAndFragment() {
        XCTAssertEqual(UrlMasker.mask(modeUrl, options: UrlMaskingOptions(mode: .dropQuery)),
                       "https://x.com/orders")
    }

    func test_mode_dropQuery_stillMasksPathJwtAndCredentials() {
        XCTAssertEqual(UrlMasker.mask("https://admin:pw@x.com/reset/\(jwt)?lang=en",
                                      options: UrlMaskingOptions(mode: .dropQuery)),
                       "https://\(R)@x.com/reset/\(R)")
    }

    // MARK: - Additional params

    func test_additionalParams_name_ignoresCaseAndSeparators() {
        XCTAssertEqual(UrlMasker.mask("https://x.com/a?TenantId=acme&q=1",
                                      options: UrlMaskingOptions(additionalParams: ["tenant_id"])),
                       "https://x.com/a?TenantId=\(R)&q=1")
    }

    func test_additionalParams_regex_isTestedAgainstDecodedName() throws {
        let regex = try NSRegularExpression(pattern: "^customer ")
        XCTAssertEqual(UrlMasker.mask("https://x.com/a?customer%20ref=9&q=1",
                                      options: UrlMaskingOptions(additionalParams: [.regex(regex)])),
                       "https://x.com/a?customer%20ref=\(R)&q=1")
    }

    func test_additionalParams_keepTheBuiltInRules() {
        XCTAssertEqual(UrlMasker.mask("https://api.example.com/callback?code=abc&foo=1#access_token=xyz",
                                      options: UrlMaskingOptions(additionalParams: ["foo"])),
                       "https://api.example.com/callback?code=\(R)&foo=\(R)#access_token=\(R)")
    }
    /// The README sample, so it keeps compiling.
    func test_readmeSample_masksNameAndRegexParams() throws {
        var maskedParams: [UrlMaskingOptions.Param] = ["tenant_id"]
        if let customerPattern = try? NSRegularExpression(pattern: "^customer") {
            maskedParams.append(.regex(customerPattern))
        }
        let options = UrlMaskingOptions(additionalParams: maskedParams, mode: .mask)
        XCTAssertEqual(UrlMasker.mask("https://x.com/a?tenant_id=1&customerRef=2&q=3", options: options),
                       "https://x.com/a?tenant_id=\(R)&customerRef=\(R)&q=3")
    }

    // MARK: - Unicode names

    /// Normalization works on scalars like the browser's regex does, so a combining mark or a
    /// zero-width joiner inside a name cannot hide it.
    func test_names_withCombiningMarksOrJoiners_areStillMatched() {
        XCTAssertEqual(UrlMasker.mask("https://x.com/a?t\u{200D}oken=abc&q=1"), "https://x.com/a?t\u{200D}oken=\(R)&q=1")
        XCTAssertEqual(UrlMasker.mask("https://x.com/a?SESS\u{0130}ON=abc"), "https://x.com/a?SESS\u{0130}ON=\(R)")
    }

    // MARK: - JSON fields

    func test_maskStrings_masksEveryNestedStringValue() throws {
        let json = #"[{"fileName":"https://cdn.x.com/bundle.js?sig=abc&v=2","lineNumber":3},{"functionName":"init"}]"#
        let masked = try XCTUnwrap(UrlMasker.maskStrings(inJson: json))
        let frames = try XCTUnwrap(Helper.convertJsonStringToArray(jsonString: masked))
        XCTAssertEqual(frames[0]["fileName"] as? String, "https://cdn.x.com/bundle.js?sig=\(R)&v=2")
        XCTAssertEqual(frames[0]["lineNumber"] as? Int, 3)
        XCTAssertEqual(frames[1]["functionName"] as? String, "init")
    }

    func test_maskStrings_returnsInputUnchangedWhenNothingIsSensitive() {
        let json = #"{"NSLocalizedDescription":"The request timed out."}"#
        XCTAssertEqual(UrlMasker.maskStrings(inJson: json), json)
    }

    // MARK: - Restored view name

    func test_restoredViewName_isMaskedWithCustomerOptions() {
        let keyChain = MockKeyChain()
        keyChain.storage[Keys.view.rawValue] = "/home?tenant_id=42&token=abc&tab=1"
        let viewManager = ViewManager(keyChain: keyChain)
        viewManager.applyUrlMasking(UrlMaskingOptions(additionalParams: ["tenant_id"]))
        XCTAssertEqual(viewManager.getPrevDictionary()[Keys.view.rawValue] as? String,
                       "/home?tenant_id=\(R)&token=\(R)&tab=1")
    }

    /// Each nested redirect is unwrapped by one recursive pass; past the bound the value is
    /// redacted whole instead, so a crafted URL cannot exhaust the stack.
    func test_deeplyNestedRedirects_areBoundedAndRedacted() {
        let deep = (0..<5000).reduce("https://x.com/a?token=abc") { url, _ in "https://x.com/r?next=\(url)" }
        let masked = UrlMasker.mask(deep)
        XCTAssertFalse(masked.contains("token=abc"))
        XCTAssertTrue(masked.hasSuffix("next=\(R)"))
    }

    func test_maskStrings_masksUrlKeysAndKeepsCollidingKeys() throws {
        let json = #"{"https://x.com/cb?token=a":1,"https://x.com/cb?token=b":2}"#
        let masked = try XCTUnwrap(UrlMasker.maskStrings(inJson: json))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(masked.utf8)) as? [String: Int])
        XCTAssertEqual(dict.count, 2)
        XCTAssertEqual(Set(dict.values), [1, 2])
        XCTAssertNotNil(dict["https://x.com/cb?token=\(R)"])
    }

    // MARK: - Stack frames and view names

    /// Only `fileName` is masked. Demangled Swift and Dart frames (`closure #1 in … == …`) look like
    /// fragment params, and untouched values keep their exact bytes because nothing is re-serialized.
    func test_maskStackTrace_masksOnlyFileNameAndKeepsOtherBytes() {
        let json = #"[{"functionName":"closure #1 in static MyApp.SessionToken.== infix(MyApp.SessionToken, MyApp.SessionToken) -> Swift.Bool","fileName":"https:\/\/cdn.x.com\/app.js?token=abc&v=2","lineNumber":1.1}]"#
        let masked = UrlMasker.Masker().maskStackTrace(json)
        XCTAssertEqual(masked, #"[{"functionName":"closure #1 in static MyApp.SessionToken.== infix(MyApp.SessionToken, MyApp.SessionToken) -> Swift.Bool","fileName":"https://cdn.x.com/app.js?token=[REDACTED]&v=2","lineNumber":1.1}]"#)
    }

    func test_maskStackTrace_withNothingToMask_isUnchanged() {
        let json = ##"[{"functionName":"#0 main (package:app/main.dart:10:3)","fileName":"package:app/main.dart"}]"##
        XCTAssertEqual(UrlMasker.Masker(UrlMaskingOptions(mode: .maskAll)).maskStackTrace(json), json)
    }

    func test_maskUrlOrText_dropQuery_cutsRoutesOnly() {
        let masker = UrlMasker.Masker(UrlMaskingOptions(mode: .dropQuery))
        XCTAssertEqual(masker.maskUrlOrText("Step #2"), "Step #2")
        XCTAssertEqual(masker.maskUrlOrText("/reset?token=abc&tab=1"), "/reset")
        XCTAssertEqual(masker.maskUrlOrText("app://reset#token=abc"), "app://reset")
    }

    func test_maskUrlOrText_defaultMode_stillMasksNonRouteNames() {
        XCTAssertEqual(UrlMasker.Masker().maskUrlOrText("Reset?token=abc"), "Reset?token=\(R)")
    }

    func test_maskStrings_dropQuery_keepsTextAndCutsUrls() throws {
        let json = #"{"NSLocalizedDescription":"Order #123 failed?","NSErrorFailingURLStringKey":"https://x.com/cb?token=abc"}"#
        let masked = try XCTUnwrap(UrlMasker.maskStrings(inJson: json, options: UrlMaskingOptions(mode: .dropQuery)))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(masked.utf8)) as? [String: String])
        XCTAssertEqual(dict["NSLocalizedDescription"], "Order #123 failed?")
        XCTAssertEqual(dict["NSErrorFailingURLStringKey"], "https://x.com/cb")
    }

    func test_maskUrlOrText_dropQuery_keepsProseThatMentionsAUrl() {
        let masker = UrlMasker.Masker(UrlMaskingOptions(mode: .dropQuery))
        XCTAssertEqual(masker.maskUrlOrText("Order #123 failed: see https://help.example.com"),
                       "Order #123 failed: see https://help.example.com")
        XCTAssertEqual(masker.maskUrlOrText("https://x.com/cb?token=abc"), "https://x.com/cb")
        XCTAssertEqual(masker.maskUrlOrText("my-app+v2://reset#token=abc"), "my-app+v2://reset")
    }

    func test_isUrlOrRoute() {
        XCTAssertTrue(UrlMasker.isUrlOrRoute("/reset?x=1"))
        XCTAssertTrue(UrlMasker.isUrlOrRoute("https://x.com"))
        XCTAssertFalse(UrlMasker.isUrlOrRoute("see https://x.com"))
        XCTAssertFalse(UrlMasker.isUrlOrRoute("://x.com"))
        XCTAssertFalse(UrlMasker.isUrlOrRoute("1http://x.com"))
    }
}
