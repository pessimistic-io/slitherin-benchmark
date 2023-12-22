// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.4;

import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Address.sol";

import "./IRewardTracker.sol";
import "./IVester.sol";
import "./IMintable.sol";
import "./IBlpManager.sol";
import "./Governable.sol";

contract RewardRouterV2 is ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized;

    address public usdc;

    address public bfr;
    address public esBfr;
    address public bnBfr;

    address public blp; // BFR Liquidity Provider token

    address public stakedBfrTracker;
    address public bonusBfrTracker;
    address public feeBfrTracker;

    address public stakedBlpTracker;
    address public feeBlpTracker;

    address public blpManager;

    address public bfrVester;
    address public blpVester;

    mapping(address => address) public pendingReceivers;

    event StakeBfr(address account, address token, uint256 amount);
    event UnstakeBfr(address account, address token, uint256 amount);

    event StakeBlp(address account, uint256 amount);
    event UnstakeBlp(address account, uint256 amount);

    receive() external payable {
        revert("Router: Can't receive eth");
    }

    function initialize(
        address _usdc,
        address _bfr,
        address _esBfr,
        address _bnBfr,
        address _blp,
        address _stakedBfrTracker,
        address _bonusBfrTracker,
        address _feeBfrTracker,
        address _feeBlpTracker,
        address _stakedBlpTracker,
        address _bfrVester,
        address _blpVester
    ) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;

        usdc = _usdc;

        bfr = _bfr;
        esBfr = _esBfr;
        bnBfr = _bnBfr;

        blp = _blp;

        stakedBfrTracker = _stakedBfrTracker;
        bonusBfrTracker = _bonusBfrTracker;
        feeBfrTracker = _feeBfrTracker;

        feeBlpTracker = _feeBlpTracker;
        stakedBlpTracker = _stakedBlpTracker;

        blpManager = _blp;

        bfrVester = _bfrVester;
        blpVester = _blpVester;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(
        address _token,
        address _account,
        uint256 _amount
    ) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function batchStakeBfrForAccount(
        address[] memory _accounts,
        uint256[] memory _amounts
    ) external nonReentrant onlyGov {
        address _bfr = bfr;
        for (uint256 i = 0; i < _accounts.length; i++) {
            _stakeBfr(msg.sender, _accounts[i], _bfr, _amounts[i]);
        }
    }

    function stakeBfrForAccount(address _account, uint256 _amount)
        external
        nonReentrant
        onlyGov
    {
        _stakeBfr(msg.sender, _account, bfr, _amount);
    }

    function stakeBfr(uint256 _amount) external nonReentrant {
        _stakeBfr(msg.sender, msg.sender, bfr, _amount);
    }

    function stakeEsBfr(uint256 _amount) external nonReentrant {
        _stakeBfr(msg.sender, msg.sender, esBfr, _amount);
    }

    function unstakeBfr(uint256 _amount) external nonReentrant {
        _unstakeBfr(msg.sender, bfr, _amount, true);
    }

    function unstakeEsBfr(uint256 _amount) external nonReentrant {
        _unstakeBfr(msg.sender, esBfr, _amount, true);
    }

    function mintAndStakeBlp(uint256 _amount, uint256 _minBlp)
        external
        nonReentrant
        returns (uint256)
    {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        uint256 blpAmount = IBlpManager(blpManager).provideForAccount(
            _amount,
            _minBlp,
            account
        );
        IRewardTracker(feeBlpTracker).stakeForAccount(
            account,
            account,
            blp,
            blpAmount
        );
        IRewardTracker(stakedBlpTracker).stakeForAccount(
            account,
            account,
            feeBlpTracker,
            blpAmount
        );

        emit StakeBlp(account, blpAmount);

        return blpAmount;
    }

    function unstakeAndRedeemBlp(uint256 _blpAmount)
        external
        nonReentrant
        returns (uint256)
    {
        require(_blpAmount > 0, "RewardRouter: invalid _blpAmount");

        address account = msg.sender;
        IRewardTracker(stakedBlpTracker).unstakeForAccount(
            account,
            feeBlpTracker,
            _blpAmount,
            account
        );
        IRewardTracker(feeBlpTracker).unstakeForAccount(
            account,
            blp,
            _blpAmount,
            account
        );
        uint256 amountOut = IBlpManager(blpManager).withdrawForAccount(
            IBlpManager(blpManager).toTokenX(_blpAmount),
            account
        );

        emit UnstakeBlp(account, _blpAmount);

        return amountOut;
    }

    function claim() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeBfrTracker).claimForAccount(account, account);
        IRewardTracker(feeBlpTracker).claimForAccount(account, account);

        IRewardTracker(stakedBfrTracker).claimForAccount(account, account);
        IRewardTracker(stakedBlpTracker).claimForAccount(account, account);
    }

    function claimEsBfr() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(stakedBfrTracker).claimForAccount(account, account);
        IRewardTracker(stakedBlpTracker).claimForAccount(account, account);
    }

    function claimFees() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeBfrTracker).claimForAccount(account, account);
        IRewardTracker(feeBlpTracker).claimForAccount(account, account);
    }

    function compound() external nonReentrant {
        _compound(msg.sender);
    }

    function compoundForAccount(address _account)
        external
        nonReentrant
        onlyGov
    {
        _compound(_account);
    }

    function handleRewards(
        bool _shouldClaimBfr,
        bool _shouldStakeBfr,
        bool _shouldClaimEsBfr,
        bool _shouldStakeEsBfr,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimUsdc
    ) external nonReentrant {
        address account = msg.sender;

        uint256 bfrAmount = 0;
        if (_shouldClaimBfr) {
            uint256 bfrAmount0 = IVester(bfrVester).claimForAccount(
                account,
                account
            );
            uint256 bfrAmount1 = IVester(blpVester).claimForAccount(
                account,
                account
            );
            bfrAmount = bfrAmount0.add(bfrAmount1);
        }

        if (_shouldStakeBfr && bfrAmount > 0) {
            _stakeBfr(account, account, bfr, bfrAmount);
        }

        uint256 esBfrAmount = 0;
        if (_shouldClaimEsBfr) {
            uint256 esBfrAmount0 = IRewardTracker(stakedBfrTracker)
                .claimForAccount(account, account);
            uint256 esBfrAmount1 = IRewardTracker(stakedBlpTracker)
                .claimForAccount(account, account);
            esBfrAmount = esBfrAmount0.add(esBfrAmount1);
        }

        if (_shouldStakeEsBfr && esBfrAmount > 0) {
            _stakeBfr(account, account, esBfr, esBfrAmount);
        }

        if (_shouldStakeMultiplierPoints) {
            uint256 bnBfrAmount = IRewardTracker(bonusBfrTracker)
                .claimForAccount(account, account);
            if (bnBfrAmount > 0) {
                IRewardTracker(feeBfrTracker).stakeForAccount(
                    account,
                    account,
                    bnBfr,
                    bnBfrAmount
                );
            }
        }

        if (_shouldClaimUsdc) {
            IRewardTracker(feeBfrTracker).claimForAccount(account, account);
            IRewardTracker(feeBlpTracker).claimForAccount(account, account);
        }
    }

    function batchCompoundForAccounts(address[] memory _accounts)
        external
        nonReentrant
        onlyGov
    {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _compound(_accounts[i]);
        }
    }

    function signalTransfer(address _receiver) external nonReentrant {
        require(
            IERC20(bfrVester).balanceOf(msg.sender) == 0,
            "RewardRouter: sender has vested tokens"
        );
        require(
            IERC20(blpVester).balanceOf(msg.sender) == 0,
            "RewardRouter: sender has vested tokens"
        );

        _validateReceiver(_receiver);
        pendingReceivers[msg.sender] = _receiver;
    }

    function acceptTransfer(address _sender) external nonReentrant {
        require(
            IERC20(bfrVester).balanceOf(_sender) == 0,
            "RewardRouter: sender has vested tokens"
        );
        require(
            IERC20(blpVester).balanceOf(_sender) == 0,
            "RewardRouter: sender has vested tokens"
        );

        address receiver = msg.sender;
        require(
            pendingReceivers[_sender] == receiver,
            "RewardRouter: transfer not signalled"
        );
        delete pendingReceivers[_sender];

        _validateReceiver(receiver);
        _compound(_sender);

        uint256 stakedBfr = IRewardTracker(stakedBfrTracker).depositBalances(
            _sender,
            bfr
        );
        if (stakedBfr > 0) {
            _unstakeBfr(_sender, bfr, stakedBfr, false);
            _stakeBfr(_sender, receiver, bfr, stakedBfr);
        }

        uint256 stakedEsBfr = IRewardTracker(stakedBfrTracker).depositBalances(
            _sender,
            esBfr
        );
        if (stakedEsBfr > 0) {
            _unstakeBfr(_sender, esBfr, stakedEsBfr, false);
            _stakeBfr(_sender, receiver, esBfr, stakedEsBfr);
        }

        uint256 stakedBnBfr = IRewardTracker(feeBfrTracker).depositBalances(
            _sender,
            bnBfr
        );
        if (stakedBnBfr > 0) {
            IRewardTracker(feeBfrTracker).unstakeForAccount(
                _sender,
                bnBfr,
                stakedBnBfr,
                _sender
            );
            IRewardTracker(feeBfrTracker).stakeForAccount(
                _sender,
                receiver,
                bnBfr,
                stakedBnBfr
            );
        }

        uint256 esBfrBalance = IERC20(esBfr).balanceOf(_sender);
        if (esBfrBalance > 0) {
            IERC20(esBfr).transferFrom(_sender, receiver, esBfrBalance);
        }

        uint256 blpAmount = IRewardTracker(feeBlpTracker).depositBalances(
            _sender,
            blp
        );
        if (blpAmount > 0) {
            IRewardTracker(stakedBlpTracker).unstakeForAccount(
                _sender,
                feeBlpTracker,
                blpAmount,
                _sender
            );
            IRewardTracker(feeBlpTracker).unstakeForAccount(
                _sender,
                blp,
                blpAmount,
                _sender
            );

            IRewardTracker(feeBlpTracker).stakeForAccount(
                _sender,
                receiver,
                blp,
                blpAmount
            );
            IRewardTracker(stakedBlpTracker).stakeForAccount(
                receiver,
                receiver,
                feeBlpTracker,
                blpAmount
            );
        }

        IVester(bfrVester).transferStakeValues(_sender, receiver);
        IVester(blpVester).transferStakeValues(_sender, receiver);
    }

    function _validateReceiver(address _receiver) private view {
        require(
            IRewardTracker(stakedBfrTracker).averageStakedAmounts(_receiver) ==
                0,
            "RewardRouter: stakedBfrTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(stakedBfrTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: stakedBfrTracker.cumulativeRewards > 0"
        );

        require(
            IRewardTracker(bonusBfrTracker).averageStakedAmounts(_receiver) ==
                0,
            "RewardRouter: bonusBfrTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(bonusBfrTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: bonusBfrTracker.cumulativeRewards > 0"
        );

        require(
            IRewardTracker(feeBfrTracker).averageStakedAmounts(_receiver) == 0,
            "RewardRouter: feeBfrTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(feeBfrTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: feeBfrTracker.cumulativeRewards > 0"
        );

        require(
            IVester(bfrVester).transferredAverageStakedAmounts(_receiver) == 0,
            "RewardRouter: bfrVester.transferredAverageStakedAmounts > 0"
        );
        require(
            IVester(bfrVester).transferredCumulativeRewards(_receiver) == 0,
            "RewardRouter: bfrVester.transferredCumulativeRewards > 0"
        );

        require(
            IRewardTracker(stakedBlpTracker).averageStakedAmounts(_receiver) ==
                0,
            "RewardRouter: stakedBlpTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(stakedBlpTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: stakedBlpTracker.cumulativeRewards > 0"
        );

        require(
            IRewardTracker(feeBlpTracker).averageStakedAmounts(_receiver) == 0,
            "RewardRouter: feeBlpTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(feeBlpTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: feeBlpTracker.cumulativeRewards > 0"
        );

        require(
            IVester(blpVester).transferredAverageStakedAmounts(_receiver) == 0,
            "RewardRouter: bfrVester.transferredAverageStakedAmounts > 0"
        );
        require(
            IVester(blpVester).transferredCumulativeRewards(_receiver) == 0,
            "RewardRouter: bfrVester.transferredCumulativeRewards > 0"
        );

        require(
            IERC20(bfrVester).balanceOf(_receiver) == 0,
            "RewardRouter: bfrVester.balance > 0"
        );
        require(
            IERC20(blpVester).balanceOf(_receiver) == 0,
            "RewardRouter: blpVester.balance > 0"
        );
    }

    function _compound(address _account) private {
        _compoundBfr(_account);
        _compoundBlp(_account);
    }

    function _compoundBfr(address _account) private {
        uint256 esBfrAmount = IRewardTracker(stakedBfrTracker).claimForAccount(
            _account,
            _account
        );
        if (esBfrAmount > 0) {
            _stakeBfr(_account, _account, esBfr, esBfrAmount);
        }

        uint256 bnBfrAmount = IRewardTracker(bonusBfrTracker).claimForAccount(
            _account,
            _account
        );
        if (bnBfrAmount > 0) {
            IRewardTracker(feeBfrTracker).stakeForAccount(
                _account,
                _account,
                bnBfr,
                bnBfrAmount
            );
        }
    }

    function _compoundBlp(address _account) private {
        uint256 esBfrAmount = IRewardTracker(stakedBlpTracker).claimForAccount(
            _account,
            _account
        );
        if (esBfrAmount > 0) {
            _stakeBfr(_account, _account, esBfr, esBfrAmount);
        }
    }

    function _stakeBfr(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount
    ) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        IRewardTracker(stakedBfrTracker).stakeForAccount(
            _fundingAccount,
            _account,
            _token,
            _amount
        );
        IRewardTracker(bonusBfrTracker).stakeForAccount(
            _account,
            _account,
            stakedBfrTracker,
            _amount
        );
        IRewardTracker(feeBfrTracker).stakeForAccount(
            _account,
            _account,
            bonusBfrTracker,
            _amount
        );

        emit StakeBfr(_account, _token, _amount);
    }

    function _unstakeBfr(
        address _account,
        address _token,
        uint256 _amount,
        bool _shouldReduceBnBfr
    ) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        uint256 balance = IRewardTracker(stakedBfrTracker).stakedAmounts(
            _account
        );

        IRewardTracker(feeBfrTracker).unstakeForAccount(
            _account,
            bonusBfrTracker,
            _amount,
            _account
        );
        IRewardTracker(bonusBfrTracker).unstakeForAccount(
            _account,
            stakedBfrTracker,
            _amount,
            _account
        );
        IRewardTracker(stakedBfrTracker).unstakeForAccount(
            _account,
            _token,
            _amount,
            _account
        );

        if (_shouldReduceBnBfr) {
            uint256 bnBfrAmount = IRewardTracker(bonusBfrTracker)
                .claimForAccount(_account, _account);
            if (bnBfrAmount > 0) {
                IRewardTracker(feeBfrTracker).stakeForAccount(
                    _account,
                    _account,
                    bnBfr,
                    bnBfrAmount
                );
            }

            uint256 stakedBnBfr = IRewardTracker(feeBfrTracker).depositBalances(
                _account,
                bnBfr
            );
            if (stakedBnBfr > 0) {
                uint256 reductionAmount = stakedBnBfr.mul(_amount).div(balance);
                IRewardTracker(feeBfrTracker).unstakeForAccount(
                    _account,
                    bnBfr,
                    reductionAmount,
                    _account
                );
                IMintable(bnBfr).burn(_account, reductionAmount);
            }
        }

        emit UnstakeBfr(_account, _token, _amount);
    }
}

