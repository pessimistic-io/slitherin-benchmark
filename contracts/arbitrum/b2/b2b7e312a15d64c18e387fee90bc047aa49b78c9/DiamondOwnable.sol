// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { LibDiamond } from "./LibDiamond.sol";
import { IERC173 } from "./IERC173.sol";
import { WithModifiers } from "./LibStorage.sol";

contract DiamondOwnable is IERC173, WithModifiers {
    function transferOwnership(address account) external onlyOwner {
        LibDiamond.setContractOwner(account);
    }

    function owner() external view override returns (address) {
        return LibDiamond.contractOwner();
    }
}

