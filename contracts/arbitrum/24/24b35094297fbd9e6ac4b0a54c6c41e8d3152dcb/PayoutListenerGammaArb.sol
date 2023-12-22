// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./PayoutListener.sol";
import "./SolidLizard.sol";
import "./Sterling.sol";
import "./Arbiswap.sol";

contract PayoutListenerGammaArb is PayoutListener {

    IERC20 public rebaseToken;

    address[] public solidLizardPools;
    address[] public solidLizardBribes; // not used

    address[] public sterlingPools;
    address public sterlingWallet;

    address[] public arbiswapPools; // not used
    address public arbiswapWallet; // not used

    address public rewardWallet;

    // ---  events

    event RebaseTokenUpdated(address rebaseToken);
    event RewardWalletUpdated(address wallet);
    event RewardWalletSend(uint256 amount);

    event SolidLizardPoolsUpdated(address[] pools);

    event SterlingPoolsUpdated(address[] pools);
    event SterlingWalletUpdated(address wallet);
    event SterlingSkimReward(address pool, address wallet, uint256 amount);

    // --- setters

    function setRebaseToken(address _rebaseToken) external onlyAdmin {
        require(_rebaseToken != address(0), "Zero address not allowed");
        rebaseToken = IERC20(_rebaseToken);
        emit RebaseTokenUpdated(_rebaseToken);
    }

    function setSolidLizardPools(address[] calldata _pools) external onlyAdmin {
        solidLizardPools = _pools;
        emit SolidLizardPoolsUpdated(_pools);
    }

    function setSterlingPools(address[] calldata _pools) external onlyAdmin {
        sterlingPools = _pools;
        emit SterlingPoolsUpdated(_pools);
    }

    function setSterlingWallet(address _wallet) external onlyAdmin {
        require(_wallet != address(0), "Zero address not allowed");
        sterlingWallet = _wallet;
        emit SterlingWalletUpdated(_wallet);
    }

    function setRewardWallet(address _wallet) external onlyAdmin {
        require(_wallet != address(0), "Zero address not allowed");
        rewardWallet = _wallet;
        emit RewardWalletUpdated(_wallet);
    }


    // ---  constructor

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize() initializer public {
        __PayoutListener_init();
    }

    // ---  logic

    function payoutDone() external override onlyExchanger {
        _solidLizardSkim();
        _sterlingSkim();
        _sendToRewardWallet();
    }

    function _solidLizardSkim() internal {
        for (uint256 i = 0; i < solidLizardPools.length; i++) {
            address pool = solidLizardPools[i];
            ILizardPair(pool).skim(address(this));
        }
    }

    function _sterlingSkim() internal {
        for (uint256 i = 0; i < sterlingPools.length; i++) {
            address pool = sterlingPools[i];
            uint256 rebaseTokenBalanceBeforeSkim = rebaseToken.balanceOf(address(this));
            ISterlingPair(pool).skim(address(this));
            uint256 amountRebaseToken = rebaseToken.balanceOf(address(this)) - rebaseTokenBalanceBeforeSkim;
            if (amountRebaseToken > 0) {
                rebaseToken.transfer(sterlingWallet, amountRebaseToken);
                emit SterlingSkimReward(pool, sterlingWallet, amountRebaseToken);
            }
        }
    }


    function _sendToRewardWallet() internal {
        require(rewardWallet != address(0), "rewardWallet is zero");
        uint256 balance = rebaseToken.balanceOf(address(this));
        if (balance > 0) {
            rebaseToken.transfer(rewardWallet, balance);
            emit RewardWalletSend(balance);
        }
    }

}

