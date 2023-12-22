// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import { ERC20 } from "./ERC20.sol";
import { MintableERC20 } from "./MintableERC20.sol";
import { RadpieReceiptToken } from "./RadpieReceiptToken.sol";
import { BaseRewardPoolV3 } from "./BaseRewardPoolV3.sol";

library RadpieFactoryLib {
    function createERC20(string memory name_, string memory symbol_) public returns (address) {
        ERC20 token = new MintableERC20(name_, symbol_);
        return address(token);
    }

    function createReceipt(
        uint8 _decimals,
        address _stakeToken,
        address _radiantStaking,
        address _masterRadpie,
        string memory _name,
        string memory _symbol
    ) public returns (address) {
        ERC20 token = new RadpieReceiptToken(
            _decimals,
            _stakeToken,
            _radiantStaking,
            _masterRadpie,
            _name,
            _symbol
        );
        return address(token);
    }

    function createRewarder(
        address _receiptToken,
        address mainRewardToken,
        address _masterRadpie,
        address _rewardQueuer
    ) external returns (address) {
        BaseRewardPoolV3 _rewarder = new BaseRewardPoolV3(
            _receiptToken,
            mainRewardToken,
            _masterRadpie,
            _rewardQueuer
        );
        return address(_rewarder);
    }
}

