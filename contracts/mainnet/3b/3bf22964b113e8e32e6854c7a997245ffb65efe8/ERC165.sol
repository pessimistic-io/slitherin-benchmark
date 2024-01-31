// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {IERC165} from "./IERC165.sol";
import {LibDiamond} from "./LibDiamond.sol";

/**
 * @title ERC165 implementation
 */
abstract contract ERC165 is IERC165 {
    /**
     * @inheritdoc IERC165
     */
    function supportsInterface(bytes4 _interfaceId)
        external
        view
        override
        returns (bool)
    {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return ds.supportedInterfaces[_interfaceId];
    }
}

