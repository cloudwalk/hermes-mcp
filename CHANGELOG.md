# Changelog

All notable changes to this project are documented in this file.

## [0.14.1](https://github.com/cloudwalk/hermes-mcp/compare/v0.14.0...v0.14.1) (2025-08-14)


### Bug Fixes

* remove the default mcp path for streamable http ([#226](https://github.com/cloudwalk/hermes-mcp/issues/226)) ([7163ce3](https://github.com/cloudwalk/hermes-mcp/commit/7163ce3dca72d24e07b3aebe0f025d0ab0f23611))

## [0.14.0](https://github.com/cloudwalk/hermes-mcp/compare/v0.13.4...v0.14.0) (2025-08-06)


### Features

* propagating opts from client.base ([#223](https://github.com/cloudwalk/hermes-mcp/issues/223)) ([c47a54b](https://github.com/cloudwalk/hermes-mcp/commit/c47a54bc8c30aee2780eefc85781d147f73d69b1))

## [0.13.4](https://github.com/cloudwalk/hermes-mcp/compare/v0.13.3...v0.13.4) (2025-08-05)


### Reverts

* revert cache impl ([#221](https://github.com/cloudwalk/hermes-mcp/issues/221)) ([cf94019](https://github.com/cloudwalk/hermes-mcp/commit/cf940196d890e39fe2f67cca43ba6821dd94bf7f))

## [0.13.3](https://github.com/cloudwalk/hermes-mcp/compare/v0.13.2...v0.13.3) (2025-08-04)


### Bug Fixes

* otp to v27.3.4.1 ([#219](https://github.com/cloudwalk/hermes-mcp/issues/219)) ([2ba5896](https://github.com/cloudwalk/hermes-mcp/commit/2ba589662115667c81b92a68a8bc2c286fdd0e40))

## [0.13.2](https://github.com/cloudwalk/hermes-mcp/compare/v0.13.1...v0.13.2) (2025-08-04)


### Bug Fixes

* just use elixir v1.19 locally ([#217](https://github.com/cloudwalk/hermes-mcp/issues/217)) ([b8963a7](https://github.com/cloudwalk/hermes-mcp/commit/b8963a744cf73b3ca05e9d961b7a6ed1d9594ea1))

## [0.13.1](https://github.com/cloudwalk/hermes-mcp/compare/v0.13.0...v0.13.1) (2025-08-04)


### Features

* add independently configurable logs ([#113](https://github.com/cloudwalk/hermes-mcp/issues/113)) ([bb0be27](https://github.com/cloudwalk/hermes-mcp/commit/bb0be2716ac41bf43814a16497b209fa55cc811b))
* add internal client/transport state inspect on cli/mix tasks ([#61](https://github.com/cloudwalk/hermes-mcp/issues/61)) ([83550ee](https://github.com/cloudwalk/hermes-mcp/commit/83550ee40a16da5b2221780cfa926fa827f33d17))
* allow customize server registry impl ([#94](https://github.com/cloudwalk/hermes-mcp/issues/94)) ([f3ac087](https://github.com/cloudwalk/hermes-mcp/commit/f3ac08749a7c361466a7a619f9782e8d8706a7b6))
* allow json schema fields on tools/prompts definition ([#99](https://github.com/cloudwalk/hermes-mcp/issues/99)) ([0345f12](https://github.com/cloudwalk/hermes-mcp/commit/0345f122484a0169645c5da07e50c2d64fd6c5f5))
* allow multiple client &lt;&gt; transport pairs ([#24](https://github.com/cloudwalk/hermes-mcp/issues/24)) ([933876d](https://github.com/cloudwalk/hermes-mcp/commit/933876d2fe01b64eb1f086f0afcf90e8043e6473))
* allow redact patterns on server assigns/data ([#190](https://github.com/cloudwalk/hermes-mcp/issues/190)) ([07af99f](https://github.com/cloudwalk/hermes-mcp/commit/07af99f9e43d2afa87bf5504437ecf21c346a1d7))
* allow sse graceful shutdown and handle sse streaming reconnection ([#25](https://github.com/cloudwalk/hermes-mcp/issues/25)) ([008725d](https://github.com/cloudwalk/hermes-mcp/commit/008725d604111d59954d583df4dae98b622779d7))
* basic client interface API ([fd3412d](https://github.com/cloudwalk/hermes-mcp/commit/fd3412da180d217f955496a467edabbffd874dce))
* batch operations on server-side ([#125](https://github.com/cloudwalk/hermes-mcp/issues/125)) ([28eea7c](https://github.com/cloudwalk/hermes-mcp/commit/28eea7cd15f72c4effccc8475e6b301b2cd9745c))
* better dsl for embedded nested fields on server components ([#199](https://github.com/cloudwalk/hermes-mcp/issues/199)) ([097f5fd](https://github.com/cloudwalk/hermes-mcp/commit/097f5fd8f788aaaa73c5e3d6699937656488886f))
* centralized state management ([#31](https://github.com/cloudwalk/hermes-mcp/issues/31)) ([76c0ab1](https://github.com/cloudwalk/hermes-mcp/commit/76c0ab1451219712fb595ebd8f86f9806e30f725))
* client request cancelation ([#35](https://github.com/cloudwalk/hermes-mcp/issues/35)) ([ace2c3b](https://github.com/cloudwalk/hermes-mcp/commit/ace2c3b356ba376222e3315ca86ca3b43dee9ef2))
* client sampling capability ([#170](https://github.com/cloudwalk/hermes-mcp/issues/170)) ([da617a6](https://github.com/cloudwalk/hermes-mcp/commit/da617a694dbeff1d363e7b671a31f484e202e685))
* client support new mcp spec ([#83](https://github.com/cloudwalk/hermes-mcp/issues/83)) ([73d14f7](https://github.com/cloudwalk/hermes-mcp/commit/73d14f77522cef0f7212230c05cdac23ee2d93e2))
* create client operation struct ([#56](https://github.com/cloudwalk/hermes-mcp/issues/56)) ([083bda6](https://github.com/cloudwalk/hermes-mcp/commit/083bda6d61922b9a840047836f4f740436a9fdd8))
* enable log disabling ([#78](https://github.com/cloudwalk/hermes-mcp/issues/78)) ([fa1453f](https://github.com/cloudwalk/hermes-mcp/commit/fa1453fee9b015c0ad7f9ac223749a9c9f1fcf6a))
* extensive guides and documentation ([b39ccca](https://github.com/cloudwalk/hermes-mcp/commit/b39ccca264d5230bd10f1526784d2c1b6672bedc))
* http/sse transport ([#7](https://github.com/cloudwalk/hermes-mcp/issues/7)) ([690a57f](https://github.com/cloudwalk/hermes-mcp/commit/690a57fb18d641b42cab9ba2c752023b3ddc9a47))
* implement termination cleanup on Hermes.Client ([#43](https://github.com/cloudwalk/hermes-mcp/issues/43)) ([d7bbf5d](https://github.com/cloudwalk/hermes-mcp/commit/d7bbf5df545554e34a0545f1e3c8f90c12002708))
* improve cli experience with help cmd and sse conn info ([#37](https://github.com/cloudwalk/hermes-mcp/issues/37)) ([0122af2](https://github.com/cloudwalk/hermes-mcp/commit/0122af286f91ab039f0bcd1f3391e17d4489f8e4))
* improve cli experience with help cmd and sse conn info ([#37](https://github.com/cloudwalk/hermes-mcp/issues/37)) ([7a9d4e7](https://github.com/cloudwalk/hermes-mcp/commit/7a9d4e7a4274bba355a7a90e94f8bd205f2eaf90))
* improve interactive mix tasks for testing mcp servers ([#34](https://github.com/cloudwalk/hermes-mcp/issues/34)) ([53779a9](https://github.com/cloudwalk/hermes-mcp/commit/53779a9da578413d5e07162c0082dfbe98c20ee8))
* improve log handling on core lib and interactive/cli ([#68](https://github.com/cloudwalk/hermes-mcp/issues/68)) ([7717f37](https://github.com/cloudwalk/hermes-mcp/commit/7717f373074fde9e4d6ee92f975207508e13ecbf))
* improve sse uri path handling ([#36](https://github.com/cloudwalk/hermes-mcp/issues/36)) ([7ed2ea8](https://github.com/cloudwalk/hermes-mcp/commit/7ed2ea86e839e913832c2603ecc238c4fbd91390))
* improve sse uri path handling ([#36](https://github.com/cloudwalk/hermes-mcp/issues/36)) ([f044d7d](https://github.com/cloudwalk/hermes-mcp/commit/f044d7d314f610ecfa14a67c39c61bb57fc2d74e))
* inject user and transport data on mcp server frame ([#106](https://github.com/cloudwalk/hermes-mcp/issues/106)) ([feb2ce3](https://github.com/cloudwalk/hermes-mcp/commit/feb2ce308e9fd0cde4118b294dd47ce64d8db18f))
* legacy sse server transport ([#102](https://github.com/cloudwalk/hermes-mcp/issues/102)) ([4a71088](https://github.com/cloudwalk/hermes-mcp/commit/4a71088713071a726bde03bf1385c3c794d2134b))
* low level genservy mcp server implementation (stdio + stremable http) ([#77](https://github.com/cloudwalk/hermes-mcp/issues/77)) ([e6606b4](https://github.com/cloudwalk/hermes-mcp/commit/e6606b4d66a2d7ddeb6c32e0041c22d4f0036ac5))
* mcp domain model ([#28](https://github.com/cloudwalk/hermes-mcp/issues/28)) ([f8c877b](https://github.com/cloudwalk/hermes-mcp/commit/f8c877bd33cc29dce7fecdf1a7843ded0d810568))
* mcp high level server components definition ([#91](https://github.com/cloudwalk/hermes-mcp/issues/91)) ([007f41d](https://github.com/cloudwalk/hermes-mcp/commit/007f41d33874fd9f1b5e340ecbe16317dc3576b7))
* mcp server handlers refactored ([#92](https://github.com/cloudwalk/hermes-mcp/issues/92)) ([e213e04](https://github.com/cloudwalk/hermes-mcp/commit/e213e046b1360b24ff9e42835cdf80f5fe2ae4fa))
* missing notifications handlers ([#129](https://github.com/cloudwalk/hermes-mcp/issues/129)) ([34d5934](https://github.com/cloudwalk/hermes-mcp/commit/34d593499fdd846f430b93b4c52ca986f345646d))
* mvp higher level mcp server definition ([#84](https://github.com/cloudwalk/hermes-mcp/issues/84)) ([a5fec1c](https://github.com/cloudwalk/hermes-mcp/commit/a5fec1c976595c3363d4eec83e0cbc382eac9207))
* new server response contents for tools/resources with annotations (2025-06-18) ([#195](https://github.com/cloudwalk/hermes-mcp/issues/195)) ([9b65308](https://github.com/cloudwalk/hermes-mcp/commit/9b653087a6ddfac399b33be2c4be54d564335c84))
* pretty print tool arguments on list_tools ([#57](https://github.com/cloudwalk/hermes-mcp/issues/57)) ([03f8781](https://github.com/cloudwalk/hermes-mcp/commit/03f87813955754fd1c748b3002f1a9227d706e57))
* progress notifications ([#26](https://github.com/cloudwalk/hermes-mcp/issues/26)) ([a3245a0](https://github.com/cloudwalk/hermes-mcp/commit/a3245a08bb63669059d483b3179744ede3b43714))
* propagating headers on requests ([#214](https://github.com/cloudwalk/hermes-mcp/issues/214)) ([a740aa4](https://github.com/cloudwalk/hermes-mcp/commit/a740aa423a09bd04ae783f89ca85378573e7e922))
* resources templates ([#193](https://github.com/cloudwalk/hermes-mcp/issues/193)) ([1457e59](https://github.com/cloudwalk/hermes-mcp/commit/1457e59f16b77ca894b07a731d69ca5f8337c42b))
* roadmap and protocol update proposal ([#53](https://github.com/cloudwalk/hermes-mcp/issues/53)) ([52cbf10](https://github.com/cloudwalk/hermes-mcp/commit/52cbf10b5215e20554c5b4811324e13356580605))
* roots/list and completion features ([#178](https://github.com/cloudwalk/hermes-mcp/issues/178)) ([d22a6bd](https://github.com/cloudwalk/hermes-mcp/commit/d22a6bdfb92189e54455c49120abc2c7fa4f8814))
* rpc and mcp specific message parsing ([#5](https://github.com/cloudwalk/hermes-mcp/issues/5)) ([531b416](https://github.com/cloudwalk/hermes-mcp/commit/531b4160cb3cf4cef4647252b0d0ebf8a56e75a6))
* runtime server components, simplified api ([#153](https://github.com/cloudwalk/hermes-mcp/issues/153)) ([8af35d6](https://github.com/cloudwalk/hermes-mcp/commit/8af35d67cd15d125e40ab9b115ff6900c3487ea5))
* server components cursor pagination ([#177](https://github.com/cloudwalk/hermes-mcp/issues/177)) ([a95eba7](https://github.com/cloudwalk/hermes-mcp/commit/a95eba7cc2ffcefca99b3961b80094bb12a3912f))
* server-side sampling capability ([#173](https://github.com/cloudwalk/hermes-mcp/issues/173)) ([c09e7f3](https://github.com/cloudwalk/hermes-mcp/commit/c09e7f3a5e95e59f5644ef12e1602b3b8621df7f))
* **sse:** support custom base and sse paths for client ([#19](https://github.com/cloudwalk/hermes-mcp/issues/19)) ([787bc2d](https://github.com/cloudwalk/hermes-mcp/commit/787bc2d0092948100df5830e2d451e56ef1126ed))
* **sse:** unit tests... ([#20](https://github.com/cloudwalk/hermes-mcp/issues/20)) ([4941fd4](https://github.com/cloudwalk/hermes-mcp/commit/4941fd4c5602364e29ea85fad47a2636f6d1ab0c))
* standard error resposne ([#32](https://github.com/cloudwalk/hermes-mcp/issues/32)) ([52602dd](https://github.com/cloudwalk/hermes-mcp/commit/52602ddeb9fe6951c3003212bad51b49a03b346a))
* stateful client interface ([#6](https://github.com/cloudwalk/hermes-mcp/issues/6)) ([6b97987](https://github.com/cloudwalk/hermes-mcp/commit/6b979878f764941508a0ef3ee47c62516bc24c3e))
* structured server-client logging support ([#27](https://github.com/cloudwalk/hermes-mcp/issues/27)) ([4e1dfa7](https://github.com/cloudwalk/hermes-mcp/commit/4e1dfa7c275d13c7068cd0c03cea7ebdd7f756cd))
* support batch operations on client side ([#101](https://github.com/cloudwalk/hermes-mcp/issues/101)) ([fadf28d](https://github.com/cloudwalk/hermes-mcp/commit/fadf28d80068f3f1e77835fd46a276338048f0bc))
* telemetry ([#54](https://github.com/cloudwalk/hermes-mcp/issues/54)) ([c52734e](https://github.com/cloudwalk/hermes-mcp/commit/c52734eef4e9e813dc5799c9fdd4488fe84cf18f))
* tools annotations ([#127](https://github.com/cloudwalk/hermes-mcp/issues/127)) ([c83e8f1](https://github.com/cloudwalk/hermes-mcp/commit/c83e8f1b0e721b1a03960ac67cdd0774337675dc))
* tools output schema feature (2025-06-18) ([#194](https://github.com/cloudwalk/hermes-mcp/issues/194)) ([8088a49](https://github.com/cloudwalk/hermes-mcp/commit/8088a49ce4463a01e899418bb9c34fce30427d3c))
* websocket transport ([#70](https://github.com/cloudwalk/hermes-mcp/issues/70)) ([cee3945](https://github.com/cloudwalk/hermes-mcp/commit/cee3945ab0cfd1ee94a5ea8a04b85a11f78f1510))


### Bug Fixes

* allow configuring server request timeout ([#182](https://github.com/cloudwalk/hermes-mcp/issues/182)) ([e79fe2f](https://github.com/cloudwalk/hermes-mcp/commit/e79fe2f003a41517a5ff5e8f6e3fb378bdc43f11))
* allow empty capabilities on incoming JSON-RPC messages ([#105](https://github.com/cloudwalk/hermes-mcp/issues/105)) ([f0ad4cf](https://github.com/cloudwalk/hermes-mcp/commit/f0ad4cf1a5a85cc8a56baed875d2d2d200bb5860)), closes [#96](https://github.com/cloudwalk/hermes-mcp/issues/96)
* allow enum specific type on json-schema ([#121](https://github.com/cloudwalk/hermes-mcp/issues/121)) ([23c9ce2](https://github.com/cloudwalk/hermes-mcp/commit/23c9ce2081ed1099ce1f3afbd9318c8a02480039)), closes [#114](https://github.com/cloudwalk/hermes-mcp/issues/114)
* allow registering a name for the client supervisor ([#117](https://github.com/cloudwalk/hermes-mcp/issues/117)) ([d356511](https://github.com/cloudwalk/hermes-mcp/commit/d356511e2fbcf47b6a85ed733671e96d800ac693))
* allow users to control external process messages ([#149](https://github.com/cloudwalk/hermes-mcp/issues/149)) ([8fef4eb](https://github.com/cloudwalk/hermes-mcp/commit/8fef4eb753f38a325a1d3a94c310e5fd1c478ede))
* client reinitialization from interactive cli ([#55](https://github.com/cloudwalk/hermes-mcp/issues/55)) ([cb6b167](https://github.com/cloudwalk/hermes-mcp/commit/cb6b16708aa95f6bae244c9f0a13b7558079bdc5))
* client should send both sse/json headers on POST requests ([#134](https://github.com/cloudwalk/hermes-mcp/issues/134)) ([e906b7f](https://github.com/cloudwalk/hermes-mcp/commit/e906b7f02bf390faecc2b6bd39aab05ef9c500b1))
* correctly allows macro-based/callback-based server implementations ([#131](https://github.com/cloudwalk/hermes-mcp/issues/131)) ([d7bfc75](https://github.com/cloudwalk/hermes-mcp/commit/d7bfc7541a8c381573f1a20ebc37d4a7dbaaa139))
* correctly encode prompt/resource ([#155](https://github.com/cloudwalk/hermes-mcp/issues/155)) ([4249b13](https://github.com/cloudwalk/hermes-mcp/commit/4249b137e43587862de2e59acba4660ac785702a))
* correctly escape quoted expressions ([#119](https://github.com/cloudwalk/hermes-mcp/issues/119)) ([0c469c5](https://github.com/cloudwalk/hermes-mcp/commit/0c469c552d8d5fd2498706b4b1f41100e8561e2f)), closes [#118](https://github.com/cloudwalk/hermes-mcp/issues/118)
* correctly handle mcp requests on phoenix apps ([#88](https://github.com/cloudwalk/hermes-mcp/issues/88)) ([09f4235](https://github.com/cloudwalk/hermes-mcp/commit/09f42359f0daac694013f0be4f6a74de2be7f4ff)), closes [#86](https://github.com/cloudwalk/hermes-mcp/issues/86)
* correctly parse dates when default values are passed ([58f6368](https://github.com/cloudwalk/hermes-mcp/commit/58f63686574e230269f847ee793d9561976653bb))
* correctly parse peri numeric contrainsts to json-schema ([#160](https://github.com/cloudwalk/hermes-mcp/issues/160)) ([808c2c0](https://github.com/cloudwalk/hermes-mcp/commit/808c2c09e490bf9a866d5575abbf08d355c8324b))
* correctly set supported versions for different transports ([#205](https://github.com/cloudwalk/hermes-mcp/issues/205)) ([30435e1](https://github.com/cloudwalk/hermes-mcp/commit/30435e1e76aeab99b30d9cbaf0ad6f7f155e85d9))
* default implementation for server handle_notification ([#135](https://github.com/cloudwalk/hermes-mcp/issues/135)) ([c958041](https://github.com/cloudwalk/hermes-mcp/commit/c9580410162c31a62190631f6702024ea3458beb))
* do not allow duplicate server components and more convenient API ([#180](https://github.com/cloudwalk/hermes-mcp/issues/180)) ([bc71df8](https://github.com/cloudwalk/hermes-mcp/commit/bc71df8f7c6fb877f19dada9b17c3eb342d32ccd))
* do not handle domain errors ([#33](https://github.com/cloudwalk/hermes-mcp/issues/33)) ([20dde00](https://github.com/cloudwalk/hermes-mcp/commit/20dde0084ab888d17994044a7d8a1a9a9e062dec))
* do not handle domain errors ([#33](https://github.com/cloudwalk/hermes-mcp/issues/33)) ([c15b260](https://github.com/cloudwalk/hermes-mcp/commit/c15b260b1b57849fea000a090f76909fc188796a))
* fixed erts version to avoid release error ([80780d2](https://github.com/cloudwalk/hermes-mcp/commit/80780d27caddf30926be777c0e8743b0bc69d28f))
* handle SSE ping and reconnect events from server ([#65](https://github.com/cloudwalk/hermes-mcp/issues/65)) ([dccdca3](https://github.com/cloudwalk/hermes-mcp/commit/dccdca3d650d115afb06b241b0304fce976c3177))
* hermes should respect mix releases startup ([#109](https://github.com/cloudwalk/hermes-mcp/issues/109)) ([f42d476](https://github.com/cloudwalk/hermes-mcp/commit/f42d476e1dc05c57479170bd58aaca9028ef1e66))
* include formatter on hex release ([#139](https://github.com/cloudwalk/hermes-mcp/issues/139)) ([d91b244](https://github.com/cloudwalk/hermes-mcp/commit/d91b244aeed4211a6653a82705b03da2247db9a3))
* include frame helpers on module-based component ([#163](https://github.com/cloudwalk/hermes-mcp/issues/163)) ([15ba2c7](https://github.com/cloudwalk/hermes-mcp/commit/15ba2c7fbdd0a776eabe028aef0350f4f52a43a8))
* interactive http tasks should accept custom headers ([#159](https://github.com/cloudwalk/hermes-mcp/issues/159)) ([c2fe91e](https://github.com/cloudwalk/hermes-mcp/commit/c2fe91eff5a701e42a636ee1a291ea51a93f7983))
* loggin should respect the logger config ([#157](https://github.com/cloudwalk/hermes-mcp/issues/157)) ([0fbf6a6](https://github.com/cloudwalk/hermes-mcp/commit/0fbf6a652ed9dd5da64716d47ece675192442ea0))
* make gun/websocket optional ([#76](https://github.com/cloudwalk/hermes-mcp/issues/76)) ([8f55057](https://github.com/cloudwalk/hermes-mcp/commit/8f550571abb42d259c8efa1622624b6304fbec7c))
* more genserver mcp server callbacks, plug based startup and documentation ([#152](https://github.com/cloudwalk/hermes-mcp/issues/152)) ([9c26b1c](https://github.com/cloudwalk/hermes-mcp/commit/9c26b1ce4d033e3c69bc872a5ed01a037ec68f59))
* nested timeout ([#71](https://github.com/cloudwalk/hermes-mcp/issues/71)) ([c7ffa71](https://github.com/cloudwalk/hermes-mcp/commit/c7ffa71d50a90d376245821f5c8b697f8a6acc1f))
* normalize transport api ([#146](https://github.com/cloudwalk/hermes-mcp/issues/146)) ([8a30a34](https://github.com/cloudwalk/hermes-mcp/commit/8a30a34c944ca4d85de622f9063a558bd495c6fc)), closes [#145](https://github.com/cloudwalk/hermes-mcp/issues/145)
* remove assign redact feature, simplify server state inspect ([#206](https://github.com/cloudwalk/hermes-mcp/issues/206)) ([a4d9ae9](https://github.com/cloudwalk/hermes-mcp/commit/a4d9ae9f0ac5abfb76649271033af75b6ac8afff))
* remove last uses of hard-coded Hermes.Server.Registry ([cc0ffd9](https://github.com/cloudwalk/hermes-mcp/commit/cc0ffd95fce771a9c861c6859124dcedb6ceb88e))
* server behaviour with optional callbacks ([#151](https://github.com/cloudwalk/hermes-mcp/issues/151)) ([91aa191](https://github.com/cloudwalk/hermes-mcp/commit/91aa1916f28da5972f6b100861a2547697c1ddb7))
* server can now send notifications correctly ([#166](https://github.com/cloudwalk/hermes-mcp/issues/166)) ([33f32de](https://github.com/cloudwalk/hermes-mcp/commit/33f32deccd42dc4591832636b2b3fad56ce40661))
* server session expiration on idle (configurable) ([#143](https://github.com/cloudwalk/hermes-mcp/issues/143)) ([d9f7164](https://github.com/cloudwalk/hermes-mcp/commit/d9f7164028b2b6e8ff3d697f888adf655110bc1f))
* sse endpoint uri merging ([#64](https://github.com/cloudwalk/hermes-mcp/issues/64)) ([2fa7869](https://github.com/cloudwalk/hermes-mcp/commit/2fa78698f69d8e4f90e5f56754e71eab4a0dc9c2))
* use mix.lock as cache key ([#58](https://github.com/cloudwalk/hermes-mcp/issues/58)) ([6a3134a](https://github.com/cloudwalk/hermes-mcp/commit/6a3134ae3288d23b333aea7e7467e6ea93a0ba11))


### Miscellaneous Chores

* add llms summary about the library ([#175](https://github.com/cloudwalk/hermes-mcp/issues/175)) ([ed0e608](https://github.com/cloudwalk/hermes-mcp/commit/ed0e60872e5b77ddb6ffff13da6c1e20b1c2d7a2))
* allow different kind of components have the same name ([#181](https://github.com/cloudwalk/hermes-mcp/issues/181)) ([d5ba6f5](https://github.com/cloudwalk/hermes-mcp/commit/d5ba6f56fb54ed07e46d37c2217dcf76c793762f))
* deprecate sse transport ([#187](https://github.com/cloudwalk/hermes-mcp/issues/187)) ([1932fbc](https://github.com/cloudwalk/hermes-mcp/commit/1932fbcdef12194c496d3ac074b17ef65fe18e49))
* **deps:** bump the npm_and_yarn group across 1 directory with 2 updates ([#198](https://github.com/cloudwalk/hermes-mcp/issues/198)) ([5e21aac](https://github.com/cloudwalk/hermes-mcp/commit/5e21aac07ab1e709cb2bad8ddf9f45ba3ff99ef9))
* readme ([bed6ff7](https://github.com/cloudwalk/hermes-mcp/commit/bed6ff78ed617af3eaba6d316c1107643e8aea06))
* release 0.10.0 ([#124](https://github.com/cloudwalk/hermes-mcp/issues/124)) ([8db7a92](https://github.com/cloudwalk/hermes-mcp/commit/8db7a927115d7071dc4e8425d89d78d357f6253e))
* release 0.10.1 ([#133](https://github.com/cloudwalk/hermes-mcp/issues/133)) ([2caf67b](https://github.com/cloudwalk/hermes-mcp/commit/2caf67bb222c27a993e44aa1609ca19754c0e260))
* release 0.10.2 ([#136](https://github.com/cloudwalk/hermes-mcp/issues/136)) ([580d96a](https://github.com/cloudwalk/hermes-mcp/commit/580d96a68c020a5560a2a631af8b8140f15d1108))
* release 0.10.3 ([#140](https://github.com/cloudwalk/hermes-mcp/issues/140)) ([2bf9890](https://github.com/cloudwalk/hermes-mcp/commit/2bf989082fa7e5c37f9ab7bc5a618cff8fe50f7d))
* release 0.10.4 ([#144](https://github.com/cloudwalk/hermes-mcp/issues/144)) ([ae22d44](https://github.com/cloudwalk/hermes-mcp/commit/ae22d4416a41bfb7c059a7b7fe6bcbc1c8cc6256))
* release 0.10.5 ([#147](https://github.com/cloudwalk/hermes-mcp/issues/147)) ([fe8f374](https://github.com/cloudwalk/hermes-mcp/commit/fe8f374d9687aa0d37e132c323841f9f37ae8773))
* release 0.11.0 ([#150](https://github.com/cloudwalk/hermes-mcp/issues/150)) ([615e9ac](https://github.com/cloudwalk/hermes-mcp/commit/615e9ac3a43e929bcc8ab4f25fbc276051e3eb52))
* release 0.11.1 ([#158](https://github.com/cloudwalk/hermes-mcp/issues/158)) ([e0c63f4](https://github.com/cloudwalk/hermes-mcp/commit/e0c63f4e0fc2dd8a1521720937376ade0ddf2700))
* release 0.11.2 ([#161](https://github.com/cloudwalk/hermes-mcp/issues/161)) ([2520588](https://github.com/cloudwalk/hermes-mcp/commit/2520588283e657a64b7e49a56e41a0c91fe40a13))
* release 0.11.3 ([#167](https://github.com/cloudwalk/hermes-mcp/issues/167)) ([1ff0786](https://github.com/cloudwalk/hermes-mcp/commit/1ff078657fcd0bce3dd7522bb922da57eb46a51c))
* release 0.12.0 ([#171](https://github.com/cloudwalk/hermes-mcp/issues/171)) ([c378929](https://github.com/cloudwalk/hermes-mcp/commit/c378929288ac86df540795c01ed64fb1f3766c2c))
* release 0.12.1 ([#184](https://github.com/cloudwalk/hermes-mcp/issues/184)) ([9f5f751](https://github.com/cloudwalk/hermes-mcp/commit/9f5f75150529a1d3534df73bc85211a49ef11f08))
* release 0.13.0 ([#191](https://github.com/cloudwalk/hermes-mcp/issues/191)) ([cfaaa9d](https://github.com/cloudwalk/hermes-mcp/commit/cfaaa9dd6ee3fbddad4a3c9f20d5328a1a916c75))
* release 0.5.0 ([#80](https://github.com/cloudwalk/hermes-mcp/issues/80)) ([feac95b](https://github.com/cloudwalk/hermes-mcp/commit/feac95bfafe01b35846b65ecda8553820ed8d6a3))
* release 0.6.0 ([#89](https://github.com/cloudwalk/hermes-mcp/issues/89)) ([5f44c37](https://github.com/cloudwalk/hermes-mcp/commit/5f44c371dc7d18604c88d5bab88890a6e30a1248))
* release 0.7.0 ([#100](https://github.com/cloudwalk/hermes-mcp/issues/100)) ([c9efd80](https://github.com/cloudwalk/hermes-mcp/commit/c9efd80614f04a76d1d564435a659cb50f7ed0d1))
* release 0.8.0 ([#104](https://github.com/cloudwalk/hermes-mcp/issues/104)) ([cc535dd](https://github.com/cloudwalk/hermes-mcp/commit/cc535ddefed63b539561ac7fb1a18c4d71e8e9b0))
* release 0.8.1 ([#110](https://github.com/cloudwalk/hermes-mcp/issues/110)) ([9fca055](https://github.com/cloudwalk/hermes-mcp/commit/9fca055e38187aa3aaeaed2084c57d41d63936c2))
* release 0.8.2 ([#112](https://github.com/cloudwalk/hermes-mcp/issues/112)) ([5dc7d40](https://github.com/cloudwalk/hermes-mcp/commit/5dc7d405c0568da8cfa1665e8337b6ae9b007284))
* release 0.9.0 ([#116](https://github.com/cloudwalk/hermes-mcp/issues/116)) ([73ac1ed](https://github.com/cloudwalk/hermes-mcp/commit/73ac1ed6fc15ae514e5da142bda93a0ee858f1eb))
* release 0.9.1 ([#120](https://github.com/cloudwalk/hermes-mcp/issues/120)) ([a490789](https://github.com/cloudwalk/hermes-mcp/commit/a490789ad68b504a114505677674087169ea4137))
* release please correct version on readme ([#128](https://github.com/cloudwalk/hermes-mcp/issues/128)) ([d0125c6](https://github.com/cloudwalk/hermes-mcp/commit/d0125c664b5190b560bb988ff01d17cbdba814bd))
* release please should include all files ([#108](https://github.com/cloudwalk/hermes-mcp/issues/108)) ([d0a25b9](https://github.com/cloudwalk/hermes-mcp/commit/d0a25b968c83ae1023ffffc8ee07b5b490122c03))
* simplify genserver naming handling, and bidirectional communication client &lt;&gt; transport ([#38](https://github.com/cloudwalk/hermes-mcp/issues/38)) ([5288ceb](https://github.com/cloudwalk/hermes-mcp/commit/5288cebaf3aaf211f0f8e5273ef0f365ed3ae31d))
* streamable http on hermes cli (standalone) ([#203](https://github.com/cloudwalk/hermes-mcp/issues/203)) ([2f41337](https://github.com/cloudwalk/hermes-mcp/commit/2f41337633c780c902dba5771c4a01ae3a1aabf3))
* upcate automatic version ([#98](https://github.com/cloudwalk/hermes-mcp/issues/98)) ([0c08233](https://github.com/cloudwalk/hermes-mcp/commit/0c08233371338af24ea66047b4e1a8e9fa5cb055))
* update documentation, simplify, more storytelling ([#168](https://github.com/cloudwalk/hermes-mcp/issues/168)) ([ccdddc1](https://github.com/cloudwalk/hermes-mcp/commit/ccdddc1478c09e2f3440a6f1343949aeca854a1d))
* update peri ([#126](https://github.com/cloudwalk/hermes-mcp/issues/126)) ([7292615](https://github.com/cloudwalk/hermes-mcp/commit/7292615cf57da0185006df2f6221f8ab93aacd30))


### Code Refactoring

* base mcp server implementation correctly uses streamable http ([#85](https://github.com/cloudwalk/hermes-mcp/issues/85)) ([29060fd](https://github.com/cloudwalk/hermes-mcp/commit/29060fd2d2e383c58c727a9085b30162c6b8179a))
* cleaner peri integration ([#137](https://github.com/cloudwalk/hermes-mcp/issues/137)) ([43226cc](https://github.com/cloudwalk/hermes-mcp/commit/43226cc9fb2f49edfbf8685fe181eb3093304308)), closes [#123](https://github.com/cloudwalk/hermes-mcp/issues/123)
* do not hangle on transport process ([#185](https://github.com/cloudwalk/hermes-mcp/issues/185)) ([e6ba926](https://github.com/cloudwalk/hermes-mcp/commit/e6ba9260ceb8e078ca043d6f1ceb41d540b42ca0))
* handle_sampling callback, use frame as entrypoint for notifications ([#176](https://github.com/cloudwalk/hermes-mcp/issues/176)) ([1e88711](https://github.com/cloudwalk/hermes-mcp/commit/1e887117ba81751042534d60df79d83a8123a3d9))
* higher-level client implementation ([#111](https://github.com/cloudwalk/hermes-mcp/issues/111)) ([5de2162](https://github.com/cloudwalk/hermes-mcp/commit/5de2162b166e390b4dacfd7b9960fab59c81b4d7))
* improve runtime components schema def ([#154](https://github.com/cloudwalk/hermes-mcp/issues/154)) ([96ff2a9](https://github.com/cloudwalk/hermes-mcp/commit/96ff2a97be02f0f35ee4a288838a1dbf518bbac3))
* interactive tasks now support JSON file input ([#172](https://github.com/cloudwalk/hermes-mcp/issues/172)) ([9465266](https://github.com/cloudwalk/hermes-mcp/commit/946526617171094ccf929a5d9f3bbd8e3a591f18))
* remove batch messaging feature ([#183](https://github.com/cloudwalk/hermes-mcp/issues/183)) ([99458c0](https://github.com/cloudwalk/hermes-mcp/commit/99458c0559d69addf9e22b3f7e38891e83d475de))
* tests ([#93](https://github.com/cloudwalk/hermes-mcp/issues/93)) ([ca31feb](https://github.com/cloudwalk/hermes-mcp/commit/ca31febee7aec1d45dcb32398b33228d1399ae39))

## [0.13.0](https://github.com/cloudwalk/hermes-mcp/compare/v0.12.1...v0.13.0) (2025-07-18)


### Features

* allow redact patterns on server assigns/data ([#190](https://github.com/cloudwalk/hermes-mcp/issues/190)) ([07af99f](https://github.com/cloudwalk/hermes-mcp/commit/07af99f9e43d2afa87bf5504437ecf21c346a1d7))
* better dsl for embedded nested fields on server components ([#199](https://github.com/cloudwalk/hermes-mcp/issues/199)) ([097f5fd](https://github.com/cloudwalk/hermes-mcp/commit/097f5fd8f788aaaa73c5e3d6699937656488886f))
* new server response contents for tools/resources with annotations (2025-06-18) ([#195](https://github.com/cloudwalk/hermes-mcp/issues/195)) ([9b65308](https://github.com/cloudwalk/hermes-mcp/commit/9b653087a6ddfac399b33be2c4be54d564335c84))
* resources templates ([#193](https://github.com/cloudwalk/hermes-mcp/issues/193)) ([1457e59](https://github.com/cloudwalk/hermes-mcp/commit/1457e59f16b77ca894b07a731d69ca5f8337c42b))
* tools output schema feature (2025-06-18) ([#194](https://github.com/cloudwalk/hermes-mcp/issues/194)) ([8088a49](https://github.com/cloudwalk/hermes-mcp/commit/8088a49ce4463a01e899418bb9c34fce30427d3c))


### Miscellaneous Chores

* deprecate sse transport ([#187](https://github.com/cloudwalk/hermes-mcp/issues/187)) ([1932fbc](https://github.com/cloudwalk/hermes-mcp/commit/1932fbcdef12194c496d3ac074b17ef65fe18e49))
* **deps:** bump the npm_and_yarn group across 1 directory with 2 updates ([#198](https://github.com/cloudwalk/hermes-mcp/issues/198)) ([5e21aac](https://github.com/cloudwalk/hermes-mcp/commit/5e21aac07ab1e709cb2bad8ddf9f45ba3ff99ef9))
* readme ([bed6ff7](https://github.com/cloudwalk/hermes-mcp/commit/bed6ff78ed617af3eaba6d316c1107643e8aea06))

## [0.12.1](https://github.com/cloudwalk/hermes-mcp/compare/v0.12.0...v0.12.1) (2025-07-14)


### Code Refactoring

* do not hangle on transport process ([#185](https://github.com/cloudwalk/hermes-mcp/issues/185)) ([e6ba926](https://github.com/cloudwalk/hermes-mcp/commit/e6ba9260ceb8e078ca043d6f1ceb41d540b42ca0))
* remove batch messaging feature ([#183](https://github.com/cloudwalk/hermes-mcp/issues/183)) ([99458c0](https://github.com/cloudwalk/hermes-mcp/commit/99458c0559d69addf9e22b3f7e38891e83d475de))

## [0.12.0](https://github.com/cloudwalk/hermes-mcp/compare/v0.11.3...v0.12.0) (2025-07-11)


### Features

* client sampling capability ([#170](https://github.com/cloudwalk/hermes-mcp/issues/170)) ([da617a6](https://github.com/cloudwalk/hermes-mcp/commit/da617a694dbeff1d363e7b671a31f484e202e685))
* roots/list and completion features ([#178](https://github.com/cloudwalk/hermes-mcp/issues/178)) ([d22a6bd](https://github.com/cloudwalk/hermes-mcp/commit/d22a6bdfb92189e54455c49120abc2c7fa4f8814))
* server components cursor pagination ([#177](https://github.com/cloudwalk/hermes-mcp/issues/177)) ([a95eba7](https://github.com/cloudwalk/hermes-mcp/commit/a95eba7cc2ffcefca99b3961b80094bb12a3912f))
* server-side sampling capability ([#173](https://github.com/cloudwalk/hermes-mcp/issues/173)) ([c09e7f3](https://github.com/cloudwalk/hermes-mcp/commit/c09e7f3a5e95e59f5644ef12e1602b3b8621df7f))


### Bug Fixes

* allow configuring server request timeout ([#182](https://github.com/cloudwalk/hermes-mcp/issues/182)) ([e79fe2f](https://github.com/cloudwalk/hermes-mcp/commit/e79fe2f003a41517a5ff5e8f6e3fb378bdc43f11))
* do not allow duplicate server components and more convenient API ([#180](https://github.com/cloudwalk/hermes-mcp/issues/180)) ([bc71df8](https://github.com/cloudwalk/hermes-mcp/commit/bc71df8f7c6fb877f19dada9b17c3eb342d32ccd))


### Miscellaneous Chores

* add llms summary about the library ([#175](https://github.com/cloudwalk/hermes-mcp/issues/175)) ([ed0e608](https://github.com/cloudwalk/hermes-mcp/commit/ed0e60872e5b77ddb6ffff13da6c1e20b1c2d7a2))
* allow different kind of components have the same name ([#181](https://github.com/cloudwalk/hermes-mcp/issues/181)) ([d5ba6f5](https://github.com/cloudwalk/hermes-mcp/commit/d5ba6f56fb54ed07e46d37c2217dcf76c793762f))


### Code Refactoring

* handle_sampling callback, use frame as entrypoint for notifications ([#176](https://github.com/cloudwalk/hermes-mcp/issues/176)) ([1e88711](https://github.com/cloudwalk/hermes-mcp/commit/1e887117ba81751042534d60df79d83a8123a3d9))
* interactive tasks now support JSON file input ([#172](https://github.com/cloudwalk/hermes-mcp/issues/172)) ([9465266](https://github.com/cloudwalk/hermes-mcp/commit/946526617171094ccf929a5d9f3bbd8e3a591f18))

## [0.11.3](https://github.com/cloudwalk/hermes-mcp/compare/v0.11.2...v0.11.3) (2025-07-02)


### Bug Fixes

* correctly parse dates when default values are passed ([58f6368](https://github.com/cloudwalk/hermes-mcp/commit/58f63686574e230269f847ee793d9561976653bb))
* include frame helpers on module-based component ([#163](https://github.com/cloudwalk/hermes-mcp/issues/163)) ([15ba2c7](https://github.com/cloudwalk/hermes-mcp/commit/15ba2c7fbdd0a776eabe028aef0350f4f52a43a8))
* server can now send notifications correctly ([#166](https://github.com/cloudwalk/hermes-mcp/issues/166)) ([33f32de](https://github.com/cloudwalk/hermes-mcp/commit/33f32deccd42dc4591832636b2b3fad56ce40661))


### Miscellaneous Chores

* update documentation, simplify, more storytelling ([#168](https://github.com/cloudwalk/hermes-mcp/issues/168)) ([ccdddc1](https://github.com/cloudwalk/hermes-mcp/commit/ccdddc1478c09e2f3440a6f1343949aeca854a1d))

## [0.11.2](https://github.com/cloudwalk/hermes-mcp/compare/v0.11.1...v0.11.2) (2025-06-30)

### Bug Fixes

- correctly parse peri numeric contrainsts to json-schema ([#160](https://github.com/cloudwalk/hermes-mcp/issues/160)) ([808c2c0](https://github.com/cloudwalk/hermes-mcp/commit/808c2c09e490bf9a866d5575abbf08d355c8324b))
- interactive http tasks should accept custom headers ([#159](https://github.com/cloudwalk/hermes-mcp/issues/159)) ([c2fe91e](https://github.com/cloudwalk/hermes-mcp/commit/c2fe91eff5a701e42a636ee1a291ea51a93f7983))

## [0.11.1](https://github.com/cloudwalk/hermes-mcp/compare/v0.11.0...v0.11.1) (2025-06-30)

### Bug Fixes

- loggin should respect the logger config ([#157](https://github.com/cloudwalk/hermes-mcp/issues/157)) ([0fbf6a6](https://github.com/cloudwalk/hermes-mcp/commit/0fbf6a652ed9dd5da64716d47ece675192442ea0))

## [0.11.0](https://github.com/cloudwalk/hermes-mcp/compare/v0.10.5...v0.11.0) (2025-06-30)

### Features

- runtime server components, simplified api ([#153](https://github.com/cloudwalk/hermes-mcp/issues/153)) ([8af35d6](https://github.com/cloudwalk/hermes-mcp/commit/8af35d67cd15d125e40ab9b115ff6900c3487ea5))

### Bug Fixes

- allow users to control external process messages ([#149](https://github.com/cloudwalk/hermes-mcp/issues/149)) ([8fef4eb](https://github.com/cloudwalk/hermes-mcp/commit/8fef4eb753f38a325a1d3a94c310e5fd1c478ede))
- correctly encode prompt/resource ([#155](https://github.com/cloudwalk/hermes-mcp/issues/155)) ([4249b13](https://github.com/cloudwalk/hermes-mcp/commit/4249b137e43587862de2e59acba4660ac785702a))
- more genserver mcp server callbacks, plug based startup and documentation ([#152](https://github.com/cloudwalk/hermes-mcp/issues/152)) ([9c26b1c](https://github.com/cloudwalk/hermes-mcp/commit/9c26b1ce4d033e3c69bc872a5ed01a037ec68f59))
- server behaviour with optional callbacks ([#151](https://github.com/cloudwalk/hermes-mcp/issues/151)) ([91aa191](https://github.com/cloudwalk/hermes-mcp/commit/91aa1916f28da5972f6b100861a2547697c1ddb7))

### Code Refactoring

- improve runtime components schema def ([#154](https://github.com/cloudwalk/hermes-mcp/issues/154)) ([96ff2a9](https://github.com/cloudwalk/hermes-mcp/commit/96ff2a97be02f0f35ee4a288838a1dbf518bbac3))

## [0.10.5](https://github.com/cloudwalk/hermes-mcp/compare/v0.10.4...v0.10.5) (2025-06-25)

### Bug Fixes

- normalize transport api ([#146](https://github.com/cloudwalk/hermes-mcp/issues/146)) ([8a30a34](https://github.com/cloudwalk/hermes-mcp/commit/8a30a34c944ca4d85de622f9063a558bd495c6fc)), closes [#145](https://github.com/cloudwalk/hermes-mcp/issues/145)

## [0.10.4](https://github.com/cloudwalk/hermes-mcp/compare/v0.10.3...v0.10.4) (2025-06-24)

### Bug Fixes

- server session expiration on idle (configurable) ([#143](https://github.com/cloudwalk/hermes-mcp/issues/143)) ([d9f7164](https://github.com/cloudwalk/hermes-mcp/commit/d9f7164028b2b6e8ff3d697f888adf655110bc1f))

## [0.10.3](https://github.com/cloudwalk/hermes-mcp/compare/v0.10.2...v0.10.3) (2025-06-23)

### Bug Fixes

- include formatter on hex release ([#139](https://github.com/cloudwalk/hermes-mcp/issues/139)) ([d91b244](https://github.com/cloudwalk/hermes-mcp/commit/d91b244aeed4211a6653a82705b03da2247db9a3))

## [0.10.2](https://github.com/cloudwalk/hermes-mcp/compare/v0.10.1...v0.10.2) (2025-06-23)

### Bug Fixes

- default implementation for server handle_notification ([#135](https://github.com/cloudwalk/hermes-mcp/issues/135)) ([c958041](https://github.com/cloudwalk/hermes-mcp/commit/c9580410162c31a62190631f6702024ea3458beb))

### Code Refactoring

- cleaner peri integration ([#137](https://github.com/cloudwalk/hermes-mcp/issues/137)) ([43226cc](https://github.com/cloudwalk/hermes-mcp/commit/43226cc9fb2f49edfbf8685fe181eb3093304308)), closes [#123](https://github.com/cloudwalk/hermes-mcp/issues/123)

## [0.10.1](https://github.com/cloudwalk/hermes-mcp/compare/v0.10.0...v0.10.1) (2025-06-21)

### Bug Fixes

- client should send both sse/json headers on POST requests ([#134](https://github.com/cloudwalk/hermes-mcp/issues/134)) ([e906b7f](https://github.com/cloudwalk/hermes-mcp/commit/e906b7f02bf390faecc2b6bd39aab05ef9c500b1))
- correctly allows macro-based/callback-based server implementations ([#131](https://github.com/cloudwalk/hermes-mcp/issues/131)) ([d7bfc75](https://github.com/cloudwalk/hermes-mcp/commit/d7bfc7541a8c381573f1a20ebc37d4a7dbaaa139))
- remove last uses of hard-coded Hermes.Server.Registry ([cc0ffd9](https://github.com/cloudwalk/hermes-mcp/commit/cc0ffd95fce771a9c861c6859124dcedb6ceb88e))

## [0.10.0](https://github.com/cloudwalk/hermes-mcp/compare/v0.9.1...v0.10.0) (2025-06-18)

### Features

- batch operations on server-side ([#125](https://github.com/cloudwalk/hermes-mcp/issues/125)) ([28eea7c](https://github.com/cloudwalk/hermes-mcp/commit/28eea7cd15f72c4effccc8475e6b301b2cd9745c))
- missing notifications handlers ([#129](https://github.com/cloudwalk/hermes-mcp/issues/129)) ([34d5934](https://github.com/cloudwalk/hermes-mcp/commit/34d593499fdd846f430b93b4c52ca986f345646d))
- support batch operations on client side ([#101](https://github.com/cloudwalk/hermes-mcp/issues/101)) ([fadf28d](https://github.com/cloudwalk/hermes-mcp/commit/fadf28d80068f3f1e77835fd46a276338048f0bc))
- tools annotations ([#127](https://github.com/cloudwalk/hermes-mcp/issues/127)) ([c83e8f1](https://github.com/cloudwalk/hermes-mcp/commit/c83e8f1b0e721b1a03960ac67cdd0774337675dc))

### Miscellaneous Chores

- release please correct version on readme ([#128](https://github.com/cloudwalk/hermes-mcp/issues/128)) ([d0125c6](https://github.com/cloudwalk/hermes-mcp/commit/d0125c664b5190b560bb988ff01d17cbdba814bd))
- update peri ([#126](https://github.com/cloudwalk/hermes-mcp/issues/126)) ([7292615](https://github.com/cloudwalk/hermes-mcp/commit/7292615cf57da0185006df2f6221f8ab93aacd30))

## [0.9.1](https://github.com/cloudwalk/hermes-mcp/compare/v0.9.0...v0.9.1) (2025-06-13)

### Bug Fixes

- allow enum specific type on json-schema ([#121](https://github.com/cloudwalk/hermes-mcp/issues/121)) ([23c9ce2](https://github.com/cloudwalk/hermes-mcp/commit/23c9ce2081ed1099ce1f3afbd9318c8a02480039)), closes [#114](https://github.com/cloudwalk/hermes-mcp/issues/114)
- correctly escape quoted expressions ([#119](https://github.com/cloudwalk/hermes-mcp/issues/119)) ([0c469c5](https://github.com/cloudwalk/hermes-mcp/commit/0c469c552d8d5fd2498706b4b1f41100e8561e2f)), closes [#118](https://github.com/cloudwalk/hermes-mcp/issues/118)

## [0.9.0](https://github.com/cloudwalk/hermes-mcp/compare/v0.8.2...v0.9.0) (2025-06-12)

### Features

- add independently configurable logs ([#113](https://github.com/cloudwalk/hermes-mcp/issues/113)) ([bb0be27](https://github.com/cloudwalk/hermes-mcp/commit/bb0be2716ac41bf43814a16497b209fa55cc811b))

### Bug Fixes

- allow registering a name for the client supervisor ([#117](https://github.com/cloudwalk/hermes-mcp/issues/117)) ([d356511](https://github.com/cloudwalk/hermes-mcp/commit/d356511e2fbcf47b6a85ed733671e96d800ac693))

## [0.8.2](https://github.com/cloudwalk/hermes-mcp/compare/v0.8.1...v0.8.2) (2025-06-11)

### Code Refactoring

- higher-level client implementation ([#111](https://github.com/cloudwalk/hermes-mcp/issues/111)) ([5de2162](https://github.com/cloudwalk/hermes-mcp/commit/5de2162b166e390b4dacfd7b9960fab59c81b4d7))

## [0.8.1](https://github.com/cloudwalk/hermes-mcp/compare/v0.8.0...v0.8.1) (2025-06-10)

### Bug Fixes

- hermes should respect mix releases startup ([#109](https://github.com/cloudwalk/hermes-mcp/issues/109)) ([f42d476](https://github.com/cloudwalk/hermes-mcp/commit/f42d476e1dc05c57479170bd58aaca9028ef1e66))

## [0.8.0](https://github.com/cloudwalk/hermes-mcp/compare/v0.7.0...v0.8.0) (2025-06-10)

### Features

- inject user and transport data on mcp server frame ([#106](https://github.com/cloudwalk/hermes-mcp/issues/106)) ([feb2ce3](https://github.com/cloudwalk/hermes-mcp/commit/feb2ce308e9fd0cde4118b294dd47ce64d8db18f))
- legacy sse server transport ([#102](https://github.com/cloudwalk/hermes-mcp/issues/102)) ([4a71088](https://github.com/cloudwalk/hermes-mcp/commit/4a71088713071a726bde03bf1385c3c794d2134b))

### Bug Fixes

- allow empty capabilities on incoming JSON-RPC messages ([#105](https://github.com/cloudwalk/hermes-mcp/issues/105)) ([f0ad4cf](https://github.com/cloudwalk/hermes-mcp/commit/f0ad4cf1a5a85cc8a56baed875d2d2d200bb5860)), closes [#96](https://github.com/cloudwalk/hermes-mcp/issues/96)

### Miscellaneous Chores

- release please should include all files ([#108](https://github.com/cloudwalk/hermes-mcp/issues/108)) ([d0a25b9](https://github.com/cloudwalk/hermes-mcp/commit/d0a25b968c83ae1023ffffc8ee07b5b490122c03))

## [0.7.0](https://github.com/cloudwalk/hermes-mcp/compare/v0.6.0...v0.7.0) (2025-06-09)

### Features

- allow json schema fields on tools/prompts definition ([#99](https://github.com/cloudwalk/hermes-mcp/issues/99)) ([0345f12](https://github.com/cloudwalk/hermes-mcp/commit/0345f122484a0169645c5da07e50c2d64fd6c5f5))

## [0.6.0](https://github.com/cloudwalk/hermes-mcp/compare/v0.5.0...v0.6.0) (2025-06-09)

### Features

- allow customize server registry impl ([#94](https://github.com/cloudwalk/hermes-mcp/issues/94)) ([f3ac087](https://github.com/cloudwalk/hermes-mcp/commit/f3ac08749a7c361466a7a619f9782e8d8706a7b6))
- mcp high level server components definition ([#91](https://github.com/cloudwalk/hermes-mcp/issues/91)) ([007f41d](https://github.com/cloudwalk/hermes-mcp/commit/007f41d33874fd9f1b5e340ecbe16317dc3576b7))
- mcp server handlers refactored ([#92](https://github.com/cloudwalk/hermes-mcp/issues/92)) ([e213e04](https://github.com/cloudwalk/hermes-mcp/commit/e213e046b1360b24ff9e42835cdf80f5fe2ae4fa))

### Bug Fixes

- correctly handle mcp requests on phoenix apps ([#88](https://github.com/cloudwalk/hermes-mcp/issues/88)) ([09f4235](https://github.com/cloudwalk/hermes-mcp/commit/09f42359f0daac694013f0be4f6a74de2be7f4ff)), closes [#86](https://github.com/cloudwalk/hermes-mcp/issues/86)

### Miscellaneous Chores

- upcate automatic version ([#98](https://github.com/cloudwalk/hermes-mcp/issues/98)) ([0c08233](https://github.com/cloudwalk/hermes-mcp/commit/0c08233371338af24ea66047b4e1a8e9fa5cb055))

### Code Refactoring

- tests ([#93](https://github.com/cloudwalk/hermes-mcp/issues/93)) ([ca31feb](https://github.com/cloudwalk/hermes-mcp/commit/ca31febee7aec1d45dcb32398b33228d1399ae39))

## [0.5.0](https://github.com/cloudwalk/hermes-mcp/compare/v0.4.1...v0.5.0) (2025-06-05)

### Features

- client support new mcp spec ([#83](https://github.com/cloudwalk/hermes-mcp/issues/83)) ([73d14f7](https://github.com/cloudwalk/hermes-mcp/commit/73d14f77522cef0f7212230c05cdac23ee2d93e2))
- enable log disabling ([#78](https://github.com/cloudwalk/hermes-mcp/issues/78)) ([fa1453f](https://github.com/cloudwalk/hermes-mcp/commit/fa1453fee9b015c0ad7f9ac223749a9c9f1fcf6a))
- low level genservy mcp server implementation (stdio + stremable http) ([#77](https://github.com/cloudwalk/hermes-mcp/issues/77)) ([e6606b4](https://github.com/cloudwalk/hermes-mcp/commit/e6606b4d66a2d7ddeb6c32e0041c22d4f0036ac5))
- mvp higher level mcp server definition ([#84](https://github.com/cloudwalk/hermes-mcp/issues/84)) ([a5fec1c](https://github.com/cloudwalk/hermes-mcp/commit/a5fec1c976595c3363d4eec83e0cbc382eac9207))

### Code Refactoring

- base mcp server implementation correctly uses streamable http ([#85](https://github.com/cloudwalk/hermes-mcp/issues/85)) ([29060fd](https://github.com/cloudwalk/hermes-mcp/commit/29060fd2d2e383c58c727a9085b30162c6b8179a))

## [0.4.0](https://github.com/cloudwalk/hermes-mcp) - 2025-05-06

### Added

- Implemented WebSocket transport (#70)
- Emit `telemetry` events (#54)
- Implement client feature `completion` request (#72)
- Implement client feature roots, server requests (#73)

## [0.3.12](https://github.com/cloudwalk/hermes-mcp) - 2025-04-24

### Fixed

- Correctly handles "nested" timeouts (genserver vs MCP) (#71)

## [0.3.11](https://github.com/cloudwalk/hermes-mcp) - 2025-04-17

### Added

- Improved core library logging and added verbosity level on interactive/CLI (#68)

## [0.3.10](https://github.com/cloudwalk/hermes-mcp) - 2025-04-17

### Fixed

- Handle SSE ping and reconnect events from server (#65)

## [0.3.9](https://github.com/cloudwalk/hermes-mcp) - 2025-04-15

### Fixed

- Improved and simplified SSE endpoint event URI merging (#64)

### Added

- Added internal client/transport state inspection on CLI/mix tasks (#61)

## [0.3.8](https://github.com/cloudwalk/hermes-mcp) - 2025-04-10

### Added

- Created `Operation` struct to standardize client API calls (#56)
- Fixed ERTS version to avoid release errors

### Fixed

- Resolved client timeout confusion by standardizing timeout handling (#42)

## [0.3.7](https://github.com/cloudwalk/hermes-mcp) - 2025-04-01

### Fixed

- Client reinitialization from interactive CLI (#55)

## [0.3.6](https://github.com/cloudwalk/hermes-mcp) - 2025-03-28

### Added

- New roadmap and protocol update proposal (#53)
- Added documentation for the 2025-03-26 protocol update

## [0.3.5](https://github.com/cloudwalk/hermes-mcp) - 2025-03-25

### Documentation

- Added Roadmap to README (#47)

## [0.3.4](https://github.com/cloudwalk/hermes-mcp) - 2025-03-20

### Added

- `help` command and flag on the interactive CLI (#37)
- improve SSE connection status on interactive task/cli (#37)

## [0.3.3](https://github.com/cloudwalk/hermes-mcp) - 2025-03-20

### Added

- Client request cancellation support (#35)
- Improved URI path handling for SSE transport (#36)
- Enhanced interactive mix tasks for testing MCP servers (#34)

## [0.3.2](https://github.com/cloudwalk/hermes-mcp) - 2025-03-19

### Added

- Ship static binaries to use hermes-mcp as standalone application

## [0.3.1](https://github.com/cloudwalk/hermes-mcp) - 2025-03-19

### Added

- Ship interactive mix tasks `stdio.interactive` and `sse.interactive` to test MCP servers

## [0.3.0](https://github.com/cloudwalk/hermes-mcp) - 2025-03-18

### Added

- Structured server-client logging support (#27)
- Progress notification tracking (#26)
- MCP domain model implementation (#28)
- Comprehensive SSE unit tests (#20)
- Centralized state management (#31)
- Standardized error response handling (#32)

### Fixed

- Improved domain error handling (#33)

## [0.2.3](https://github.com/cloudwalk/hermes-mcp) - 2025-03-12

### Added

- Enhanced SSE transport with graceful shutdown capabilities (#25)
- Improved SSE streaming with automatic reconnection handling (#25)

## [0.2.2](https://github.com/cloudwalk/hermes-mcp) - 2025-03-05

### Added

- Support for multiple concurrent client <> transport pairs (#24)
- Improved client resource management

## [0.2.1](https://github.com/cloudwalk/hermes-mcp) - 2025-02-28

### Added

- Support for custom base and SSE paths in HTTP/SSE client (#19)
- Enhanced configuration options for SSE endpoints

## [0.2.0](https://github.com/cloudwalk/hermes-mcp) - 2025-02-27

### Added

- Implemented HTTP/SSE transport (#7)
  - Support for server-sent events communication
  - HTTP client integration for MCP protocol
  - Streaming response handling

### Documentation

- Extensive guides and documentation improvements

## [0.1.0](https://github.com/cloudwalk/hermes-mcp) - 2025-02-26

### Added

- Implemented STDIO transport (#1) for MCP communication
  - Support for bidirectional communication via standard I/O
  - Automatic process monitoring and recovery
  - Environment variable handling for cross-platform support
  - Integration test utilities in Mix tasks

- Created stateful client interface (#6)
  - Robust GenServer implementation for MCP client
  - Automatic initialization and protocol handshake
  - Synchronous-feeling API over asynchronous transport
  - Support for all MCP operations (ping, resources, prompts, tools)
  - Proper error handling and logging
  - Capability negotiation and management

- Developed JSON-RPC message parsing (#5)
  - Schema-based validation of MCP messages
  - Support for requests, responses, notifications, and errors
  - Comprehensive test suite for message handling
  - Encoding/decoding functions with proper validation

- Established core architecture and client API
  - MCP protocol implementation following specification
  - Client struct for maintaining connection state
  - Request/response correlation with unique IDs
  - Initial transport abstraction layer

### Documentation

- Added detailed RFC document describing the library architecture
- Enhanced README with project overview and installation instructions
