// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "./Base64.sol";
import "./Strings.sol";
import "./IRenderer.sol";
contract OnChainCSGameRenderer is IRenderer {

  using Strings for uint;

  struct RenderData {
        string[20] colors;
        string[6] hat;
        string[9] head;
        string[4] body1;
        string[4] body2;
        string[4] gun;
        string[6] leg;
    }

    function _renderSVG(uint256 tokenId, uint hp, uint shootTimes) private pure returns (bytes memory) {
        bytes memory svg = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 320 320" ><rect width="100%" height="100%" fill="#121212" /><g font-family="Courier,monospace" font-weight="700" font-size="40" text-anchor="middle" letter-spacing="1">';

        uint seed = uint(
            keccak256(abi.encodePacked(tokenId))
        );

        RenderData memory data = RenderData({
            colors: ["#e60049","#82b6b9","#b3d4ff","#00ffff","#0bb4ff","#1853ff","#35d435","#61ff75","#00bfa0","#ffa300","#fd7f6f","#d0f400","#9b19f5","#dc0ab4","#f46a9b","#bd7ebe","#fdcce5","#FCE74C","#eeeeee","#7f766d"],
            hat: [unicode"\\Ω/", unicode"\\Λ/", unicode"_∩_","_%_", unicode"\\_/", unicode"(_)"],
            head: [unicode"θ", unicode"⊚", unicode"⊙", unicode"⊡", unicode"▪", unicode"▫", unicode"△", unicode"◊", "@"],
            body1: ["(", "[", "/", unicode"√"],
            body2: ["L", ">", "+", unicode"×"],
            gun: [unicode"︻╦╤─", unicode"︻デ═一",unicode"︻╦̵̵͇╤──", unicode"╦̵̵̿╤"],
            leg: [unicode"/\\",unicode"∫\\",unicode"ƒ\\",unicode"/†",unicode"∫†",unicode"ƒ†"]
        });

        bytes memory hpText = "";
        for(uint i = 0; i < hp; i++) {
            hpText = abi.encodePacked(hpText, unicode'♥', i < hp - 1 ? ' ': '');
        }
        bytes memory bulletText = "";
        for(uint i = 0; i < shootTimes; i++) {
            bulletText = abi.encodePacked(bulletText, unicode'⁍');
        }

        string[9] memory body = _randomBody(data, seed);
        return abi.encodePacked(svg,
            _buildBody(body),
            _buildBody2(body),
            '<text x="160" y="260" font-size="30" fill="#f00">',hpText,'</text>',
            '<text x="160" y="300" font-size="30" fill="#ff0">',bulletText,'</text></g></svg>'
        );
    }

    function _buildBody(string[9] memory body) private pure returns(bytes memory) {
        return abi.encodePacked(
            '<text x="130" y="60" fill="', body[6] ,'">',body[0],'</text>',
            '<text x="130" y="100" fill="', body[7],'">',body[1],'</text>',
            '<text x="120" y="140" fill="', body[7] ,'">',body[2], body[3],'</text>'
        );
    }

    function _buildBody2(string[9] memory body) private pure returns(bytes memory) {
        return abi.encodePacked(
            '<text x="150" y="130" text-anchor="start" font-size="30" font-family="Arial, sans-serif" fill="', body[8] ,'">',body[4],'</text>'
            '<text x="130" y="180" fill="', body[7] ,'">',body[5],'</text>'
            '<text x="160" y="220" font-size="20" fill="#fff">buy to shoot</text>'
        );
    }

    function _randomBody(RenderData memory data, uint seed) private pure returns(string[9] memory body) {
        body[0] = data.hat[(seed >> 15) % 6];
        body[1] = data.head[(seed >> 20) % 9];
        body[2] = data.body1[(seed >> 25) % 4];
        body[3] = data.body2[(seed >> 27) % 4];
        body[4] = data.gun[(seed >> 30) % 4];
        body[5] = data.leg[(seed >> 35) % 6];

        uint[3] memory colors = [seed%20, (seed >> 5) % 20, (seed >> 10) % 20];
        if (colors[1] == colors[0]) {
            colors[1] += 1;
        }
        if (colors[2] == colors[0] || colors[2] == colors[1]) {
            colors[2] = (colors[0] + colors[1]) % 20;
        }

        body[6] = data.colors[colors[0]];
        body[7] = data.colors[colors[1]];
        body[8] = data.colors[colors[2]];
  }

  function render(uint tokenId, uint hp, uint shootTimes) external pure returns(string memory) {
    bytes memory d = abi.encodePacked('{"name": "OnChainCSGame #', tokenId.toString(), '","description":"First-ever trade to play 100% on-chain game. just buy to shoot randomly.  killed guy will be transferred to the buyer","image": "data:image/svg+xml;base64,', Base64.encode(_renderSVG(tokenId, hp, shootTimes)), '","attributes": [{ "trait_type": "HP", "value":', hp.toString(),  ' }, { "trait_type": "Bullets", "value":', shootTimes.toString(),'}]}');
    return string(abi.encodePacked('data:application/json;base64,', Base64.encode(d)));
  }
}
