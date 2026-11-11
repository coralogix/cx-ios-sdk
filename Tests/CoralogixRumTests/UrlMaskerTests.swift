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
    /// redacted whole instead, so a crafted URL cannot exhaust the stack. Stricter than Android.
    func test_deeplyNestedRedirects_areBoundedAndRedacted() {
        let deep = (0..<5000).reduce("https://x.com/a?token=abc") { url, _ in "https://x.com/r?next=\(url)" }
        let masked = UrlMasker.mask(deep)
        XCTAssertFalse(masked.contains("token=abc"))
        XCTAssertTrue(masked.hasSuffix("next=\(R)"))
    }

    // MARK: - Stack frames, userInfo and view names

    /// Only `fileName` is masked. Demangled Swift and Dart frames (`closure #1 in … == …`) look like
    /// fragment params, and untouched values keep their exact bytes because nothing is re-serialized.
    func test_maskStackTrace_masksOnlyFileNameAndKeepsOtherBytes() {
        let json = #"[{"functionName":"closure #1 in static MyApp.SessionToken.== infix(MyApp.SessionToken, MyApp.SessionToken) -> Swift.Bool","fileName":"https:\/\/cdn.x.com\/app.js?token=abc&v=2","lineNumber":1.1}]"#
        XCTAssertEqual(UrlMasker.Masker().maskStackTrace(json),
                       #"[{"functionName":"closure #1 in static MyApp.SessionToken.== infix(MyApp.SessionToken, MyApp.SessionToken) -> Swift.Bool","fileName":"https://cdn.x.com/app.js?token=[REDACTED]&v=2","lineNumber":1.1}]"#)
    }

    func test_maskStackTrace_withNothingToMask_isUnchanged() {
        let json = ##"[{"functionName":"#0 main (package:app/main.dart:10:3)","fileName":"package:app/main.dart"}]"##
        XCTAssertEqual(UrlMasker.Masker(UrlMaskingOptions(mode: .maskAll)).maskStackTrace(json), json)
    }

    /// Strings are edited in place, keys included; prose and untouched values keep their bytes.
    func test_maskUserInfo_masksUrlsInPlace() {
        let json = #"{"a":1.1,"NSLocalizedDescription":"Order #123 failed? code=abc","NSErrorFailingURLStringKey":"https:\/\/x.com\/cb?token=abc","https://k.com/?token=k":2}"#
        XCTAssertEqual(UrlMasker.Masker().maskUserInfo(json),
                       #"{"a":1.1,"NSLocalizedDescription":"Order #123 failed? code=abc","NSErrorFailingURLStringKey":"https://x.com/cb?token=[REDACTED]","https://k.com/?token=[REDACTED]":2}"#)
    }

    func test_maskUserInfo_dropQuery_cutsOnlyUrls() {
        let json = #"{"d":"Order #123 failed: see https://x.com/help?page=2#faq now","u":"https://x.com/cb?token=abc"}"#
        XCTAssertEqual(UrlMasker.Masker(UrlMaskingOptions(mode: .dropQuery)).maskUserInfo(json),
                       #"{"d":"Order #123 failed: see https://x.com/help now","u":"https://x.com/cb"}"#)
    }

    func test_maskUserInfo_numbersKeysThatMaskAlike() throws {
        let json = #"{"https://x.com/cb?token=a":1,"https://x.com/cb?token=b":2}"#
        let masked = try XCTUnwrap(UrlMasker.Masker().maskUserInfo(json))
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(masked.utf8)) as? [String: Int])
        XCTAssertEqual(dict.count, 2)
        XCTAssertEqual(Set(dict.values), [1, 2])
        XCTAssertNotNil(dict["https://x.com/cb?token=\(R)"])
    }

    /// A value that is wholly a route is masked as one, in text fields and userInfo alike; prose
    /// that only contains a route is still left alone.
    func test_wholeValueRoutes_areMaskedInTextAndUserInfo() {
        let masker = UrlMasker.Masker()
        XCTAssertEqual(masker.maskText("/reset?token=abc"), "/reset?token=\(R)")
        XCTAssertEqual(masker.maskText("see /reset?token=abc now"), "see /reset?token=abc now")
        XCTAssertEqual(masker.maskUserInfo(#"{"u":"/callback?token=abc"}"#), #"{"u":"/callback?token=\#(R)"}"#)
        XCTAssertEqual(UrlMasker.Masker(UrlMaskingOptions(mode: .dropQuery)).maskText("/reset?token=abc&tab=1"), "/reset")
    }

    func test_maskViewName_dropQuery_cutsUrlsInsideAName() {
        let masker = UrlMasker.Masker(UrlMaskingOptions(mode: .dropQuery))
        XCTAssertEqual(masker.maskViewName("Checkout https://x.com/cb?page=2#top"), "Checkout https://x.com/cb")
        XCTAssertEqual(masker.maskViewName("Step #2"), "Step #2")
    }

    func test_maskViewName_dropQuery_cutsRoutesOnly() {
        let masker = UrlMasker.Masker(UrlMaskingOptions(mode: .dropQuery))
        XCTAssertEqual(masker.maskViewName("Step #2"), "Step #2")
        XCTAssertEqual(masker.maskViewName("/reset?token=abc&tab=1"), "/reset")
        XCTAssertEqual(masker.maskViewName("app://reset#token=abc"), "app://reset")
    }

    func test_maskViewName_defaultMode_masksNonRouteNames() {
        XCTAssertEqual(UrlMasker.Masker().maskViewName("Reset?token=abc"), "Reset?token=\(R)")
    }

    func test_isUrlOrRoute() {
        XCTAssertTrue(UrlMasker.isUrlOrRoute("/reset?x=1"))
        XCTAssertTrue(UrlMasker.isUrlOrRoute("https://x.com"))
        XCTAssertFalse(UrlMasker.isUrlOrRoute("see https://x.com"))
        XCTAssertFalse(UrlMasker.isUrlOrRoute("://x.com"))
        XCTAssertFalse(UrlMasker.isUrlOrRoute("1http://x.com"))
    }

    // MARK: - A. Rules shared with the Android SDK

    private func assertMasks(_ cases: [(String, String)], _ options: UrlMaskingOptions = UrlMaskingOptions(),
                             file: StaticString = #filePath, line: UInt = #line) {
        for (input, expected) in cases {
            XCTAssertEqual(UrlMasker.mask(input, options: options), expected, input, file: file, line: line)
        }
    }

    private func assertFast(_ input: String, _ options: UrlMaskingOptions = UrlMaskingOptions(),
                            limit: TimeInterval = 2, file: StaticString = #filePath, line: UInt = #line) -> String {
        let start = Date()
        let output = UrlMasker.mask(input, options: options)
        XCTAssertLessThan(Date().timeIntervalSince(start), limit, file: file, line: line)
        return output
    }

    func test_A1_A3_semicolonSeparatesParameters() {
        assertMasks([
            ("https://h/p?a=1;token=abc", "https://h/p?a=1;token=\(R)"),
            ("https://shop/cart?x=1;sid=abc&sort=price", "https://shop/cart?x=1;sid=\(R)&sort=price"),
            ("https://shop/cart;jsessionid=A1B2C3?item=5", "https://shop/cart;jsessionid=\(R)?item=5"),
        ])
    }

    func test_A2_htmlEscapedAmpersandSeparatesParameters() {
        assertMasks([
            ("https://h/p?state=1&amp;code=abc", "https://h/p?state=\(R)&amp;code=\(R)"),
            ("https://h/cb?a=1&amp;code=4/0AX4XfWh-rest", "https://h/cb?a=1&amp;code=\(R)"),
        ])
    }

    func test_A4_encodedParameters() {
        assertMasks([
            ("https://sso/login?next=%2Freset%3Ftoken%3Dabc123%26lang%3Den", "https://sso/login?next=%2Freset%3Ftoken%3D\(R)%26lang%3Den"),
            ("https://sso/login?next=%2Freset%3F%74oken%3Dabc%26lang%3Den", "https://sso/login?next=%2Freset%3F%74oken%3D\(R)%26lang%3Den"),
            ("https://h/p?return_to=code%3Dabc%26lang%3Den", "https://h/p?return_to=code%3D\(R)%26lang%3Den"),
            ("https://h/p?next=%2Freset%3Fuser[password]%3Dabc", "https://h/p?next=%2Freset%3Fuser[password]%3D\(R)"),
            ("https://h/?next=%2Fcb%3F~token%3Dabc", "https://h/?next=%2Fcb%3F~token%3D\(R)"),
            ("https://h/?r=%2Fcb%3Fx%3D1%26amp%3Bcode%3Dabc", "https://h/?r=%2Fcb%3Fx%3D1%26amp%3Bcode%3D\(R)"),
            ("https://h/?return_to=x%3D1%3Bcode%3Dabc", "https://h/?return_to=x%3D1%3Bcode%3D\(R)"),
        ])
    }

    func test_A4_encodedParameters_areLinear() {
        let separators = "https://h/?a=" + String(repeating: "%3F", count: 200_000)
        XCTAssertEqual(assertFast(separators), separators)
        let longValue = "https://h/x?q=a%26" + String(repeating: "b", count: 200_000)
        XCTAssertEqual(assertFast(longValue), longValue)
    }

    /// ICU overflows its backtrack stack on a possessive run inside a capture group past ~180k
    /// characters and then reports no match at all; the patterns avoid that, and anything that still
    /// overflows fails closed. Either way the secret must not come through.
    func test_longValues_areMaskedNotPassedThrough() {
        let long = String(repeating: "a", count: 200_000)
        XCTAssertEqual(assertFast("https://h/?x=\(long)&token=secret"), "https://h/?x=\(long)&token=\(R)")
        XCTAssertEqual(assertFast("https://h/p;x=\(long);token=secret"), "https://h/p;x=\(long);token=\(R)")
        XCTAssertEqual(assertFast("https://h/p?token=\(long)"), "https://h/p?token=\(R)")
        XCTAssertEqual(assertFast("https://h.example.com/x?q=a%26token%3D" + String(repeating: "b", count: 200_000)),
                       "https://h.example.com/x?q=a%26token%3D\(R)")
        XCTAssertFalse(assertFast("/go/%3Fx%3D" + String(repeating: "%41", count: 200_000) + "%26token%3Dsecret").contains("secret"))
    }

    func test_longJsonStrings_areMaskedNotPassedThrough() {
        let long = String(repeating: "a", count: 200_000)
        let json = #"{"u":"https:\/\/x.com\/cb?q="# + long + #"&token=secret"}"#
        let masked = UrlMasker.Masker().maskUserInfo(json)
        XCTAssertFalse(masked?.contains("secret") ?? false)
    }

    func test_A5_nameLimitIsMeasuredOnTheDecodedName() {
        assertMasks([("https://x.com/a?access" + String(repeating: "%5F", count: 20) + "token=abc&q=1",
                      "https://x.com/a?access" + String(repeating: "%5F", count: 20) + "token=\(R)&q=1")])
    }

    func test_A6_lenientDecoding() {
        assertMasks([("https://h/p?%74oken%=abc", "https://h/p?%74oken%=\(R)")])
    }

    func test_A7_credentials() {
        assertMasks([
            ("https://u:p@ss@host/x", "https://\(R)@host/x"),
            ("//alice:secret@cdn/app.js", "//\(R)@cdn/app.js"),
            ("https:user:pw@example.com/", "https:\(R)@example.com/"),
            ("https:///user:pw@example.com/", "https:///\(R)@example.com/"),
            (" https://user:pw@example.com/", " https://\(R)@example.com/"),
            ("https://proxy/fetch/https://user:pw@inner/x", "https://proxy/fetch/https://\(R)@inner/x"),
            (#"https:/\user:pw@host/p"#, #"https:/\\#(R)@host/p"#),
            (#"https:\/user:pw@host/p"#, #"https:\/\#(R)@host/p"#),
            (#"https:\/\/user:pw@h\/x"#, #"https:\/\/\#(R)@h\/x"#),
            (#"\/\/user:pw@h\/x"#, #"\/\/\#(R)@h\/x"#),
            ("//:pw@h/x", "//\(R)@h/x"),
        ])
    }

    func test_A7_credentials_areLinear() {
        let input = "https://h/?a=" + String(repeating: #":\:\"#, count: 100_000) + "@x"
        _ = assertFast(input)
    }

    func test_A8_jwts() {
        assertMasks([
            ("https://h/p/eyJhbGciOiJIUzI1NiJ9.e30.SIGNATUREabcdef", "https://h/p/\(R)"),
            ("https://h/p/eyJhbGciOiJIUzI1NiJ9==.eyJzdWIiOiIxMjM0NTY3ODkwIn0=.SIGxyz", "https://h/p/\(R)"),
        ])
        let run = "https://x.com/a?q=" + String(repeating: "eyJ", count: 200_000)
        XCTAssertEqual(assertFast(run), run)
    }

    func test_A9_dataAndBlobUrlsAreMasked() {
        assertMasks([
            ("data:text/plain,hi#access_token=abc", "data:text/plain,hi#access_token=\(R)"),
            ("data:text/plain,hi?token=abc", "data:text/plain,hi?token=\(R)"),
            ("data://h/?token=abc", "data://h/?token=\(R)"),
            ("blob:https://h/?token=abc", "blob:https://h/?token=\(R)"),
        ])
        let png = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        XCTAssertEqual(UrlMasker.mask(png), png)
    }

    func test_A10_precheckFiresOnEncodedSeparatorsAndAmpersand() {
        assertMasks([
            ("https://h/go/%3Ftoken%3Dabc", "https://h/go/%3Ftoken%3D\(R)"),
            ("/go/%3Ftoken%3Dabc", "/go/%3Ftoken%3D\(R)"),
            ("https://h/cb&access_token=abc", "https://h/cb&access_token=\(R)"),
        ])
    }

    func test_A11_maskAllMasksAnEmptyName_defaultDoesNot() {
        assertMasks([("https://h/p?=abc&a=1", "https://h/p?=\(R)&a=\(R)")], UrlMaskingOptions(mode: .maskAll))
        assertMasks([("https://h/p?=abc&a=1", "https://h/p?=abc&a=1")])
    }

    func test_A12_dropQueryDropsAQueryWithALineBreak() {
        assertMasks([("https://x.com/a?q=1\nfoo#b", "https://x.com/a")], UrlMaskingOptions(mode: .dropQuery))
    }

    func test_userInfo_passwordWithUnencodedAt_isMaskedWhole() {
        assertMasks([("https://u:p@host.com/a@b?x=1", "https://\(R)@host.com/a@b?x=1")])
    }

    func test_jwt_stillMaskedAfterSeparatorsAndEscapes() {
        assertMasks([
            ("https://a.com/cb?redirect=\(jwt)&x=1", "https://a.com/cb?redirect=\(R)&x=1"),
            ("https://a.com/go?to=x%3Fid%3D\(jwt)", "https://a.com/go?to=x%3Fid%3D\(R)"),
            ("https://a.com/p/session_eyJhbGciOiJIUzI1NiJ9.e30.sig", "https://a.com/p/session_\(R)"),
        ])
    }

    // MARK: - C. URLs inside free text

    private func assertText(_ cases: [(String, String)], _ options: UrlMaskingOptions = UrlMaskingOptions(),
                            file: StaticString = #filePath, line: UInt = #line) {
        for (input, expected) in cases {
            XCTAssertEqual(UrlMasker.maskUrlsInText(input, options: options), expected, input, file: file, line: line)
        }
    }

    private func assertTextFast(_ input: String, file: StaticString = #filePath, line: UInt = #line) -> String {
        let start = Date()
        let output = UrlMasker.maskUrlsInText(input)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2, file: file, line: line)
        return output
    }

    func test_C4_errorMessages() {
        assertText([
            ("ClientException: Connection closed, uri=https://api/cb?code=abc&page=2",
             "ClientException: Connection closed, uri=https://api/cb?code=\(R)&page=2"),
            ("timeout after 10000 ms? code=abc", "timeout after 10000 ms? code=abc"),
        ])
        assertText([(#"GET https://a.com/x?tenant=acme failed, redirected to "https://b.com/y#access_token=xyz""#,
                     #"GET https://a.com/x?tenant=\#(R) failed, redirected to "https://b.com/y#access_token=\#(R)""#)],
                   UrlMaskingOptions(additionalParams: ["tenant"]))
        assertText([("Failed host lookup for https://a.com/cb?code=abc&x=1 (code 7). Retry later?",
                     "Failed host lookup for https://a.com/cb (code 7). Retry later?")],
                   UrlMaskingOptions(mode: .dropQuery))
    }

    func test_C2_protocolRelativeUrls() {
        assertText([
            ("failed to load //api/reset?token=abc uri=//cdn/a.js?sig=xyz retrying",
             "failed to load //api/reset?token=\(R) uri=//cdn/a.js?sig=\(R) retrying"),
            ("[//a/r?token=abc] {//b/r?token=abc} x,//c/r?token=abc x;//d/r?token=abc x|//e/r?token=abc",
             "[//a/r?token=\(R)] {//b/r?token=\(R)} x,//c/r?token=\(R) x;//d/r?token=\(R) x|//e/r?token=\(R)"),
            ("load //[2001:db8::1]:8080/cb?code=abc failed", "load //[2001:db8::1]:8080/cb?code=\(R) failed"),
            ("path//nothttps://x/cb?token=abc", "path//nothttps://x/cb?token=\(R)"),
            ("see //:pw@h/x now", "see //\(R)@h/x now"),
            ("a // b?token=abc and path/to//x?code=abc", "a // b?token=abc and path/to//x?code=abc"),
        ])
        for prefix in ["<td>", "`", "*", "!", "->", "[GET]:", "\u{200B}", "\u{FEFF}", "x\u{0085}"] {
            assertText([("\(prefix)//h/?token=abc", "\(prefix)//h/?token=\(R)")])
        }
    }

    func test_C2_C3_jsonEscapedUrlsAndQuotes() {
        assertText([
            (#"body {"u":"https:\/\/h\/?token=abc"}"#, #"body {"u":"https:\/\/h\/?token=\#(R)"}"#),
            (#"{"u":"https:\/\/user:pw@h\/x"}"#, #"{"u":"https:\/\/\#(R)@h\/x"}"#),
            ("uri=https://h/?q=O'Brien&token=abc end", "uri=https://h/?q=O'Brien&token=\(R) end"),
            ("uri=https://u:p'pw@h/x end", "uri=https://\(R)@h/x end"),
            ("see 'https://h/?token=abc' now", "see 'https://h/?token=\(R)' now"),
        ])
    }

    func test_C3_closingBracketsStayOutside_ipv6BracketsInside() {
        assertText([("x,//api/cb?code=abc) and (see https://b/y?token=xyz]}) but //[2001:db8::1]/z?sig=abc stays whole",
                     "x,//api/cb?code=\(R)) and (see https://b/y?token=\(R)]}) but //[2001:db8::1]/z?sig=\(R) stays whole")])
    }

    func test_C_linearTime() {
        let a = String(repeating: "a", count: 200_000) + "://" + String(repeating: "b", count: 200_000)
            + String(repeating: " ://", count: 50_000)
        XCTAssertEqual(assertTextFast(a), a)
        let b = String(repeating: "/", count: 400_000) + "x" + String(repeating: "a//", count: 100_000)
        XCTAssertEqual(assertTextFast(b), b)
        let c = String(repeating: #"a\/\/"#, count: 200_000)
        XCTAssertEqual(assertTextFast(c), c)
        let d = "//h/a?token=abc" + String(repeating: ")", count: 200_000)
        XCTAssertEqual(assertTextFast(d), "//h/a?token=\(R)" + String(repeating: ")", count: 200_000))
    }
}
