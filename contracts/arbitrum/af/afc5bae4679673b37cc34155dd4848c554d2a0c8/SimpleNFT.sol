// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./ERC721.sol";
import "./ERC721Enumerable.sol";
import "./Ownable.sol";
import "./Strings.sol";

/// [MIT License]
/// @title Base64
/// @notice Provides a function for encoding some bytes in base64
/// @author Brecht Devos <brecht@loopring.org>
library Base64 {
    bytes internal constant TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    /// @notice Encodes some bytes to the base64 representation
    function encode(bytes memory data) internal pure returns (string memory) {
        uint256 len = data.length;
        if (len == 0) return "";

        // multiply by 4/3 rounded up
        uint256 encodedLen = 4 * ((len + 2) / 3);

        // Add some extra buffer at the end
        bytes memory result = new bytes(encodedLen + 32);
        bytes memory table = TABLE;

        assembly {
            let tablePtr := add(table, 1)
            let resultPtr := add(result, 32)
            for {
                let i := 0
            } lt(i, len) {
            } {
                i := add(i, 3)
                let input := and(mload(add(data, i)), 0xffffff)
                let out := mload(add(tablePtr, and(shr(18, input), 0x3F)))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(shr(12, input), 0x3F))), 0xFF))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(shr(6, input), 0x3F))), 0xFF))
                out := shl(8, out)
                out := add(out, and(mload(add(tablePtr, and(input, 0x3F))), 0xFF))
                out := shl(224, out)
                mstore(resultPtr, out)
                resultPtr := add(resultPtr, 4)
            }
            switch mod(len, 3)
            case 1 {
                mstore(sub(resultPtr, 2), shl(240, 0x3d3d))
            }
            case 2 {
                mstore(sub(resultPtr, 1), shl(248, 0x3d))
            }
            mstore(result, encodedLen)
        }
        return string(result);
    }
}

contract SimpleNFT is ERC721, ERC721Enumerable, Ownable {

    uint256 public constant MAX = 10000;

    constructor() ERC721("Warrens Army", "SOLDIER") {}

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            string(
                                abi.encodePacked(
                                    '{"name": "Soldier #',
                                    Strings.toString(tokenId),
                                    '", "description": "Warrens Anti-Crypto Army",'
                                    '"external_url": "https://warrensarmy.com",',
                                    '"image": "ipfs://QmX2uWtePU6mcq8fTv3b6gUCt8wUHM4SV4AgWm6xp9mn2V"',
                                    '}'
                                )
                            )
                        )
                    )
                )
            );
    }


    function mintSoldier(uint256 numberOfTokens) public {
        require(
            numberOfTokens > 0 && numberOfTokens <= 10,
            "Can only mint 10 tokens at a time"
        );
        require(
            (totalSupply() + numberOfTokens) <= MAX,
            "Cannot be more than 10k."
        );
        for (uint256 i = 0; i < numberOfTokens; i++) {
            uint256 mintIndex = totalSupply()+1;
            if (totalSupply() < MAX) {
                _safeMint(msg.sender, mintIndex);
            }
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 firstTokenId, uint256 batchSize)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._beforeTokenTransfer(from, to, firstTokenId, batchSize);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, ERC721Enumerable) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            interfaceId == type(IERC721Enumerable).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
