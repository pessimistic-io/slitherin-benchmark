// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IPlayerCardDescriptor} from "./IPlayerCardDescriptor.sol";
import {IPlayerCard} from "./IPlayerCard.sol";
import {Base64} from "./Base64.sol";
import {LibString} from "./LibString.sol";

contract PlayerCardDescriptor is IPlayerCardDescriptor {
    string public constant BASE_IMAGE_URL = "https://potionpanic.gg/cards/";

    function tokenURI(IPlayerCard, uint256 id) public pure returns (string memory) {
        string memory imageURL = string(abi.encodePacked(BASE_IMAGE_URL, LibString.toString(id)));

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        abi.encodePacked(
                            '{"name":"Potion Panic Card #',
                            LibString.toString(id),
                            '", "description":"Potion Panic Card", "image": "',
                            imageURL,
                            '"}'
                        )
                    )
                )
            );
    }
}

