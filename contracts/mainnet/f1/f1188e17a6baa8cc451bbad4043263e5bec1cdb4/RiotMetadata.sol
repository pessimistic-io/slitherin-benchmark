// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

// Note     : On-chain metadata for Riot Pass
// Dev      : 3L33T

/*************************************************************
    ████████████████████████████████████████████████████████████████████████████████
    ████████████████████████████████████████████████████████████████████████████████
    ████████████████████████████████████████████████████████████████████████████████
    ████████████████████████████████████████████████████████████████████████████████
    ████████████████████████████████████████████████████████████████████████████████
    ████████████████████████████████████████████████████████████████████████████████
    ██████████████████████████████████▀▀█▀█████▀▀▀██████████████████████████████████
    █████████████████████████████▀▀███  " ████   ▐███▀ ▀▀███████████████████████████
    ████████████████████████▀▀███▄ ▐██µ   ███▌ ▐  ██▀  ▀ ▐██████████████████████████
    ██████████████████████▌ █  ▀██▄ ▀██ ▐▄ ██  ▄  ██  ▌ ████` ██████████████████████
    ███████████████████████▄  ▄  ██▄▄██████████████▄▄█ ╓██▀ ,███████████████████████
    █████████████████████████  ▀▄▄█████▀▀▀▀▀█▀▀▀▀████████  ▄████████████████████████
    ██████████████████▄█ ██████████▀▀      ▀█▄      ▀▀████████▄`█▀██████████████████
    █████████████████ ███ ███████▀*      ▀█▐█▌▄█▀⌐  ,▀ ▀██████▐▄██ █████████████████
    █████████████████▐▀█▀▄██████    ▄  ▐█████████▄ ¬    ▐█████ ██▀█▐████████████████
    ████████████████▀▌ ████████     `▀    ▐███ `   ╛     ██████▄█ ██████████████████
    ███████████████`███ ███████         ,██ ▀█▄ ▄       ▄███████▀▌▄▄▐███████████████
    ███████████████▐███ ██████▌▐  ,ⁿ   "▀   `▀▀▀▀   `* , ▐██████ ███▌███████████████
    ████████████████▌▐████████▌ ¥  ▄██████^"▌ⁿ▄▄█████▄r▌ ▐███████▐▌j▄███████████████
    ████████████████▌▐▀███████▌ⁿ" ████████  ▌ ████████ ▀▀▐████████▌]████████████████
    ███████████████ ███ ██████▌,P '▀█████▀▐███▀██████▀ ▀,▐██████▌▄██ ███████████████
    ████████████████'█▀▄██████▌   ▄'  ═"  ▐███  ⁿ   ▀    ███████ ███▐███████████████
    ██████████████████▌"█▀█████  ▀        ████       '▄  ████████ █▄████████████████
    ██████████████████▐███▄███████████,,   ▀▌▌1╒╒╔███████████▀▄█▄███████████████████
    ███████████████████▀█▀▀█████████████▐▀▀▌▌▌██▐███████████▌████▄██████████████████
    ██████████████████████▄ ████▀▀███████████████████▀▀▀████▀ █▌▄███████████████████
    ██████████████████████████▀  ▀ ██▀███████████▀▀█▌ ▀▀▀███████████████████████████
    █████████████████████████▌ ▄ ▐██ ▄█   ▐█  ▄█⌐ ▌ ███▀▌ ██████████████████████████
    ███████████████████████████▄███ ╒██ █ ]█⌐ ▄██  ▄ ██▄▄███████████████████████████
    ███████████████████████████████▄██▌ ▀ ██▌ ▀███▄█▄███████████████████████████████
    ████████████████████████████████████████████████████████████████████████████████
    ████████████████████████████████████████████████████████████████████████████████
    ████████████████████████████████████████████████████████████████████████████████
    ████████████████████████████████████████████████████████████████████████████████
    ████████████████████████████████████████████████████████████████████████████████
    ████████████████████████████████████████████████████████████████████████████████
                                                                                                                    
*************************************************************/

import "./Base64.sol";

error NotOwner();
error NoQuantitiesAndPoints();

contract RiotMetadata {
    string public desc =
        "Hikari Riot Pass is a membership pass by Hikari Riders backed by NFT technology.\\nThis pass will grant the holder access to perks within the Hikari Riders ecosystem.";
    string public animURL = "ar://BfJC-XcqUalYqEkQcOh0cSD6DCNKXu9qBmYktPQUpU8";
    string public image = "ar://PPhGPCcE445tddFMZYzXNIU_Rl-wbz0Gc_PZ76waNuY";
    address public owner;

    mapping(uint256 => uint256) public points;

    constructor() {
        owner = msg.sender;
    }

    event newDesc(string desc);
    event newAnimURL(string animURL);
    event newImage(string image);
    event pointsUpdated(uint256 indexed id, uint256 points);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function setDescription(string calldata _desc) external onlyOwner {
        desc = _desc;
        emit newDesc(desc);
    }

    function setAnimationURL(string calldata _animURL) external onlyOwner {
        animURL = _animURL;
        emit newAnimURL(animURL);
    }

    function setImageURL(string calldata _image) external onlyOwner {
        image = _image;
        emit newImage(image);
    }

    function updatePoints(uint256 _id, uint256 _points) external onlyOwner {
        points[_id] = _points;
        emit pointsUpdated(_id, _points);
    }

    function updatePointsBatch(
        uint256[] calldata _ids,
        uint256[] calldata _points
    ) external onlyOwner {
        uint256 idl = _ids.length;
        uint256 ptl = _points.length;

        if (ptl != idl) revert NoQuantitiesAndPoints();

        for (uint256 i = 0; i < idl; ) {
            points[_ids[i]] = _points[i];
            unchecked {
                ++i;
            }
        }
        delete ptl;
        delete idl;
    }

    function fetchMetadata(uint256 _tokenID)
        external
        view
        returns (string memory)
    {
        string memory _name = "Hikari Riot Pass #";
        string memory _desc = desc;
        string memory _image = image;
        string memory _animURL = animURL;

        string[7] memory attr;

        attr[0] = '{"trait_type":"ID","value":"';
        attr[1] = toString(_tokenID);
        attr[2] = '"},{"trait_type":"Supply","value":2500},';
        attr[3] = '{"trait_type":"Type","value":"Pass"},';
        attr[4] = '{"trait_type":"Point","value":';
        attr[5] = toString(points[_tokenID]);
        attr[6] = "}";

        string memory _attr = string(
            abi.encodePacked(
                attr[0],
                attr[1],
                attr[2],
                attr[3],
                attr[4],
                attr[5],
                attr[6]
            )
        );

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "',
                        _name,
                        toString(_tokenID),
                        '", "description": "',
                        _desc,
                        '", "image": "',
                        _image,
                        '", "animation_url": "',
                        _animURL,
                        '", "attributes": [',
                        _attr,
                        "]",
                        "}"
                    )
                )
            )
        );
        string memory output = string(
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
}
