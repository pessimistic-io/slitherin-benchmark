// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import { OnlyWhitelisted } from "./OnlyWhitelisted.sol";
import { IERC20 } from "./IERC20.sol";
import { IERC20Metadata } from "./extensions_IERC20Metadata.sol";
import { IStakeValuator, PriceOracle } from "./IStakeValuator.sol";
import { IStakingPerRewardController } from "./IStakingPerRewardController.sol";
import { IStakingPerTierController } from "./IStakingPerTierController.sol";
import { SafeERC20 } from "./SafeERC20.sol";


contract MultiStakingConverter is OnlyWhitelisted, IStakingPerRewardController, IStakingPerTierController {
    IStakeValuator public stakingInstance;
    uint256 public priceDecimals;
    IERC20Metadata public target;
    
    constructor(IStakeValuator _stakingInstance, uint256 _priceDecimals, IERC20Metadata _target) {
        require(address(_stakingInstance) != address(0), "Invalid staking contract address");
        stakingInstance = _stakingInstance;
        priceDecimals = _priceDecimals;
        target = _target;
    }

    // core functionality, converting from the staking token to the base token
    function getVestedTokens(address user) external override view returns (uint256) {
        return _toBaseToken(stakingInstance.getVestedTokens(user));
    }
    function getVestedTokensAtSnapshot(address user, uint256 blockNumber) external override view returns (uint256) {
        return _toBaseTokenAtSnapshot(stakingInstance.getVestedTokensAtSnapshot(user, blockNumber), blockNumber);
    }

    function _toBaseTokenAtSnapshot(uint256 amount, uint256 blockNumber) public view returns (uint256) {
        uint256 price = stakingInstance.getValueAtSnapshot(IERC20(target), blockNumber);
        return calculateInverseAmount(amount, price);
    }
    function _toBaseToken(uint256 amount) public view returns (uint256) {
        uint256 price = stakingInstance.getValueAtSnapshot(IERC20(target), block.number);
        return calculateInverseAmount(amount, price);
    }

    function calculateInverseAmount(uint256 amount, uint256 price) public view returns (uint256) {
        // we have the baseToken*price amount, calculate the inverse
        uint256 inverseAmount = (amount * 10**target.decimals()) / price;
        return inverseAmount;
    }

    // unaltered proxy calls
    function stakeFor(address _account, uint256 _amount) external {
        // collect the tokens
        IERC20 baseToken = stakingInstance.token();
        uint256 allowance = baseToken.allowance(msg.sender, address(this));
        require(allowance >= _amount, "Check the token allowance");
        SafeERC20.safeTransferFrom(baseToken, msg.sender, address(this), _amount);

        // stake the tokens onward
        baseToken.approve(address(stakingInstance), _amount);
        stakingInstance.stakeFor(_account, _amount);
    }
    function token() external view override returns (IERC20) {
        return stakingInstance.token();
    }
    function snapshot() external override onlyWhitelisted {
        stakingInstance.snapshot();
    }
    function getStakersCount() external override view returns (uint256) {
        return stakingInstance.getStakersCount();
    }
    function getStakers(uint256 idx) external override view returns (address) {
        return stakingInstance.getStakers(idx);
    }
}

