pragma solidity ^0.8.0;

import "./base64.sol";
import "./Strings.sol";
/// @title NFTSVG
/// @notice Provides a function for generating an SVG associated with a Uniswap NFT
library WandMetadataSvg {
	using Strings for uint256;

	function generateSVGofTokenById(address owner, uint256 id, string memory core, string memory coreType, string memory wood, string memory maker, string memory length, string memory specialty, string memory symbol) internal pure returns (string memory) {
		string memory svg = string(abi.encodePacked(
		'<svg width="400" height="400" xmlns="http://www.w3.org/2000/svg"><style>.base { fill: white; font-family: serif; font-size: 18px; }.topright { fill: white; font-family: serif; font-size: 12px;}.symbol { fill: red; font-family: serif; font-size: 45px; }</style><rect width="100%" height="100%" fill="black"/>',
		'<text text-anchor="end" x="98%" y="4%" class="topright">#',
		id.toString(),
		'</text><text x="7%" y="15%" class="base">Wand Core:</text><text text-anchor="end" x="95%" y="15%" class="base" font-style = "italic">',
		core,
		'</text><text x="7%" y="25%" class="base">Core Type:</text><text text-anchor="end" x="95%" y="25%" class="base" font-style = "italic">',
		coreType,
		'</text><text x="7%" y="35%" class="base">Wood:</text><text text-anchor="end" x="95%" y="35%" class="base" font-style = "italic">',
		wood,
		'</text><text x="7%" y="45%" class="base">Length:</text><text text-anchor="end" x="95%" y="45%" class="base" font-style = "italic">'
		));

		svg = string(abi.encodePacked(
		svg,
		length,
		'</text><text x="7%" y="55%" class="base">Wandmaker:</text><text text-anchor="end" x="95%" y="55%" class="base" font-style = "italic">',
		maker,
		'</text><text x="7%" y="65%" class="base">Specialty:</text><text text-anchor="end" x="95%" y="65%" class="base" font-style = "italic">',
		specialty,
		'</text><text x="50%" y="85%" class="symbol" text-anchor="middle" font-style = "italic">',
		symbol,
		'</text></svg>'));
		return svg;
	}

	function tokenURI(address owner, uint256 tokenId, string[] memory attrs) internal pure returns (string memory) {
		string memory name = string(abi.encodePacked('Wand Item #',tokenId.toString()));

		string memory image = Base64.encode(bytes(generateSVGofTokenById(owner,tokenId,attrs[0],attrs[1],attrs[2],attrs[3],attrs[4],attrs[5],attrs[6])));

		return string(
			abi.encodePacked(
				'data:application/json;base64,',
				Base64.encode(
					bytes(
						abi.encodePacked(
							'{"name":"',
							name,

							'", "image": "',
							'data:image/svg+xml;base64,',
							image,
							'"}'
						)
					)
				)
			)
		);
	}
}
