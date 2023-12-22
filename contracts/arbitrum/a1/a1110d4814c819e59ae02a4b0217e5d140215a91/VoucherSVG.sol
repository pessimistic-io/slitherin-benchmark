// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./IVoucherSVG.sol";
import "./ISurfVoucher.sol";
import "./StringConverter.sol";

contract VoucherSVG is IVoucherSVG {
  using StringConverter for uint256;
  using StringConverter for uint128;
  using StringConverter for bytes;

  struct SVGParams {
    uint256 bondsAmount;
    uint128 tokenId;
    uint128 slotId;
    uint8 bondsDecimals;
  }

  string private constant BG_COLOR_0 = "#186e6e";
  string private constant BG_COLOR_1 = "#111212";

  /// Admin functions

  /// View functions

  function generateSVG(address _voucher, uint256 _tokenId) external view override returns (bytes memory) {
    ISurfVoucher voucher = ISurfVoucher(_voucher);
    uint128 slotId = uint128(voucher.slotOf(_tokenId));

    SVGParams memory svgParams;
    svgParams.bondsAmount = voucher.unitsInToken(_tokenId);
    svgParams.tokenId = uint128(_tokenId);
    svgParams.slotId = slotId;
    svgParams.bondsDecimals = uint8(voucher.unitDecimals());

    return _generateSVG(svgParams);
  }

  /// Internal functions

  function _generateSVG(SVGParams memory params) internal view virtual returns (bytes memory) {
    return
        abi.encodePacked(
          '<svg width="600px" height="400px" viewBox="0 0 600 400" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">',
          _generateDefs(),
          '<g stroke-width="1" fill="none" fill-rule="evenodd" font-family="Arial">',
          _generateBackground(),
          _generateTitle(params),
          _generateLogo(),
          "</g>",
          "</svg>"
      );
  }

  function _generateDefs() internal pure returns (string memory) {
    return 
        string(
            abi.encodePacked(
                '<defs>',
                    '<linearGradient x1="0%" y1="75%" x2="100%" y2="30%" id="lg-1">',
                        '<stop stop-color="', BG_COLOR_1,'" offset="0%"></stop>',
                        '<stop stop-color="', BG_COLOR_0, '" offset="100%"></stop>',
                    '</linearGradient>',
                    '<rect id="path-2" x="16" y="16" width="568" height="368" rx="16"></rect>',
                    '<linearGradient x1="100%" y1="50%" x2="0%" y2="50%" id="lg-2">',
                        '<stop stop-color="#FFFFFF" offset="0%"></stop>',
                        '<stop stop-color="#FFFFFF" stop-opacity="0" offset="100%"></stop>',
                    '</linearGradient>', 
                    abi.encodePacked(
                        '<linearGradient x1="50%" y1="0%" x2="50%" y2="100%" id="lg-3">',
                            '<stop stop-color="#FFFFFF" offset="0%"></stop>',
                            '<stop stop-color="#FFFFFF" stop-opacity="0" offset="100%"></stop>',
                        '</linearGradient>',
                        '<linearGradient x1="100%" y1="50%" x2="35%" y2="50%" id="lg-4">',
                            '<stop stop-color="#FFFFFF" offset="0%"></stop>',
                            '<stop stop-color="#FFFFFF" stop-opacity="0" offset="100%"></stop>',
                        '</linearGradient>',
                        '<linearGradient x1="50%" y1="0%" x2="50%" y2="100%" id="lg-5">',
                            '<stop stop-color="#FFFFFF" offset="0%"></stop>',
                            '<stop stop-color="#FFFFFF" stop-opacity="0" offset="100%"></stop>',
                        '</linearGradient>'
                    ),
                    '<path id="text-path-a" d="M30 12 H570 A18 18 0 0 1 588 30 V370 A18 18 0 0 1 570 388 H30 A18 18 0 0 1 12 370 V30 A18 18 0 0 1 30 12 Z" />',
                '</defs>'
            )
        );
  }

  function _generateBackground() internal pure returns (string memory) {
    return 
        string(
            abi.encodePacked(
                '<rect fill="url(#lg-1)" x="0" y="0" width="600" height="400" rx="24"></rect>',
                '<g text-rendering="optimizeSpeed" opacity="0.5" font-family="Arial" font-size="10" font-weight="500" fill="#FFFFFF">',
                    '<text><textPath startOffset="-100%" xlink:href="#text-path-a">In Crypto We Trust<animate additive="sum" attributeName="startOffset" from="0%" to="100%" begin="0s" dur="30s" repeatCount="indefinite" /></textPath></text>',
                    '<text><textPath startOffset="0%" xlink:href="#text-path-a">In Crypto We Trust<animate additive="sum" attributeName="startOffset" from="0%" to="100%" begin="0s" dur="30s" repeatCount="indefinite" /></textPath></text>',
                    '<text><textPath startOffset="50%" xlink:href="#text-path-a">Powered by Solv Protocol<animate additive="sum" attributeName="startOffset" from="0%" to="100%" begin="0s" dur="30s" repeatCount="indefinite" /></textPath></text>',
                    '<text><textPath startOffset="-50%" xlink:href="#text-path-a">Powered by Solv Protocol<animate additive="sum" attributeName="startOffset" from="0%" to="100%" begin="0s" dur="30s" repeatCount="indefinite" /></textPath></text>',
                '</g>',
                '<rect stroke="#FFFFFF" x="16.5" y="16.5" width="567" height="367" rx="16"></rect>',
                '<mask id="mask-3" fill="white">',
                    '<use xlink:href="#path-2"></use>',
                '</mask>',
                '<path d="M404,-41 L855,225 M165,100 L616,366 M427,-56 L878,210 M189,84 L640,350 M308,14 L759,280 M71,154 L522,420 M380,-27 L831,239 M143,113 L594,379 M286,28 L737,294 M47,169 L498,435 M357,-14 L808,252 M118,128 L569,394 M262,42 L713,308 M24,183 L475,449 M333,0 L784,266 M94,141 L545,407 M237,57 L688,323 M0,197 L451,463 M451,-69 L902,197 M214,71 L665,337 M665,57 L214,323 M902,197 L451,463 M569,0 L118,266 M808,141 L357,407 M640,42 L189,308 M878,183 L427,449 M545,-14 L94,252 M784,128 L333,394 M616,28 L165,294 M855,169 L404,435 M522,-27 L71,239 M759,113 L308,379 M594,14 L143,280 M831,154 L380,420 M498,-41 L47,225 M737,100 L286,366 M475,-56 L24,210 M713,84 L262,350 M451,-69 L0,197 M688,71 L237,337" stroke="url(#lg-2)" opacity="0.2" mask="url(#mask-3)"></path>'
            )
        );
  }

  function _generateTitle(SVGParams memory params) internal pure returns (string memory) {
    string memory tokenIdStr = params.tokenId.toString();
    uint256 tokenIdLeftMargin = 488 - 20 * bytes(tokenIdStr).length;

    bytes memory amount = _formatValue(params.bondsAmount, params.bondsDecimals);
    uint256 amountLeftMargin = 290 - 20 * amount.length;

    return 
      string(
        abi.encodePacked(
          '<g transform="translate(40, 40)" fill="#FFFFFF" fill-rule="nonzero">',
              '<text font-family="Arial" font-size="32">',
                  abi.encodePacked(
                      '<tspan x="', tokenIdLeftMargin.toString(), '" y="25"># ', tokenIdStr, '</tspan>'
                  ),
              '</text>',
              '<text font-family="Arial" font-size="64">',
                  abi.encodePacked(
                      '<tspan x="', amountLeftMargin.toString(), '" y="185">', amount, '</tspan>'
                  ),
              '</text>',
              '<text font-family="Arial" font-size="24"><tspan x="460" y="185">Units</tspan></text>',
              '<text font-family="Arial" font-size="24" font-weight="500"><tspan x="60" y="25"> SURF ISR Voucher</tspan></text>',
          '</g>'
        )
      );
  }

    function _generateLogo() internal pure returns (string memory) {
    return
      string(
        abi.encodePacked(
            '<g fill-rule="evenodd">',
              '<path d="M64.256 31.399c-.185.011-.339.045-.339.074 0 .028-.069.051-.153.051-.367 0-1.898.259-2 .34a.171.171 0 0 1-.149.021c-.045-.016-.082-.01-.082.016s-.121.064-.271.084c-.149.019-.271.058-.271.087s-.079.049-.173.049c-.181 0-1.186.264-1.234.324-.015.019-.207.09-.428.159-.22.069-.517.183-.658.254a1.484 1.484 0 0 1-.316.129c-.032 0-.06.024-.06.054s-.048.054-.107.054c-.058 0-.211.048-.339.105a245.797 245.797 0 0 0-.653.298c-.232.106-.445.193-.474.193-.029 0-.053.019-.053.043s-.162.126-.362.224a4.88 4.88 0 0 0-.42.227c-.129.107-.471.316-.518.316-.063 0-.44.22-.534.311-.04.04-.162.12-.271.18a3.919 3.919 0 0 0-.747.539c-.094.088-.196.159-.226.159s-.088.03-.128.068a3.526 3.526 0 0 1-.261.201 6.241 6.241 0 0 0-.769.665c-.113.112-.223.204-.245.204-.128 0-2.047 1.987-2.13 2.207-.025.068-.078.125-.116.127-.076.003-.668.712-.802.962a1.283 1.283 0 0 1-.168.243c-.245.245-1.238 1.753-1.238 1.882 0 .053-.037.11-.081.127-.045.016-.081.056-.081.088 0 .03-.133.288-.297.57-.279.484-.732 1.47-.732 1.596 0 .031-.024.056-.052.056s-.081.103-.116.23a5.429 5.429 0 0 1-.315.799 8.02 8.02 0 0 0-.19.569 7.8 7.8 0 0 1-.225.659 1.862 1.862 0 0 0-.112.433c-.019.145-.051.286-.074.315-.022.03-.055.211-.075.404-.019.192-.055.363-.08.379-.054.036-.191.642-.349 1.547-.174.998-.173 5.792.002 6.771.18 1.008.292 1.514.344 1.546.027.016.064.187.082.379.019.192.053.373.075.404.023.03.054.172.074.315.019.145.068.34.11.433.041.094.144.392.225.659.082.269.168.524.191.569.081.158.249.571.318.786a.99.99 0 0 0 .105.244c.019.015.102.197.185.406.083.209.207.489.275.622.068.133.204.409.302.61.097.201.196.366.218.366.023 0 .069.074.107.162.037.09.089.162.115.162.026 0 .048.047.048.105 0 .057.11.266.244.467.133.2.244.375.244.389 0 .084 1.45 2.003 1.732 2.294.075.076.22.248.323.379.258.331 1.548 1.592 2.18 2.136l.472.406c.155.133.329.266.388.292.057.028.104.067.104.09 0 .023.116.107.258.188.251.145.298.18.536.396.064.058.201.146.304.194.102.049.232.132.289.183.114.105.874.55.938.55.023 0 .097.049.166.107.069.058.157.107.196.107.065 0 .392.193.547.324.036.03.079.055.094.055.016 0 .283.123.592.274.31.149.651.288.757.305.107.017.196.053.196.079 0 .025.028.048.06.048s.173.056.311.127c.139.069.441.184.672.256.231.071.42.149.42.175 0 .024.025.029.056.01.031-.019.089-.008.129.024.04.032.313.122.608.198.295.076.639.173.767.214.128.043.315.077.417.077.102 0 .197.022.214.048.036.058.544.141.75.121.082-.006.149.008.149.034s.262.079.583.116c.321.038.641.097.713.132.201.097 5.302.09 5.362-.01.027-.043.119-.066.229-.056.102.01.209.002.237-.016.03-.017.206-.049.392-.071.185-.022.339-.056.339-.079s.196-.054.435-.071c.24-.016.465-.053.5-.082a.486.486 0 0 1 .227-.055c.09-.002.272-.04.406-.084a17.266 17.266 0 0 1 .783-.224c.297-.079.566-.162.596-.188a.261.261 0 0 1 .095-.053c.045-.006.039-.004.583-.184.223-.074.479-.172.569-.22a.804.804 0 0 1 .223-.088c.032 0 .092-.037.129-.082a.29.29 0 0 1 .198-.081c.071 0 .409-.133.747-.298.339-.165.641-.298.674-.298.032 0 .058-.019.058-.042 0-.023.165-.125.366-.226.201-.102.378-.203.394-.225a.53.53 0 0 1 .162-.1c.192-.082.834-.444.866-.487.015-.019.223-.167.46-.324.238-.158.441-.31.451-.335a.081.081 0 0 1 .069-.047c.062 0 .325-.185.555-.392.092-.082.181-.149.201-.149a.614.614 0 0 0 .171-.121c.075-.067.194-.168.265-.226.807-.653 2.089-1.93 2.78-2.767.147-.179.337-.396.42-.484.084-.088.153-.175.153-.194 0-.019.062-.106.139-.193.129-.147.688-.937.809-1.147.03-.051.185-.289.347-.526a7 7 0 0 0 .407-.678c.064-.133.183-.348.263-.474.133-.209.35-.653.435-.893.048-.135-.077-.121-.406.045-4.888 2.476-11.954 4.849-16.678 5.6-11.797 1.873-21.329-3.202-20.307-10.814.557-4.14 4.677-6.626 9.631-5.807.517.084.511.09-.439.392-4.881 1.553-6.792 4.047-5.557 7.25.998 2.585 5.365 4.824 10.76 5.516 1.193.153 1.114.166 1.353-.223 1.467-2.378 3.579-5.437 5.711-8.271l1.073-1.423-.23-.136c-3.697-2.186-5.796-3.487-8.568-5.318-2.109-1.393-4.911-3.329-4.891-3.379.087-.224 5.003-5.171 6.785-6.827 1.868-1.736 4.848-4.269 4.848-4.122 0 .067-1.143 2.022-1.751 2.993-1.137 1.82-2.476 3.792-4.052 5.969-.477.658-.847 1.213-.822 1.236.024.022.592.35 1.262.73 4.135 2.344 12.703 7.762 12.703 8.032 0 .378-7.687 8.002-10.326 10.241-.409.348-.745.647-.747.664-.006.069 1.496.097 2.677.049 4.707-.192 10.157-1.262 17.983-3.532.517-.149.648-.256.782-.626.062-.171.138-.355.169-.409.069-.121.24-.674.322-1.038.032-.148.079-.283.101-.298.083-.058.355-1.319.526-2.438a1.35 1.35 0 0 1 .081-.325c.296-.557.292-6.114-.002-6.8-.025-.06-.101-.438-.168-.84a226.657 226.657 0 0 0-.162-.975c-.062-.36-.224-.942-.274-.977-.024-.015-.069-.149-.101-.298-.069-.318-.27-.951-.326-1.028a5.295 5.295 0 0 1-.21-.534 12.934 12.934 0 0 0-.297-.757l-.252-.563c-.069-.157-.147-.285-.171-.285-.024 0-.045-.026-.045-.058 0-.088-.266-.65-.391-.825a3.784 3.784 0 0 1-.262-.469c-.158-.328-1.354-2.135-1.592-2.408a.736.736 0 0 1-.136-.192c0-.019-.118-.159-.261-.313a8.691 8.691 0 0 1-.481-.567c-.254-.335-1.315-1.426-1.748-1.802a32.977 32.977 0 0 1-.602-.536 8.781 8.781 0 0 0-.46-.4l-.555-.422a21.244 21.244 0 0 0-.894-.636 9.518 9.518 0 0 1-.524-.366c-.045-.054-.435-.272-.487-.272-.045 0-.391-.211-.521-.321a4.097 4.097 0 0 0-.406-.224c-.191-.094-.353-.194-.363-.22-.01-.027-.045-.048-.081-.048-.035-.001-.232-.084-.439-.187a3.639 3.639 0 0 0-.524-.22.455.455 0 0 1-.214-.11c-.036-.043-.132-.078-.214-.078-.082 0-.18-.037-.218-.081-.037-.045-.094-.081-.129-.082-.034 0-.133-.039-.223-.087s-.344-.147-.569-.22a8.554 8.554 0 0 1-.57-.208c-.256-.116-1.216-.359-1.273-.323-.028.017-.053.01-.053-.019 0-.028-.108-.067-.243-.088-.133-.019-.256-.058-.272-.084-.016-.027-.066-.036-.11-.017a.165.165 0 0 1-.147-.024c-.07-.058-1.19-.258-1.78-.318-.19-.019-.363-.062-.383-.094-.038-.058-4.281-.1-5.067-.049" fill="#fcbb33"/>',
            '</g>'
        )
      );
  }

  function _formatValue(uint256 value, uint8 decimals) private pure returns (bytes memory) {
    return value.uint2decimal(decimals).trim(decimals - 2).addThousandsSeparator();
  }
}
