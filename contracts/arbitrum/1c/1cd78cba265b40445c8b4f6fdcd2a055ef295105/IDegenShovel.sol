// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;
import {IERC721AUpgradeable} from "./IERC721AUpgradeable.sol";

interface IDegenShovel is IERC721AUpgradeable {
    function mint(
        address to,
        uint256 quantity
    ) external returns (uint256 startTokenId);

    function burn(uint256 tokenId) external;
}

