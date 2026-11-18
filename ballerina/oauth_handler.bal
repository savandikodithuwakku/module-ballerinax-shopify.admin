// Copyright (c) 2026, WSO2 LLC. (http://www.wso2.com).
//
// WSO2 LLC. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied. See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerina/url;

// Holds a cached access token along with metadata needed to determine expiry.
type TokenCache record {|
    string accessToken;
    int fetchedAtEpoch;
    int expiresInSeconds;
|};

// Handles fetching and caching of Shopify access tokens using the
// OAuth 2.0 client credentials flow.
isolated class ShopifyOAuthHandler {

    private final string clientId;
    private final string clientSecret;
    private final string scope;
    private final http:Client tokenClient;
    private TokenCache? cachedToken = ();

    public isolated function init(string clientId, string clientSecret,
            string scope, string serviceUrl, ConnectionConfig config = {})
            returns error? {
        self.clientId = clientId;
        self.clientSecret = clientSecret;
        self.scope = scope;
        http:ClientConfiguration httpClientConfig = {
            httpVersion: config.httpVersion,
            http1Settings: config.http1Settings,
            http2Settings: config.http2Settings,
            timeout: config.timeout,
            forwarded: config.forwarded,
            followRedirects: config.followRedirects,
            poolConfig: config.poolConfig,
            cache: config.cache,
            compression: config.compression,
            circuitBreaker: config.circuitBreaker,
            retryConfig: config.retryConfig,
            cookieConfig: config.cookieConfig,
            responseLimits: config.responseLimits,
            secureSocket: config.secureSocket,
            proxy: config.proxy,
            socketConfig: config.socketConfig,
            validation: config.validation,
            laxDataBinding: config.laxDataBinding
        };
        self.tokenClient = check new (
            serviceUrl,
            httpClientConfig
        );
    }

    # Returns a valid access token, fetching a new one from Shopify if the
    # cached token is missing or within 5 minutes of expiry.
    #
    # + return - A valid access token string or an error
    public isolated function getToken() returns string|error {
        lock {
            TokenCache? current = self.cachedToken;
            if current is TokenCache {
                time:Utc now = time:utcNow();
                int elapsed = <int>(now[0] - current.fetchedAtEpoch);
                int remaining = current.expiresInSeconds - elapsed;
                if remaining > 300 {
                    log:printDebug("Reusing cached token. Expires in "
                        + remaining.toString() + "s");
                    return current.accessToken;
                }
                log:printInfo("Shopify token expired. Fetching a new token...");
            } else {
                log:printInfo("No token yet. Fetching initial token from Shopify...");
            }

            string cId = self.clientId;
            string cSecret = self.clientSecret;
            string cScope = self.scope;

            string encodedClientId = check url:encode(cId, "UTF-8");
            string encodedClientSecret = check url:encode(cSecret, "UTF-8");
            string encodedScope = check url:encode(cScope, "UTF-8");

            string requestBody = "client_id=" + encodedClientId
                + "&client_secret=" + encodedClientSecret
                + "&grant_type=client_credentials"
                + "&scope=" + encodedScope;

            http:Response response = check self.tokenClient->post(
                "/admin/oauth/access_token",
                requestBody,
                headers = {"Content-Type": "application/x-www-form-urlencoded"}
            );

            if response.statusCode != 200 && response.statusCode != 201 {
                string errBody = check response.getTextPayload();
                return error("Shopify token fetch failed. HTTP "
                    + response.statusCode.toString() + ": " + errBody);
            }

            json responseJson = check response.getJsonPayload();
            string newToken = check responseJson.access_token;

            int expiresIn = 86400;
            json|error expiresField = responseJson.expires_in;
            if expiresField is json && expiresField != () {
                expiresIn = check int:fromString(expiresField.toString());
            }

            time:Utc fetchedAt = time:utcNow();
            self.cachedToken = {
                accessToken: newToken,
                fetchedAtEpoch: <int>fetchedAt[0],
                expiresInSeconds: expiresIn
            };

            log:printInfo("New Shopify token fetched. Valid for "
                + expiresIn.toString() + "s");
            return newToken;
        }
    }
}