pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

import "./Ownable.sol";
import "./IEllerianHeroUpgradeable.sol";
import "./Strings.sol";

/** 
 * Tales of Elleria
*/
contract TokenUriHelper is Ownable {
    using Strings for uint256;

    function GetTokenUri(uint256 _tokenId) external pure returns (string memory) {
        return string(abi.encodePacked('https://wall.talesofelleria.com/api/hero/',
        Strings.toString(_tokenId)));
    }
}
