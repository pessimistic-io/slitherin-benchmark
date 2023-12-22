// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {Ownable} from "./Ownable.sol";
import {DiscoveryCue} from "./DiscoveryCue.sol";

contract DiscoveryCueBatchMint is Ownable {
    DiscoveryCue public immutable cue;

    constructor(address cue_) {
        cue = DiscoveryCue(cue_);
    }

    function mint(address wallet, uint256 cueType) external onlyOwner {
        cue.mint(wallet, cueType);
    }

    function mintBatch(address[] calldata wallets, uint256 cueType) external onlyOwner {
        for (uint256 i = 0; i < wallets.length; ) {
            cue.mint(wallets[i], cueType);
            unchecked {
                i++;
            }
        }
    }
}

