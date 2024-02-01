// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./SSTORE2.sol";
import "./Ownable.sol";

contract PunkFont is Ownable {
	struct Font {
		address[] pieces;
	}
	mapping(uint256 => Font) private fonts;
	mapping(uint256 => bool) private locked;

	constructor() Ownable() {}

	modifier unlocked(uint256 fontId) {
		require(!locked[fontId], "cannot modify locked font");
		_;
	}

	/// @notice Adds a font (only owner)
	/// @param id The font index
	/// @param pieces the amount of pieces the font is made of (each must be < 24 kB)
	function initFont(
		uint256 id,
		uint256 pieces
	) public unlocked(id) onlyOwner {
		delete fonts[id].pieces;
		fonts[id].pieces = new address[](pieces);
	}

	/// @notice Adds data to a font (since setting the whole thing at once may violate gas limits)
	/// @param id The font index
	/// @param piece The index of the piece to be set.
	/// @param base64 A base64-encoded font piece
	function setFontPiece(
		uint256 id,
		uint256 piece,
		bytes memory base64
	) public unlocked(id) onlyOwner {
		// string memory previousFont = fonts[id];
		require(
			piece < fonts[id].pieces.length,
			"piece out of bounds for font"
		);
		fonts[id].pieces[piece] = SSTORE2.write(base64);
	}

	/// @notice Retrieves a font
	/// @param id The font index
	/// @return A base64 encoded font
	function getFont(uint256 id) external view returns (string memory) {
		bytes memory b;
		for (uint piece = 0; piece < fonts[id].pieces.length; piece++) {
			b = bytes.concat(b, SSTORE2.read(fonts[id].pieces[piece]));
		}
		return string(b);
	}

	/// @notice Lock a font
	/// @param id The font index
	function lockFont(uint256 id) public unlocked(id) onlyOwner {
		locked[id] = true;
	}
}

