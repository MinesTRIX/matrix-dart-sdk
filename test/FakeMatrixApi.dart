/*
 * Copyright (c) 2019 Zender & Kurtz GbR.
 *
 * Authors:
 *   Christian Pauly <krille@famedly.com>
 *   Marcel Radzio <mtrnord@famedly.com>
 *
 * This file is part of famedlysdk.
 *
 * famedlysdk is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * famedlysdk is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with famedlysdk.  If not, see <http://www.gnu.org/licenses/>.
 */

import 'package:http/testing.dart';
import 'dart:convert';
import 'dart:core';
import 'dart:math';
import 'package:http/http.dart';

class FakeMatrixApi extends MockClient {
  FakeMatrixApi()
      : super((request) async {
          // Collect data from Request
          final String action = request.url.path.split("/_matrix")[1];
          final String method = request.method;
          final dynamic data =
              method == "GET" ? request.url.queryParameters : request.body;
          var res = {};

          //print("$method request to $action with Data: $data");

          // Sync requests with timeout
          if (data is Map<String, dynamic> && data["timeout"] is String) {
            await new Future.delayed(Duration(seconds: 5));
          }

          if (request.url.origin != "https://fakeserver.notexisting")
            return Response(
                "<html><head></head><body>Not found...</body></html>", 50);

          // Call API
          if (api.containsKey(method) && api[method].containsKey(action))
            res = api[method][action](data);
          else
            res = {
              "errcode": "M_UNRECOGNIZED",
              "error": "Unrecognized request"
            };

          return Response(json.encode(res), 100);
        });

  static final Map<String, Map<String, dynamic>> api = {
    "GET": {
      "/client/versions": (var req) => {
            "versions": ["r0.0.1", "r0.1.0", "r0.2.0", "r0.3.0", "r0.4.0"],
            "unstable_features": {"m.lazy_load_members": true},
          },
      "/client/r0/login": (var req) => {
            "flows": [
              {"type": "m.login.password"}
            ]
          },
      "/client/r0/rooms/!localpart:server.abc/members": (var req) => {
            "chunk": [
              {
                "content": {
                  "membership": "join",
                  "avatar_url": "mxc://example.org/SEsfnsuifSDFSSEF",
                  "displayname": "Alice Margatroid"
                },
                "type": "m.room.member",
                "event_id": "§143273582443PhrSn:example.org",
                "room_id": "!636q39766251:example.com",
                "sender": "@example:example.org",
                "origin_server_ts": 1432735824653,
                "unsigned": {"age": 1234},
                "state_key": "@alice:example.org"
              }
            ]
          },
      "/client/r0/pushrules": (var req) => {
            "global": {
              "content": [
                {
                  "actions": [
                    "notify",
                    {"set_tweak": "sound", "value": "default"},
                    {"set_tweak": "highlight"}
                  ],
                  "default": true,
                  "enabled": true,
                  "pattern": "alice",
                  "rule_id": ".m.rule.contains_user_name"
                }
              ],
              "override": [
                {
                  "actions": ["dont_notify"],
                  "conditions": [],
                  "default": true,
                  "enabled": false,
                  "rule_id": ".m.rule.master"
                },
                {
                  "actions": ["dont_notify"],
                  "conditions": [
                    {
                      "key": "content.msgtype",
                      "kind": "event_match",
                      "pattern": "m.notice"
                    }
                  ],
                  "default": true,
                  "enabled": true,
                  "rule_id": ".m.rule.suppress_notices"
                }
              ],
              "room": [],
              "sender": [],
              "underride": [
                {
                  "actions": [
                    "notify",
                    {"set_tweak": "sound", "value": "ring"},
                    {"set_tweak": "highlight", "value": false}
                  ],
                  "conditions": [
                    {
                      "key": "type",
                      "kind": "event_match",
                      "pattern": "m.call.invite"
                    }
                  ],
                  "default": true,
                  "enabled": true,
                  "rule_id": ".m.rule.call"
                },
                {
                  "actions": [
                    "notify",
                    {"set_tweak": "sound", "value": "default"},
                    {"set_tweak": "highlight"}
                  ],
                  "conditions": [
                    {"kind": "contains_display_name"}
                  ],
                  "default": true,
                  "enabled": true,
                  "rule_id": ".m.rule.contains_display_name"
                },
                {
                  "actions": [
                    "notify",
                    {"set_tweak": "sound", "value": "default"},
                    {"set_tweak": "highlight", "value": false}
                  ],
                  "conditions": [
                    {"is": "2", "kind": "room_member_count"}
                  ],
                  "default": true,
                  "enabled": true,
                  "rule_id": ".m.rule.room_one_to_one"
                },
                {
                  "actions": [
                    "notify",
                    {"set_tweak": "sound", "value": "default"},
                    {"set_tweak": "highlight", "value": false}
                  ],
                  "conditions": [
                    {
                      "key": "type",
                      "kind": "event_match",
                      "pattern": "m.room.member"
                    },
                    {
                      "key": "content.membership",
                      "kind": "event_match",
                      "pattern": "invite"
                    },
                    {
                      "key": "state_key",
                      "kind": "event_match",
                      "pattern": "@alice:example.com"
                    }
                  ],
                  "default": true,
                  "enabled": true,
                  "rule_id": ".m.rule.invite_for_me"
                },
                {
                  "actions": [
                    "notify",
                    {"set_tweak": "highlight", "value": false}
                  ],
                  "conditions": [
                    {
                      "key": "type",
                      "kind": "event_match",
                      "pattern": "m.room.member"
                    }
                  ],
                  "default": true,
                  "enabled": true,
                  "rule_id": ".m.rule.member_event"
                },
                {
                  "actions": [
                    "notify",
                    {"set_tweak": "highlight", "value": false}
                  ],
                  "conditions": [
                    {
                      "key": "type",
                      "kind": "event_match",
                      "pattern": "m.room.message"
                    }
                  ],
                  "default": true,
                  "enabled": true,
                  "rule_id": ".m.rule.message"
                }
              ]
            }
          },
      "/client/r0/sync": (var req) => {
            "next_batch": Random().nextDouble().toString(),
            "presence": {
              "events": [
                {
                  "sender": "@alice:example.com",
                  "type": "m.presence",
                  "content": {"presence": "online"}
                }
              ]
            },
            "account_data": {
              "events": [
                {
                  "type": "org.example.custom.config",
                  "content": {"custom_config_key": "custom_config_value"}
                }
              ]
            },
            "to_device": {
              "events": [
                {
                  "sender": "@alice:example.com",
                  "type": "m.new_device",
                  "content": {
                    "device_id": "XYZABCDE",
                    "rooms": ["!726s6s6q:example.com"]
                  }
                }
              ]
            },
            "rooms": {
              "join": {
                "!726s6s6q:example.com": {
                  "unread_notifications": {
                    "highlight_count": 2,
                    "notification_count": 2,
                  },
                  "state": {
                    "events": [
                      {
                        "sender": "@alice:example.com",
                        "type": "m.room.member",
                        "state_key": "@alice:example.com",
                        "content": {"membership": "join"},
                        "origin_server_ts": 1417731086795,
                        "event_id": "66697273743031:example.com"
                      }
                    ]
                  },
                  "timeline": {
                    "events": [
                      {
                        "sender": "@bob:example.com",
                        "type": "m.room.member",
                        "state_key": "@bob:example.com",
                        "content": {"membership": "join"},
                        "prev_content": {"membership": "invite"},
                        "origin_server_ts": 1417731086795,
                        "event_id": "7365636s6r6432:example.com"
                      },
                      {
                        "sender": "@alice:example.com",
                        "type": "m.room.message",
                        "txn_id": "1234",
                        "content": {"body": "I am a fish", "msgtype": "m.text"},
                        "origin_server_ts": 1417731086797,
                        "event_id": "74686972643033:example.com"
                      }
                    ],
                    "limited": true,
                    "prev_batch": "t34-23535_0_0"
                  },
                  "ephemeral": {
                    "events": [
                      {
                        "type": "m.typing",
                        "content": {
                          "user_ids": ["@alice:example.com"]
                        }
                      }
                    ]
                  },
                  "account_data": {
                    "events": [
                      {
                        "type": "m.tag",
                        "content": {
                          "tags": {
                            "work": {"order": 1}
                          }
                        }
                      },
                      {
                        "type": "org.example.custom.room.config",
                        "content": {"custom_config_key": "custom_config_value"}
                      }
                    ]
                  }
                }
              },
              "invite": {
                "!696r7674:example.com": {
                  "invite_state": {
                    "events": [
                      {
                        "sender": "@alice:example.com",
                        "type": "m.room.name",
                        "state_key": "",
                        "content": {"name": "My Room Name"}
                      },
                      {
                        "sender": "@alice:example.com",
                        "type": "m.room.member",
                        "state_key": "@bob:example.com",
                        "content": {"membership": "invite"}
                      }
                    ]
                  }
                }
              },
              "leave": {
                "!5345234234:example.com": {
                  "timeline": {"events": []}
                },
              },
            }
          },
    },
    "POST": {
      "/client/r0/login": (var req) => {
            "user_id": "@test:fakeServer.notExisting",
            "access_token": "abc123",
            "device_id": "GHTYAJCE"
          },
      "/client/r0/logout": (var reqI) => {},
      "/client/r0/logout/all": (var reqI) => {},
      "/client/r0/createRoom": (var reqI) => {
            "room_id": "!1234:fakeServer.notExisting",
          },
      "/client/r0/rooms/!localpart:server.abc/read_markers": (var reqI) => {},
    },
    "PUT": {},
    "DELETE": {
      "/unknown/token": (var req) => {"errcode": "M_UNKNOWN_TOKEN"},
    },
  };
}
