// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Address.sol";

import "./IRewardTracker.sol";
import "./IVester.sol";
import "./IMintable.sol";
import "./IWETH.sol";
import "./Governable.sol";

contract RewardRouterV2 is ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized;

    address public weth;

    address public tnd;
    address public esTnd;
    address public bnTnd;

    address public stakedTndTracker;
    address public bonusTndTracker;
    address public feeTndTracker;

    address public tndVester;

    mapping (address => address) public pendingReceivers;

    event StakeTnd(address account, address token, uint256 amount);
    event UnstakeTnd(address account, address token, uint256 amount);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    function initialize(
        address _weth,
        address _tnd,
        address _esTnd,
        address _bnTnd,
        address _stakedTndTracker,
        address _bonusTndTracker,
        address _feeTndTracker,
        address _tndVester
    ) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;

        weth = _weth;

        tnd = _tnd;
        esTnd = _esTnd;
        bnTnd = _bnTnd;

        stakedTndTracker = _stakedTndTracker;
        bonusTndTracker = _bonusTndTracker;
        feeTndTracker = _feeTndTracker;

        tndVester = _tndVester;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function batchStakeTndForAccount(address[] memory _accounts, uint256[] memory _amounts) external nonReentrant onlyGov {
        address _tnd = tnd;
        for (uint256 i = 0; i < _accounts.length; i++) {
            _stakeTnd(msg.sender, _accounts[i], _tnd, _amounts[i]);
        }
    }

    function stakeTndForAccount(address _account, uint256 _amount) external nonReentrant onlyGov {
        _stakeTnd(msg.sender, _account, tnd, _amount);
    }

    function stakeTnd(uint256 _amount) external nonReentrant {
        _stakeTnd(msg.sender, msg.sender, tnd, _amount);
    }

    function stakeEsTnd(uint256 _amount) external nonReentrant {
        _stakeTnd(msg.sender, msg.sender, esTnd, _amount);
    }

    function unstakeTnd(uint256 _amount) external nonReentrant {
        _unstakeTnd(msg.sender, tnd, _amount, true);
    }

    function unstakeEsTnd(uint256 _amount) external nonReentrant {
        _unstakeTnd(msg.sender, esTnd, _amount, true);
    }

    function claim() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeTndTracker).claimForAccount(account, account);
        IRewardTracker(stakedTndTracker).claimForAccount(account, account);
    }

    function claimEsTnd() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(stakedTndTracker).claimForAccount(account, account);
    }

    function claimFees() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeTndTracker).claimForAccount(account, account);
    }

    function compound() external nonReentrant {
        _compound(msg.sender);
    }

    function compoundForAccount(address _account) external nonReentrant onlyGov {
        _compound(_account);
    }

    function handleRewards(
        bool _shouldClaimTnd,
        bool _shouldStakeTnd,
        bool _shouldClaimEsTnd,
        bool _shouldStakeEsTnd,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external nonReentrant {
        address account = msg.sender;

        uint256 tndAmount = 0;
        if (_shouldClaimTnd) {
            tndAmount = IVester(tndVester).claimForAccount(account, account);
        }

        if (_shouldStakeTnd && tndAmount > 0) {
            _stakeTnd(account, account, tnd, tndAmount);
        }

        uint256 esTndAmount = 0;
        if (_shouldClaimEsTnd) {
            esTndAmount = IRewardTracker(stakedTndTracker).claimForAccount(account, account);
        }

        if (_shouldStakeEsTnd && esTndAmount > 0) {
            _stakeTnd(account, account, esTnd, esTndAmount);
        }

        if (_shouldStakeMultiplierPoints) {
            uint256 bnTndAmount = IRewardTracker(bonusTndTracker).claimForAccount(account, account);
            if (bnTndAmount > 0) {
                IRewardTracker(feeTndTracker).stakeForAccount(account, account, bnTnd, bnTndAmount);
            }
        }

        if (_shouldClaimWeth) {
            if (_shouldConvertWethToEth) {
                uint256 wethAmount = IRewardTracker(feeTndTracker).claimForAccount(account, address(this));
                IWETH(weth).withdraw(wethAmount);

                payable(account).sendValue(wethAmount);
            } else {
                IRewardTracker(feeTndTracker).claimForAccount(account, account);
            }
        }
    }

    function batchCompoundForAccounts(address[] memory _accounts) external nonReentrant onlyGov {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _compound(_accounts[i]);
        }
    }

    function signalTransfer(address _receiver) external nonReentrant {
        require(IERC20(tndVester).balanceOf(msg.sender) == 0, "RewardRouter: sender has vested tokens");

        _validateReceiver(_receiver);
        pendingReceivers[msg.sender] = _receiver;
    }

    function acceptTransfer(address _sender) external nonReentrant {
        require(IERC20(tndVester).balanceOf(_sender) == 0, "RewardRouter: sender has vested tokens");

        address receiver = msg.sender;
        require(pendingReceivers[_sender] == receiver, "RewardRouter: transfer not signalled");
        delete pendingReceivers[_sender];

        _validateReceiver(receiver);
        _compound(_sender);

        uint256 stakedTnd = IRewardTracker(stakedTndTracker).depositBalances(_sender, tnd);
        if (stakedTnd > 0) {
            _unstakeTnd(_sender, tnd, stakedTnd, false);
            _stakeTnd(_sender, receiver, tnd, stakedTnd);
        }

        uint256 stakedEsTnd = IRewardTracker(stakedTndTracker).depositBalances(_sender, esTnd);
        if (stakedEsTnd > 0) {
            _unstakeTnd(_sender, esTnd, stakedEsTnd, false);
            _stakeTnd(_sender, receiver, esTnd, stakedEsTnd);
        }

        uint256 stakedBnTnd = IRewardTracker(feeTndTracker).depositBalances(_sender, bnTnd);
        if (stakedBnTnd > 0) {
            IRewardTracker(feeTndTracker).unstakeForAccount(_sender, bnTnd, stakedBnTnd, _sender);
            IRewardTracker(feeTndTracker).stakeForAccount(_sender, receiver, bnTnd, stakedBnTnd);
        }

        uint256 esTndBalance = IERC20(esTnd).balanceOf(_sender);
        if (esTndBalance > 0) {
            IERC20(esTnd).transferFrom(_sender, receiver, esTndBalance);
        }

        IVester(tndVester).transferStakeValues(_sender, receiver);
    }

    function _validateReceiver(address _receiver) private view {
        require(IRewardTracker(stakedTndTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: stakedTndTracker.averageStakedAmounts > 0");
        require(IRewardTracker(stakedTndTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: stakedTndTracker.cumulativeRewards > 0");

        require(IRewardTracker(bonusTndTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: bonusTndTracker.averageStakedAmounts > 0");
        require(IRewardTracker(bonusTndTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: bonusTndTracker.cumulativeRewards > 0");

        require(IRewardTracker(feeTndTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: feeTndTracker.averageStakedAmounts > 0");
        require(IRewardTracker(feeTndTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: feeTndTracker.cumulativeRewards > 0");

        require(IVester(tndVester).transferredAverageStakedAmounts(_receiver) == 0, "RewardRouter: tndVester.transferredAverageStakedAmounts > 0");
        require(IVester(tndVester).transferredCumulativeRewards(_receiver) == 0, "RewardRouter: tndVester.transferredCumulativeRewards > 0");

        require(IERC20(tndVester).balanceOf(_receiver) == 0, "RewardRouter: tndVester.balance > 0");
    }

    function _compound(address _account) private {
        _compoundTnd(_account);
    }

    function _compoundTnd(address _account) private {
        uint256 esTndAmount = IRewardTracker(stakedTndTracker).claimForAccount(_account, _account);
        if (esTndAmount > 0) {
            _stakeTnd(_account, _account, esTnd, esTndAmount);
        }

        uint256 bnTndAmount = IRewardTracker(bonusTndTracker).claimForAccount(_account, _account);
        if (bnTndAmount > 0) {
            IRewardTracker(feeTndTracker).stakeForAccount(_account, _account, bnTnd, bnTndAmount);
        }
    }

    function _stakeTnd(address _fundingAccount, address _account, address _token, uint256 _amount) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        IRewardTracker(stakedTndTracker).stakeForAccount(_fundingAccount, _account, _token, _amount);
        IRewardTracker(bonusTndTracker).stakeForAccount(_account, _account, stakedTndTracker, _amount);
        IRewardTracker(feeTndTracker).stakeForAccount(_account, _account, bonusTndTracker, _amount);

        emit StakeTnd(_account, _token, _amount);
    }

    function _unstakeTnd(address _account, address _token, uint256 _amount, bool _shouldReduceBnTnd) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        uint256 balance = IRewardTracker(stakedTndTracker).stakedAmounts(_account);

        IRewardTracker(feeTndTracker).unstakeForAccount(_account, bonusTndTracker, _amount, _account);
        IRewardTracker(bonusTndTracker).unstakeForAccount(_account, stakedTndTracker, _amount, _account);
        IRewardTracker(stakedTndTracker).unstakeForAccount(_account, _token, _amount, _account);

        if (_shouldReduceBnTnd) {
            uint256 bnTndAmount = IRewardTracker(bonusTndTracker).claimForAccount(_account, _account);
            if (bnTndAmount > 0) {
                IRewardTracker(feeTndTracker).stakeForAccount(_account, _account, bnTnd, bnTndAmount);
            }

            uint256 stakedBnTnd = IRewardTracker(feeTndTracker).depositBalances(_account, bnTnd);
            if (stakedBnTnd > 0) {
                uint256 reductionAmount = stakedBnTnd.mul(_amount).div(balance);
                IRewardTracker(feeTndTracker).unstakeForAccount(_account, bnTnd, reductionAmount, _account);
                IMintable(bnTnd).burn(_account, reductionAmount);
            }
        }

        emit UnstakeTnd(_account, _token, _amount);
    }
}

