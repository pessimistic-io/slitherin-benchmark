// SPDX-License-Identifier: Apache-2.0
/*          

//      _   ___ _____ ___    _   _    _____  __   ___ _    ___  _   _ ___  
//     /_\ / __|_   _| _ \  /_\ | |  |_ _\ \/ /  / __| |  / _ \| | | |   \ 
//    / _ \\__ \ | | |   / / _ \| |__ | | >  <  | (__| |_| (_) | |_| | |) |
//   /_/ \_\___/ |_| |_|_\/_/ \_\____|___/_/\_\  \___|____\___/ \___/|___/ 
// 
//   D·M                                                                                                                                                                                      
*/

pragma solidity ^0.8.0;

import "./ERC721Drop.sol";
import "./Base64.sol";

contract AstralixContract is ERC721Drop {
    constructor(
        string memory _name,
        string memory _symbol,
        address _royaltyRecipient,
        uint128 _royaltyBps,
        address _primarySaleRecipient
    )
        ERC721Drop(
            _name,
            _symbol,
            _royaltyRecipient,
            _royaltyBps,
            _primarySaleRecipient
        )
    {}

    // Mapping from owner to list of owned token IDs
    mapping(address => mapping(uint256 => uint256)) private _ownedTokens;

    // Mapping from token ID to index of the owner tokens list
    mapping(uint256 => uint256) private _ownedTokensIndex;

    // Array with all token ids, used for enumeration
    uint256[] private _allTokens;

    // Mapping from token id to position in the allTokens array
    mapping(uint256 => uint256) private _allTokensIndex;

    string[] private firstrow = [
        "11 00 11 00 01 00",
        "00 00 00 10 00 10",
        "00 11 00 11 01 01",
        "10 00 00 11 11 01",
        "01 10 11 01 01 10",
        "10 00 11 11 11 10",
        "00 01 10 01 10 11",
        "00 01 10 10 10 00",
        "10 01 10 11 01 01",
        "10 11 00 11 00 10",
        "01 10 01 11 11 01",
        "00 11 00 00 00 00",
        "11 00 00 01 00 10",
        "11 10 10 11 11 01",
        "01 10 00 01 00 11",
        "10 10 10 00 00 11",
        "01 11 01 11 11 01",
        "11 10 11 10 11 00",
        "01 01 10 11 10 00",
        "10 10 00 00 11 01"
    ];

    string[] private secondrow = [
        "11 00 01 01 00 00",
        "10 00 01 01 00 11",
        "00 10 11 01 10 10",
        "10 11 11 00 11 11",
        "11 01 11 00 01 11",
        "00 10 00 10 00 11",
        "01 01 00 10 01 11",
        "00 01 00 11 11 11",
        "10 11 11 11 01 10",
        "10 01 10 01 01 00",
        "10 01 10 01 11 11",
        "10 01 01 01 01 11",
        "01 01 11 01 01 01",
        "11 00 11 10 00 10",
        "01 11 01 11 11 00",
        "00 11 00 10 11 10",
        "01 11 11 10 00 11",
        "00 00 01 11 11 01",
        "11 11 10 11 10 10",
        "10 11 00 11 10 00"
    ];

    string[] private thirdrow = [
        "10 00 00 11 10 00",
        "11 10 10 10 11 00",
        "01 00 11 10 11 11",
        "01 00 10 11 00 01",
        "01 10 11 11 00 11",
        "11 10 01 00 10 10",
        "00 10 01 01 11 10",
        "11 01 01 11 11 00",
        "11 10 00 10 00 00",
        "11 10 11 10 00 10",
        "00 11 01 01 00 10",
        "01 11 00 01 10 01",
        "00 11 01 11 11 00",
        "01 00 00 00 11 11",
        "10 10 01 11 01 01",
        "11 11 01 11 00 00",
        "11 11 01 10 01 11",
        "10 11 01 01 11 01",
        "00 01 11 11 11 11",
        "00 10 01 00 00 10"
    ];

    string[] private fourthrow = [
        "10 11 00 11 10 00",
        "11 01 10 01 11 10",
        "11 11 00 11 00 11",
        "00 11 10 10 11 00",
        "00 11 01 10 01 01",
        "10 10 11 11 11 00",
        "00 01 01 10 10 11",
        "00 00 00 11 11 11",
        "11 01 11 00 10 00",
        "11 10 01 00 00 10",
        "10 00 00 00 01 01",
        "00 00 00 10 00 10",
        "10 00 10 01 11 10",
        "01 00 10 00 01 10",
        "10 00 10 01 01 10",
        "11 00 01 01 11 00",
        "01 10 01 11 01 11",
        "01 11 01 10 00 11",
        "01 00 11 10 11 10",
        "00 10 10 01 10 00"
    ];

    string[] private fifthrow = [
        "00 11 10 10 10 00",
        "01 00 11 11 00 11",
        "10 11 10 01 11 00",
        "00 01 11 01 00 10",
        "11 10 01 10 10 01",
        "10 11 11 11 01 11",
        "00 01 11 10 00 01",
        "11 10 10 10 01 01",
        "11 10 11 10 01 11",
        "00 01 11 01 00 11",
        "10 01 01 00 00 00",
        "10 11 01 11 10 00",
        "01 01 00 11 11 00",
        "10 00 11 11 00 01",
        "11 00 10 10 01 11",
        "00 00 10 10 11 11",
        "10 11 11 10 00 11",
        "11 11 10 10 11 10",
        "11 11 10 00 01 01",
        "01 01 10 11 00 00"
    ];

    string[] private sixthrow = [
        "10 10 01 00 11 10",
        "00 00 01 00 00 00",
        "00 10 11 11 00 11",
        "01 00 11 01 11 00",
        "11 00 10 00 11 00",
        "10 00 00 11 11 10",
        "11 10 11 00 01 10",
        "01 01 11 11 00 10",
        "01 11 10 01 00 11",
        "00 00 00 10 11 10",
        "11 01 00 11 00 11",
        "10 01 10 11 11 01",
        "10 11 00 10 00 01",
        "01 00 00 01 11 11",
        "10 10 01 10 10 01",
        "01 11 00 10 10 10",
        "11 01 11 00 11 11",
        "11 00 00 10 00 01",
        "01 10 10 01 00 00",
        "01 00 01 01 00 10"
    ];

    function pluck(
        uint256 tokenId,
        string memory keyPrefix,
        string[] memory sourceArray
    ) internal pure returns (string memory) {
        uint256 rand = random(
            string(abi.encodePacked(keyPrefix, toString(tokenId)))
        );
        string memory output = sourceArray[rand % sourceArray.length];
        return output;
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        string[13] memory parts;

        parts[
            0
        ] = '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 700 700"><style>.base { fill: #fff; font-family: sans-serif; font-size: 22px; font-weight: bold;}</style><rect width="100%" height="100%" fill="#1e293b" /><defs><linearGradient id="g1" x1="451.3" y1="254.7" x2="602.2" y2="435.5" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#312e81"/><stop offset="1" stop-color="#4b43d9"/></linearGradient><linearGradient id="g2" x1="-231.1" y1="324.6" x2="68.4" y2="-109.1" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#534be6"/><stop offset="1" stop-color="#777df4"/></linearGradient></defs><style>.s0 { fill: url(#g1) } .s1 { fill: #1e1b4b } .s2 { fill: url(#g2) } .s3 { fill: #a5b4fc } </style><g id="Layer 1" transform="translate(400,30) scale(0.50,0.50)"><g id="&lt;Clip Group&gt;"><g id="&lt;Clip Group&gt;"><path id="&lt;Path&gt;" class="s0" d="m472.2 335.1c-197.3-239.1-469.3 132.5-469.3 132.5 5 5.3 18.2 5.5 40.5 5.5h226.5 227.7c52.5-1.2 49.8-7.9 26.5-48z"/></g><path id="&lt;Path&gt;" class="s1" d="m472.2 335.1c-197.3-239.1-469.3 132.5-469.3 132.5 5 5.3 18.2 5.5 40.5 5.5h132.4c0-0.1 86.1-284.4 296.4-138z"/><g id="&lt;Clip Group&gt;"><path id="&lt;Path&gt;" class="s2" d="m2.9 467.6c0 0 272-371.6 469.3-132.5l-61.3-106.2-113.9-197.2c-27.3-44.9-31.7-39.2-54.8 1l-113.3 196.2-113.8 197.2c-13.2 24-17.6 35.7-12.2 41.5z"/></g><path id="&lt;Path&gt;" class="s3" d="m89.4 297.4c154.5-249.6 254.9-169.8 296.5-111.7l-88.9-154c-27.3-44.9-31.7-39.2-54.8 1l-113.3 196.2-39.5 68.4z"/><path id="&lt;Path&gt;" class="s3" d="m2.9 467.6c0 0 272-371.6 469.3-132.5l-8.1-14c-200.2-221.8-461.2 146.5-461.2 146.5z"/></g></g><text x="50" y="460" class="base">';

        parts[1] = pluck(tokenId, "FIRSTROW", firstrow); //getFirst(tokenId);

        parts[2] = '</text><text x="50" y="498" class="base">';

        parts[3] = pluck(tokenId, "SECONDROW", secondrow); //getSecond(tokenId);

        parts[4] = '</text><text x="50" y="536" class="base">';

        parts[5] = pluck(tokenId, "THIRDROW", thirdrow); //getThird(tokenId);

        parts[6] = '</text><text x="50" y="574" class="base">';

        parts[7] = pluck(tokenId, "FOURTHROW", fourthrow); //getFourth(tokenId);

        parts[8] = '</text><text x="50" y="612" class="base">';

        parts[9] = pluck(tokenId, "FIFTHROW", fifthrow); //getFifth(tokenId);

        parts[10] = '</text><text x="50" y="650" class="base">';

        parts[11] = pluck(tokenId, "SIXTHROW", sixthrow); //getSixth(tokenId);

        parts[12] = "</text></svg>";

        string memory output = string(
            abi.encodePacked(
                parts[0],
                parts[1],
                parts[2],
                parts[3],
                parts[4],
                parts[5],
                parts[6]
            )
        );
        output = string(
            abi.encodePacked(
                output,
                parts[7],
                parts[8],
                parts[9],
                parts[10],
                parts[11],
                parts[12]
            )
        );

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "Astralix Mining Slot ',
                        toString(tokenId),
                        '", "description": "This NFT is soulbounded to a Bitcoin mining rig.", "image": "data:image/svg+xml;base64,',
                        Base64.encode(bytes(output)),
                        '"}'
                    )
                )
            )
        );
        output = string(
            abi.encodePacked("data:application/json;base64,", json)
        );

        return output;
    }

    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT license
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function random(string memory input) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(input)));
    }

    // function getFirst(uint256 tokenId) public view returns (string memory) {
    //     return pluck(tokenId, "FIRSTROW", firstrow);
    // }

    // function getSecond(uint256 tokenId) public view returns (string memory) {
    //     return pluck(tokenId, "SECONDROW", secondrow);
    // }

    // function getThird(uint256 tokenId) public view returns (string memory) {
    //     return pluck(tokenId, "THIRDROW", thirdrow);
    // }

    // function getFourth(uint256 tokenId) public view returns (string memory) {
    //     return pluck(tokenId, "FOURTHROW", fourthrow);
    // }

    // function getFifth(uint256 tokenId) public view returns (string memory) {
    //     return pluck(tokenId, "FIFTHROW", fifthrow);
    // }

    // function getSixth(uint256 tokenId) public view returns (string memory) {
    //     return pluck(tokenId, "SIXTHROW", sixthrow);
    // }

    /**
     * @dev token should always start from 1 in order to make Enumerable work properly
     */
    function _startTokenId() internal view virtual override returns (uint256) {
        return 1;
    }

    /**
     * @dev See {IERC721Enumerable-tokenOfOwnerByIndex}.
     */
    function tokenOfOwnerByIndex(
        address owner,
        uint256 index
    ) public view returns (uint256) {
        require(index < ERC721A.balanceOf(owner), "owner index out of bounds");
        return _ownedTokens[owner][index];
    }

    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual override {
        super._beforeTokenTransfers(from, to, startTokenId, quantity);
        for (uint index = 0; index < quantity; index++) {
            uint tokenId = startTokenId + index;
            if (from == address(0)) {
                _addTokenToAllTokensEnumeration(tokenId);
            } else if (from != to) {
                _removeTokenFromOwnerEnumeration(from, tokenId, index);
            }
            if (to == address(0)) {
                _removeTokenFromAllTokensEnumeration(tokenId);
            } else if (to != from) {
                _addTokenToOwnerEnumeration(to, tokenId, index);
            }
        }
    }

    /**
     * @dev Private function to add a token to this extension's ownership-tracking data structures.
     * @param to address representing the new owner of the given token ID
     * @param tokenId uint256 ID of the token to be added to the tokens list of the given address
     */
    function _addTokenToOwnerEnumeration(
        address to,
        uint256 tokenId,
        uint256 index
    ) private {
        uint256 length = ERC721A.balanceOf(to) + index;
        _ownedTokens[to][length] = tokenId;
        _ownedTokensIndex[tokenId] = length;
    }

    /**
     * @dev Private function to add a token to this extension's token tracking data structures.
     * @param tokenId uint256 ID of the token to be added to the tokens list
     */
    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        _allTokensIndex[tokenId] = _allTokens.length;
        _allTokens.push(tokenId);
    }

    /**
     * @dev Private function to remove a token from this extension's ownership-tracking data structures. Note that
     * while the token is not assigned a new owner, the `_ownedTokensIndex` mapping is _not_ updated: this allows for
     * gas optimizations e.g. when performing a transfer operation (avoiding double writes).
     * This has O(1) time complexity, but alters the order of the _ownedTokens array.
     * @param from address representing the previous owner of the given token ID
     * @param tokenId uint256 ID of the token to be removed from the tokens list of the given address
     */
    function _removeTokenFromOwnerEnumeration(
        address from,
        uint256 tokenId,
        uint256 index
    ) private {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = ERC721A.balanceOf(from) - index + 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];

            _ownedTokens[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete _ownedTokensIndex[tokenId];
        delete _ownedTokens[from][lastTokenIndex];
    }

    /**
     * @dev Private function to remove a token from this extension's token tracking data structures.
     * This has O(1) time complexity, but alters the order of the _allTokens array.
     * @param tokenId uint256 ID of the token to be removed from the tokens list
     */
    function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
        // To prevent a gap in the tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _allTokens.length - 1;
        uint256 tokenIndex = _allTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary. However, since this occurs so
        // rarely (when the last minted token is burnt) that we still do the swap here to avoid the gas cost of adding
        // an 'if' statement (like in _removeTokenFromOwnerEnumeration)
        uint256 lastTokenId = _allTokens[lastTokenIndex];

        _allTokens[tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
        _allTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index

        // This also deletes the contents at the last position of the array
        delete _allTokensIndex[tokenId];
        _allTokens.pop();
    }
}

