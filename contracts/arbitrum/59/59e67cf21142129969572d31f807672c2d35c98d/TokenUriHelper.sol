pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

import "./Strings.sol";

/** 
 * Tales of Elleria
*/
contract TokenUriHelper {
    using Strings for uint256;

    function GetTokenUri(uint256 _tokenId) external pure returns (string memory) {
        return string(abi.encodePacked('https://wall.talesofelleria.com/api/equipment/',
        Strings.toString(_tokenId)));
    }
}
