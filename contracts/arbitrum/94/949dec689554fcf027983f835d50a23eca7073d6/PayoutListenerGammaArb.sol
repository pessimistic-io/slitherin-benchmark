// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./PayoutListener.sol";
import "./SolidLizard.sol";
import "./Sterling.sol";
import "./Arbiswap.sol";

contract PayoutListenerGammaArb is PayoutListener {

    IERC20 public rebaseToken;

    address[] public solidLizardPools;
    address[] public solidLizardBribes;

    address[] public sterlingPools;
    address public sterlingWallet;

    address[] public arbiswapPools;
    address public arbiswapWallet;

    // ---  events

    event RebaseTokenUpdated(address rebaseToken);
    event SolidLizardPoolsUpdated(address[] pools, address[] bribes);
    event SolidLizardSkimAndBribeReward(address pool, address bribe, uint256 amount);

    event SterlingPoolsUpdated(address[] pools);
    event SterlingWalletUpdated(address wallet);
    event SterlingSkimReward(address pool, address wallet, uint256 amount);

    event ArbiswapPoolsUpdated(address[] pools);
    event ArbiswapWalletUpdated(address wallet);
    event ArbiswapSkimReward(address pool, address wallet, uint256 amount);

    // --- setters

    function setRebaseToken(address _rebaseToken) external onlyAdmin {
        require(_rebaseToken != address(0), "Zero address not allowed");
        rebaseToken = IERC20(_rebaseToken);
        emit RebaseTokenUpdated(_rebaseToken);
    }

    function setSolidLizardPools(address[] calldata _pools, address[] calldata _bribes) external onlyAdmin {
        require(_pools.length == _bribes.length, "Pools and bribes not equal");
        solidLizardPools = _pools;
        solidLizardBribes = _bribes;
        emit SolidLizardPoolsUpdated(_pools, _bribes);
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

    function setArbiswapPools(address[] calldata _pools) external onlyAdmin {
        arbiswapPools = _pools;
        emit ArbiswapPoolsUpdated(_pools);
    }

    function setArbiswapWallet(address _wallet) external onlyAdmin {
        require(_wallet != address(0), "Zero address not allowed");
        arbiswapWallet = _wallet;
        emit ArbiswapWalletUpdated(_wallet);
    }

    // ---  constructor

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize() initializer public {
        __PayoutListener_init();
    }

    // ---  logic

    function payoutDone() external override onlyExchanger {
        _solidLizardSkimAndBribe();
        _sterlingSkim();
        _arbiswapSkim();
    }

    function _solidLizardSkimAndBribe() internal {
        for (uint256 i = 0; i < solidLizardPools.length; i++) {
            address pool = solidLizardPools[i];
//            address bribe = solidLizardBribes[i];
//            uint256 rebaseTokenBalanceBeforeSkim = rebaseToken.balanceOf(address(this));
            ILizardPair(pool).skim(address(this));
//            uint256 amountRebaseToken = rebaseToken.balanceOf(address(this)) - rebaseTokenBalanceBeforeSkim;
//            if (amountRebaseToken > 0) {
//                rebaseToken.approve(bribe, amountRebaseToken);
//                ILizardBribe(bribe).notifyRewardAmount(address(rebaseToken), amountRebaseToken);
//                emit SolidLizardSkimAndBribeReward(pool, bribe, amountRebaseToken);
//            }
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

    function _arbiswapSkim() internal {
        for (uint256 i = 0; i < arbiswapPools.length; i++) {
            address pool = arbiswapPools[i];
            uint256 rebaseTokenBalanceBeforeSkim = rebaseToken.balanceOf(address(this));
            IArbiswapPair(pool).skim(address(this));
            uint256 amountRebaseToken = rebaseToken.balanceOf(address(this)) - rebaseTokenBalanceBeforeSkim;
            if (amountRebaseToken > 0) {
                rebaseToken.transfer(arbiswapWallet, amountRebaseToken);
                emit ArbiswapSkimReward(pool, arbiswapWallet, amountRebaseToken);
            }
        }
    }

}
