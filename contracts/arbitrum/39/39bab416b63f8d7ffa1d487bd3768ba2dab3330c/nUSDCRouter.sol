// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./ReentrancyGuard.sol";

import {IERC20} from "./IERC20.sol";
import {IRewardTracker} from "./IRewardTracker.sol";
import {Governable} from "./Governable.sol";

interface VaultAPI is IERC20 {
    function deposit(uint256 amount, address recipient) external returns (uint256);

    function withdraw(uint256 maxShares, address recipient, uint256 maxLoss) external returns (uint256);
}

contract nUSDCRouter is ReentrancyGuard, Governable {
    address public vault;
    address public want;
    address public stakedNeutraUsdcTracker;

    event StakeNeutraUsdc(address fundingAccount, address account, uint256 amount);
    event UnstakeNeutraUsdc(address fundingAccount, address account, uint256 amount, uint256 maxLoss);

    constructor (
        address _vault,
        address _want,
        address _stakedNeutraUsdcTracker
    ) {
        vault = _vault;
        want = _want;
        stakedNeutraUsdcTracker = _stakedNeutraUsdcTracker;

        IERC20(_want).approve(_vault, type(uint256).max);
        VaultAPI(_vault).approve(_stakedNeutraUsdcTracker, type(uint256).max);
    }

    function depositAndStakeNeutraUsdc(address _recipient, uint256 _amount) external returns (uint256) {
        require(_amount > 0, "invalid _amount");

        IERC20(want).transferFrom(msg.sender, address(this), _amount);
        uint256 share = VaultAPI(vault).deposit(_amount, address(this));
        IRewardTracker(stakedNeutraUsdcTracker).stakeForAccount(address(this), _recipient, vault, share);

        emit StakeNeutraUsdc(msg.sender, _recipient, _amount);

        return share;
    }

    function unstakeAndRedeemNeutraUsdc(
        address _recipient,
        uint256 _amount,
        uint256 _maxLoss
    ) external returns (uint256) {
        require(_amount > 0, "invalid _amount");

        IRewardTracker(stakedNeutraUsdcTracker).unstakeForAccount(msg.sender, vault, _amount, address(this));
        uint256 amountOut = VaultAPI(vault).withdraw(_amount, _recipient, _maxLoss);

        emit UnstakeNeutraUsdc(msg.sender, _recipient, _amount, _maxLoss);

        return amountOut;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).transfer(_account, _amount);
    }

    function claim() external nonReentrant {
        IRewardTracker(stakedNeutraUsdcTracker).claimForAccount(msg.sender, msg.sender);
    }
}

