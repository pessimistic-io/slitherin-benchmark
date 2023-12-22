// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./base64.sol";
import "./INpcDesc.sol";
import "./Strings.sol";

contract ArbitrumNpcDesc is INpcDesc {
 struct Color {
 string value;
 string name;
 }
 struct Trait {
 string content;
 string name;
 Color color;
 }
 using Strings for uint256;

 string private constant SVG_END_TAG = '</svg>';

function tokenURI(uint256 tokenId, uint256 seed) external pure override returns (string memory) {
        uint256[4] memory colors = [seed % 100000000000000 / 1000000000000, seed % 10000000000 / 100000000, seed % 1000000 / 10000, seed % 100];
        Trait memory head = getHead(seed / 100000000000000, colors[0]);
        Trait memory body = getBody(seed % 1000000000000 / 10000000000, colors[1]);
        Trait memory legs = getLegs(seed % 100000000 / 1000000, colors[2]);
        Trait memory feet = getFeet(seed % 10000 / 100, colors[3]);
        string memory colorCount = calculateColorCount(colors);



 string memory rawSvg = string(
 abi.encodePacked(
 '<svg width="512" height="512" viewBox="0 0 320 320" xmlns="http://www.w3.org/2000/svg">',
 '<rect width="100%" height="100%" fill="#2c4369"/>',
 '<text x="160" y="130" font-family="Impact" font-weight="400" font-size="20" text-anchor="middle" letter-spacing="1">',
 head.content,
 body.content,
 legs.content,
 feet.content,
 '</text>',
 SVG_END_TAG
 )
 );

 string memory encodedSvg = Base64.encode(bytes(rawSvg));
 string memory description = 'Stole grandma`s funds to deploy ANPCs.';

 return string(
 abi.encodePacked(
 'data:application/json;base64,',
 Base64.encode(
 bytes(
 abi.encodePacked(
 '{',
 '"name":"ANPC #', tokenId.toString(), '",',
 '"description":"', description, '",',
 '"image": "', 'data:image/svg+xml;base64,', encodedSvg, '",',
 '"attributes": [{"trait_type": "Head", "value": "', head.name,' (',head.color.name,')', '"},',
 '{"trait_type": "Body", "value": "', body.name,' (',body.color.name,')', '"},',
 '{"trait_type": "Legs", "value": "', legs.name,' (',legs.color.name,')', '"},',
 '{"trait_type": "Feet", "value": "', feet.name,' (',feet.color.name,')', '"},',
 '{"trait_type": "010110010", "value": ', colorCount, '}',
 ']',
 '}')
 )
 )
 )
 );
 }

 function getColor(uint256 seed) private pure returns (Color memory) {
 if (seed == 10) {
 return Color("#dc4e7b", "dc4e7b");
 }
 if (seed == 11) {
 return Color("#9dd9dc", "9dd9dc");
 }
 if (seed == 12) {
 return Color("#b3d4ff", "b3d4ff");
 }
 if (seed == 13) {
 return Color("#32f0f0", "32f0f0");
 }
 if (seed == 14) {
 return Color("#129edc", "129edc");
 }
 if (seed == 15) {
 return Color("#86a1ed", "86a1ed");
 }
 if (seed == 16) {
 return Color("#98e839", "98e839");
 }
 if (seed == 17) {
 return Color("#7bed89", "7bed89");
 }
 if (seed == 18) {
 return Color("#18c7ab", "18c7ab");
 }
 if (seed == 19) {
 return Color("#ffbf4d", "ffbf4d");
 }
 if (seed == 20) {
 return Color("#e5786a", "e5786a");
 }
 if (seed == 21) {
 return Color("#b5d400", "b5d400");
 }
 if (seed == 22) {
 return Color("#ab31ff", "ab31ff");
 }
 if (seed == 23) {
 return Color("#f014c6", "f014c6");
 }
 if (seed == 24) {
 return Color("#ec8eaf", "ec8eaf");
 }
 if (seed == 25) {
 return Color("#bd7ebe", "bd7ebe");
 }
 if (seed == 26) {
 return Color("#fdcce5", "fdcce5");
 }
 if (seed == 27) {
 return Color("#FCE74C", "ffee6d");
 }
 if (seed == 28) {
 return Color("#eeeeee", "eeeeee");
 }
 if (seed == 29) {
 return Color("#cbbed0", "cbbed0");
 }

 return Color('','');
 }

 function getHead(uint256 seed, uint256 colorSeed) private pure returns (Trait memory) {
 Color memory color = getColor(colorSeed);
 string memory content;
 string memory name;
 if (seed == 10) {
 content = "[O_O]";
 name = "Regular Square";
 }
 if (seed == 11) {
 content = "[-_-]";
 name = "Sleeping square";
 }
 if (seed == 12) {
 content = "[O_-]";
 name = "Wink Square";
 }
 if (seed == 13) {
 content = "(O_O)";
 name = "Regular Round";
 }
 if (seed == 14) {
 content = "(-_-)";
 name = "Sleeping Round";
 }
 if (seed == 15) {
 content = "(O_-)";
 name = "Wink Round";
 }
  if (seed == 16) {
 content = "(x_x)";
 name = "R I P Round";
 }
   if (seed == 17) {
 content = "[x_x]";
 name = "R I P Square";
 }

 return Trait(string(abi.encodePacked('<tspan dy="20" x="160" fill="', color.value, '">', content, '</tspan>')), name, color);
 }

 function getBody(uint256 seed, uint256 colorSeed) private pure returns (Trait memory) {
 Color memory color = getColor(colorSeed);
 string memory content;
 string memory name;
 if (seed == 10) {
 content = "|=[ARB]=|";
 name = "Arbitrum";
 }
 if (seed == 11) {
 content = "|=[XXX]=|";
 name = "BDSM";
 }
 if (seed == 12) {
 content = "(=[ETH]=)";
 name = "Ethereum";
 }
 if (seed == 13) {
 content = "|=(.)-(.)=|";
 name = "Tits";
 }
 if (seed == 14) {
 content = "(=(NFT)=)";
 name = "NFT";
 }
 if (seed == 15) {
 content = "|=[NPC]=|";
 name = "NPC";
 }

 return Trait(string(abi.encodePacked('<tspan dy="25" x="160" fill="', color.value, '">', content, '</tspan>')), name, color);
 }


 function getLegs(uint256 seed, uint256 colorSeed) private pure returns (Trait memory) {
 Color memory color = getColor(colorSeed);
 string memory content;
 string memory name;
 if (seed == 10) {
 content = "| | |";
 name = "Slim";
 }
 if (seed == 11) {
 content = "{ | }";
 name = "Tubes";
 }
 if (seed == 12) {
 content = "|~|~|";
 name = "Pockets Slim";
 }
 if (seed == 13) {
 content = "{~|~}";
 name = "Pockets Tubes";
 }
 if (seed == 14) {
 content = "(~|~)";
 name = "Pockets Comfortable";
 }
 if (seed == 15) {
 content = "( | )";
 name = "Comfortable";
 }
 if (seed == 16) {
 content = "! | !";
 name = "Shorts";
 }
  if (seed == 17) {
 content = "*!*";
 name = "Dick";
 }

 return Trait(string(abi.encodePacked('<tspan dy="25" x="160" fill="', color.value, '">', content, '</tspan>')), name, color);
 }

 function getFeet(uint256 seed, uint256 colorSeed) private pure returns (Trait memory) {
 Color memory color = getColor(colorSeed);
 string memory content;
 string memory name;
 uint256 y;
 if (seed == 10) {
 content = "== ==";
 name = "Crocs";
 y = 25;
 }
 if (seed == 11) {
 content = "~~ ~~";
 name = "Yeezy";
 y = 22;
 }

 return Trait(string(abi.encodePacked('<tspan dy="',y.toString(),'" x="160" fill="', color.value, '">', content, '</tspan>')), name, color);
 }

 function calculateColorCount(uint256[4] memory colors) private pure returns (string memory) {
 uint256 count;
 for (uint256 i = 0; i < 4; i++) {
 for (uint256 j = 0; j < 4; j++) {
 if (colors[i] == colors[j]) {
 count++;
 }
 }
 }

 if (count == 4) {
 return '4';
 }
 if (count == 6) {
 return '3';
 }
 if (count == 8 || count == 10) {
 return '2';
 }
 if (count == 16) {
 return '1';
 }

 return '0';
 }
}

