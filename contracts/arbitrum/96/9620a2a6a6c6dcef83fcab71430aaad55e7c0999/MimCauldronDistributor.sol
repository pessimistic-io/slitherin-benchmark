// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./ERC20.sol";
import "./BoringERC20.sol";
import "./ICauldronV4.sol";
import "./IMimCauldronDistributor.sol";

contract MimCauldronDistributor is IMimCauldronDistributor {
    ERC20 public immutable mim;
    ICauldronV4 public immutable cauldron;

    constructor(ERC20 _mim, ICauldronV4 _cauldron) {
        mim = _mim;
        cauldron = _cauldron;
    }

    function distribute() external {
        mim.transfer(address(cauldron), mim.balanceOf(address(this)));
        cauldron.repayForAll(
            0, /* amount ignored when skimming */
            true
        );
    }
}

