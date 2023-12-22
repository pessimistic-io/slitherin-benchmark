// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Strings.sol";

contract CloudTrait is Ownable {
    using Strings for uint256;
    using Strings for address;
    using Strings for bool;

    string public baseTokenURI;

    enum Level {
        Beginner,
        Intermediate,
        Advanced
    }

    struct Trait {
        Level level;
        address owner;
        uint256 createdAt;
        uint256 lastClaim;
    }

    mapping(uint256 => Trait) public traits;
    mapping(address => bool) public admins;

    modifier onlyAdmin() {
        require(admins[msg.sender], "FBD: Caller is not an admin");
        _;
    }

    constructor() {}

    function addTrait(
        uint256 _tokenId,
        Level _level,
        address _owner
    ) external onlyAdmin {
        traits[_tokenId] = Trait(
            _level,
            _owner,
            block.timestamp,
            block.timestamp
        );
    }

    function setURI(string memory _baseTokenURI) external onlyAdmin {
        baseTokenURI = _baseTokenURI;
    }

    function setLastClaim(uint256 _tokenId) external onlyAdmin {
        traits[_tokenId].lastClaim = block.timestamp;
    }

    /***********************
        Owner function area
    ************************/

    function setAdmin(address _account, bool _value) external onlyOwner {
        admins[_account] = _value;
    }

    /***********************
        View function area
    ************************/

    /**
     * @notice return NFT metadata from tokenId
     * @param _tokenId is the id of token
     */
    function getMetadata(
        uint256 _tokenId
    ) external view returns (Trait memory) {
        return traits[_tokenId];
    }

    function attributeForTypeAndValue(
        string memory traitType,
        string memory value
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '{"trait_type":"',
                    traitType,
                    '","value":"',
                    value,
                    '"}'
                )
            );
    }

    /**
     * generates an array composed of all the individual traits and values
     * @param _tokenId the ID of the token to compose the metadata for
     * @return a JSON array of all of the attributes for given token ID
     */
    function compileAttributes(
        uint256 _tokenId
    ) public view returns (string memory) {
        string memory _traits;
        _traits = string(
            abi.encodePacked(
                attributeForTypeAndValue(
                    "Level",
                    checkUserLevel(traits[_tokenId].level)
                ),
                ",",
                string(
                    abi.encodePacked(
                        '{"trait_type":"',
                        "Minter",
                        '","value":"0x',
                        toAsciiString(traits[_tokenId].owner),
                        '"}'
                    )
                )
            )
        );
        return string(abi.encodePacked("[", _traits, "]"));
    }

    function tokenURI(uint256 _tokenId) public view returns (string memory) {
        Trait memory t = traits[_tokenId];

        string memory metadata = string(
            abi.encodePacked(
                '{"name": "',
                checkUserLevel(t.level),
                " Cloud #",
                _tokenId.toString(),
                '", "description": "Nimbus Cloud is a collection that gives its holders the possibility to collect passive income according to the level of the Cloud. In addition to the NFT, governance tokens are distributed. These tokens have a major importance in the protocol as they will allow to vote for the direction Nimbus Finance should take. It is particularly on the APR that these tokens will be important because every 24 hours a vote will be live for 12 hours to define the rewards distributed.", "image": "',
                baseTokenURI,
                checkUserLevel(t.level),
                ".png",
                '", "attributes":',
                compileAttributes(_tokenId),
                "}"
            )
        );

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    base64(bytes(metadata))
                )
            );
    }

    function checkUserLevel(
        Level userLevel
    ) public pure returns (string memory) {
        if (userLevel == Level.Beginner) {
            return "Stratos";
        } else if (userLevel == Level.Intermediate) {
            return "Cirrusia";
        } else if (userLevel == Level.Advanced) {
            return "Cumulonix";
        }
        return "Stratos";
    }

    /***BASE 64 - Written by Brech Devos */

    string internal constant TABLE =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    function base64(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";

        // load the table into memory
        string memory table = TABLE;

        // multiply by 4/3 rounded up
        uint256 encodedLen = 4 * ((data.length + 2) / 3);

        // add some extra buffer at the end required for the writing
        string memory result = new string(encodedLen + 32);

        assembly {
            // set the actual output length
            mstore(result, encodedLen)

            // prepare the lookup table
            let tablePtr := add(table, 1)

            // input ptr
            let dataPtr := data
            let endPtr := add(dataPtr, mload(data))

            // result ptr, jump over length
            let resultPtr := add(result, 32)

            // run over the input, 3 bytes at a time
            for {

            } lt(dataPtr, endPtr) {

            } {
                dataPtr := add(dataPtr, 3)

                // read 3 bytes
                let input := mload(dataPtr)

                // write 4 characters
                mstore(
                    resultPtr,
                    shl(248, mload(add(tablePtr, and(shr(18, input), 0x3F))))
                )
                resultPtr := add(resultPtr, 1)
                mstore(
                    resultPtr,
                    shl(248, mload(add(tablePtr, and(shr(12, input), 0x3F))))
                )
                resultPtr := add(resultPtr, 1)
                mstore(
                    resultPtr,
                    shl(248, mload(add(tablePtr, and(shr(6, input), 0x3F))))
                )
                resultPtr := add(resultPtr, 1)
                mstore(
                    resultPtr,
                    shl(248, mload(add(tablePtr, and(input, 0x3F))))
                )
                resultPtr := add(resultPtr, 1)
            }

            // padding with '='
            switch mod(mload(data), 3)
            case 1 {
                mstore(sub(resultPtr, 2), shl(240, 0x3d3d))
            }
            case 2 {
                mstore(sub(resultPtr, 1), shl(248, 0x3d))
            }
        }

        return result;
    }

    function toAsciiString(address x) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint(uint160(x)) / (2 ** (8 * (19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 * i] = char(hi);
            s[2 * i + 1] = char(lo);
        }
        return string(s);
    }

    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }
}

