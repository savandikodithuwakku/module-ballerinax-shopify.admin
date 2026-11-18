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

import ballerina/test;
import ballerina/http;

final string mockServiceUrl = "http://localhost:8080/shopify";

@test:Config {
    groups: ["mock_tests", "oauth_tests"]
}
function testOAuthHandlerFetchesToken() returns error? {
    ShopifyOAuthHandler handler = check new (
        "mock-client-id",
        "mock-client-secret",
        "read_products",
        mockServiceUrl
    );
    string token = check handler.getToken();
    test:assertTrue(token.length() > 0, "Token should not be empty");
}

@test:Config {
    groups: ["mock_tests", "oauth_tests"]
}
function testTokenIsCached() returns error? {
    ShopifyOAuthHandler handler = check new (
        "mock-client-id",
        "mock-client-secret",
        "read_products",
        mockServiceUrl
    );

    http:Client mockClient = check new ("http://localhost:8080/shopify");
    json beforeResponse = check mockClient->get("/admin/oauth/token_request_count");
    int countBefore = check beforeResponse.count;

    // First call fetches token from mock server
    string token1 = check handler.getToken();
    string token2 = check handler.getToken();
    json afterResponse = check mockClient->get("/admin/oauth/token_request_count");
    int countAfter = check afterResponse.count;

    test:assertEquals(token1, token2,
        "Token should be served from cache on second call");
    test:assertEquals(countAfter - countBefore, 1,
        "Only one network request should be made - second call uses cache");
}

@test:Config {
    groups: ["mock_tests", "oauth_tests"]
}
function testGetClientReturnsWorkingClient() returns error? {
    ShopifyAdminClient wrapper = check new (
        {
            clientId: "mock-client-id",
            clientSecret: "mock-client-secret",
            scope: "read_products"
        },
        mockServiceUrl
    );
    Client shopify = check wrapper.getClient();
    ProductsResponse products = check shopify->retrieveAListOfProducts();
    test:assertTrue(products.products !is (),
        "Products list should not be null");
}