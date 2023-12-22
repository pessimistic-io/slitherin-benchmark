// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Address.sol";

import "./IRewardTracker.sol";
import "./IRewardRouterV2.sol";
import "./IVester.sol";
import "./IMintable.sol";
import "./IWETH.sol";
import "./IUlpManager.sol";
import "./Governable.sol";

contract RewardRouterV2 is IRewardRouterV2, ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized;

    address public weth;

    address public unip;
    address public esUnip;
    address public bnUnip;

    address public ulp; // UNIP Liquidity Provider token

    address public stakedUnipTracker;
    address public bonusUnipTracker;
    address public feeUnipTracker;

    address public override stakedUlpTracker;
    address public override feeUlpTracker;

    address public ulpManager;
    bool public isSellable;

    address public unipVester;
    address public ulpVester;

    mapping (address => address) public pendingReceivers;

    event StakeUnip(address account, address token, uint256 amount);
    event UnstakeUnip(address account, address token, uint256 amount);

    event StakeUlp(address account, uint256 amount);
    event UnstakeUlp(address account, uint256 amount);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    function initialize(
        address _weth,
        address _unip,
        address _esUnip,
        address _bnUnip,
        address _ulp,
        address _stakedUnipTracker,
        address _bonusUnipTracker,
        address _feeUnipTracker,
        address _feeUlpTracker,
        address _stakedUlpTracker,
        address _ulpManager,
        address _unipVester,
        address _ulpVester
    ) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;

        weth = _weth;

        unip = _unip;
        esUnip = _esUnip;
        bnUnip = _bnUnip;

        ulp = _ulp;

        stakedUnipTracker = _stakedUnipTracker;
        bonusUnipTracker = _bonusUnipTracker;
        feeUnipTracker = _feeUnipTracker;

        feeUlpTracker = _feeUlpTracker;
        stakedUlpTracker = _stakedUlpTracker;

        ulpManager = _ulpManager;

        unipVester = _unipVester;
        ulpVester = _ulpVester;
    }

    function setIsSellable(bool _isSellable) external onlyGov {
        isSellable = _isSellable;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function batchStakeUnipForAccount(address[] memory _accounts, uint256[] memory _amounts) external nonReentrant onlyGov {
        address _unip = unip;
        for (uint256 i = 0; i < _accounts.length; i++) {
            _stakeUnip(msg.sender, _accounts[i], _unip, _amounts[i]);
        }
    }

    function stakeUnipForAccount(address _account, uint256 _amount) external nonReentrant onlyGov {
        _stakeUnip(msg.sender, _account, unip, _amount);
    }

    function stakeUnip(uint256 _amount) external nonReentrant {
        _stakeUnip(msg.sender, msg.sender, unip, _amount);
    }

    function stakeEsUnip(uint256 _amount) external nonReentrant {
        _stakeUnip(msg.sender, msg.sender, esUnip, _amount);
    }

    function unstakeUnip(uint256 _amount) external nonReentrant {
        _unstakeUnip(msg.sender, unip, _amount, true);
    }

    function unstakeEsUnip(uint256 _amount) external nonReentrant {
        _unstakeUnip(msg.sender, esUnip, _amount, true);
    }

    function mintAndStakeUlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minUlp) external nonReentrant returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        uint256 ulpAmount = IUlpManager(ulpManager).addLiquidityForAccount(account, account, _token, _amount, _minUsdg, _minUlp);
        IRewardTracker(feeUlpTracker).stakeForAccount(account, account, ulp, ulpAmount);
        IRewardTracker(stakedUlpTracker).stakeForAccount(account, account, feeUlpTracker, ulpAmount);

        emit StakeUlp(account, ulpAmount);

        return ulpAmount;
    }

    function mintAndStakeUlpETH(uint256 _minUsdg, uint256 _minUlp) external payable nonReentrant returns (uint256) {
        require(msg.value > 0, "RewardRouter: invalid msg.value");

        IWETH(weth).deposit{value: msg.value}();
        IERC20(weth).approve(ulpManager, msg.value);

        address account = msg.sender;
        uint256 ulpAmount = IUlpManager(ulpManager).addLiquidityForAccount(address(this), account, weth, msg.value, _minUsdg, _minUlp);

        IRewardTracker(feeUlpTracker).stakeForAccount(account, account, ulp, ulpAmount);
        IRewardTracker(stakedUlpTracker).stakeForAccount(account, account, feeUlpTracker, ulpAmount);

        emit StakeUlp(account, ulpAmount);

        return ulpAmount;
    }

    function unstakeAndRedeemUlp(address _tokenOut, uint256 _ulpAmount, uint256 _minOut, address _receiver) external nonReentrant returns (uint256) {
        require(_ulpAmount > 0, "RewardRouter: invalid _ulpAmount");
        if (!isSellable) { revert("RewardRouter: only after super ulp phase can sell"); }

        address account = msg.sender;
        IRewardTracker(stakedUlpTracker).unstakeForAccount(account, feeUlpTracker, _ulpAmount, account);
        IRewardTracker(feeUlpTracker).unstakeForAccount(account, ulp, _ulpAmount, account);
        uint256 amountOut = IUlpManager(ulpManager).removeLiquidityForAccount(account, _tokenOut, _ulpAmount, _minOut, _receiver);

        emit UnstakeUlp(account, _ulpAmount);

        return amountOut;
    }

    function unstakeAndRedeemUlpETH(uint256 _ulpAmount, uint256 _minOut, address payable _receiver) external nonReentrant returns (uint256) {
        require(_ulpAmount > 0, "RewardRouter: invalid _ulpAmount");
        if (!isSellable) { revert("RewardRouter: only after super ulp phase can sell"); }

        address account = msg.sender;
        IRewardTracker(stakedUlpTracker).unstakeForAccount(account, feeUlpTracker, _ulpAmount, account);
        IRewardTracker(feeUlpTracker).unstakeForAccount(account, ulp, _ulpAmount, account);
        uint256 amountOut = IUlpManager(ulpManager).removeLiquidityForAccount(account, weth, _ulpAmount, _minOut, address(this));

        IWETH(weth).withdraw(amountOut);

        _receiver.sendValue(amountOut);

        emit UnstakeUlp(account, _ulpAmount);

        return amountOut;
    }

    function claim() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeUnipTracker).claimForAccount(account, account);
        IRewardTracker(feeUlpTracker).claimForAccount(account, account);

        IRewardTracker(stakedUnipTracker).claimForAccount(account, account);
        IRewardTracker(stakedUlpTracker).claimForAccount(account, account);
    }

    function claimEsUnip() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(stakedUnipTracker).claimForAccount(account, account);
        IRewardTracker(stakedUlpTracker).claimForAccount(account, account);
    }

    function claimFees() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeUnipTracker).claimForAccount(account, account);
        IRewardTracker(feeUlpTracker).claimForAccount(account, account);
    }

    function compound() external nonReentrant {
        _compound(msg.sender);
    }

    function compoundForAccount(address _account) external nonReentrant onlyGov {
        _compound(_account);
    }

    function handleRewards(
        bool _shouldClaimUnip,
        bool _shouldStakeUnip,
        bool _shouldClaimEsUnip,
        bool _shouldStakeEsUnip,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external nonReentrant {
        address account = msg.sender;

        uint256 unipAmount = 0;
        if (_shouldClaimUnip) {
            uint256 unipAmount0 = IVester(unipVester).claimForAccount(account, account);
            uint256 unipAmount1 = IVester(ulpVester).claimForAccount(account, account);
            unipAmount = unipAmount0.add(unipAmount1);
        }

        if (_shouldStakeUnip && unipAmount > 0) {
            _stakeUnip(account, account, unip, unipAmount);
        }

        uint256 esUnipAmount = 0;
        if (_shouldClaimEsUnip) {
            uint256 esUnipAmount0 = IRewardTracker(stakedUnipTracker).claimForAccount(account, account);
            uint256 esUnipAmount1 = IRewardTracker(stakedUlpTracker).claimForAccount(account, account);
            esUnipAmount = esUnipAmount0.add(esUnipAmount1);
        }

        if (_shouldStakeEsUnip && esUnipAmount > 0) {
            _stakeUnip(account, account, esUnip, esUnipAmount);
        }

        if (_shouldStakeMultiplierPoints) {
            uint256 bnUnipAmount = IRewardTracker(bonusUnipTracker).claimForAccount(account, account);
            if (bnUnipAmount > 0) {
                IRewardTracker(feeUnipTracker).stakeForAccount(account, account, bnUnip, bnUnipAmount);
            }
        }

        if (_shouldClaimWeth) {
            if (_shouldConvertWethToEth) {
                uint256 weth0 = IRewardTracker(feeUnipTracker).claimForAccount(account, address(this));
                uint256 weth1 = IRewardTracker(feeUlpTracker).claimForAccount(account, address(this));

                uint256 wethAmount = weth0.add(weth1);
                IWETH(weth).withdraw(wethAmount);

                payable(account).sendValue(wethAmount);
            } else {
                IRewardTracker(feeUnipTracker).claimForAccount(account, account);
                IRewardTracker(feeUlpTracker).claimForAccount(account, account);
            }
        }
    }

    function batchCompoundForAccounts(address[] memory _accounts) external nonReentrant onlyGov {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _compound(_accounts[i]);
        }
    }

    function signalTransfer(address _receiver) external nonReentrant {
        require(IERC20(unipVester).balanceOf(msg.sender) == 0, "RewardRouter: sender has vested tokens");
        require(IERC20(ulpVester).balanceOf(msg.sender) == 0, "RewardRouter: sender has vested tokens");

        _validateReceiver(_receiver);
        pendingReceivers[msg.sender] = _receiver;
    }

    function acceptTransfer(address _sender) external nonReentrant {
        require(IERC20(unipVester).balanceOf(_sender) == 0, "RewardRouter: sender has vested tokens");
        require(IERC20(ulpVester).balanceOf(_sender) == 0, "RewardRouter: sender has vested tokens");

        address receiver = msg.sender;
        require(pendingReceivers[_sender] == receiver, "RewardRouter: transfer not signalled");
        delete pendingReceivers[_sender];

        _validateReceiver(receiver);
        _compound(_sender);

        uint256 stakedUnip = IRewardTracker(stakedUnipTracker).depositBalances(_sender, unip);
        if (stakedUnip > 0) {
            _unstakeUnip(_sender, unip, stakedUnip, false);
            _stakeUnip(_sender, receiver, unip, stakedUnip);
        }

        uint256 stakedEsUnip = IRewardTracker(stakedUnipTracker).depositBalances(_sender, esUnip);
        if (stakedEsUnip > 0) {
            _unstakeUnip(_sender, esUnip, stakedEsUnip, false);
            _stakeUnip(_sender, receiver, esUnip, stakedEsUnip);
        }

        uint256 stakedBnUnip = IRewardTracker(feeUnipTracker).depositBalances(_sender, bnUnip);
        if (stakedBnUnip > 0) {
            IRewardTracker(feeUnipTracker).unstakeForAccount(_sender, bnUnip, stakedBnUnip, _sender);
            IRewardTracker(feeUnipTracker).stakeForAccount(_sender, receiver, bnUnip, stakedBnUnip);
        }

        uint256 esUnipBalance = IERC20(esUnip).balanceOf(_sender);
        if (esUnipBalance > 0) {
            IERC20(esUnip).transferFrom(_sender, receiver, esUnipBalance);
        }

        uint256 ulpAmount = IRewardTracker(feeUlpTracker).depositBalances(_sender, ulp);
        if (ulpAmount > 0) {
            IRewardTracker(stakedUlpTracker).unstakeForAccount(_sender, feeUlpTracker, ulpAmount, _sender);
            IRewardTracker(feeUlpTracker).unstakeForAccount(_sender, ulp, ulpAmount, _sender);

            IRewardTracker(feeUlpTracker).stakeForAccount(_sender, receiver, ulp, ulpAmount);
            IRewardTracker(stakedUlpTracker).stakeForAccount(receiver, receiver, feeUlpTracker, ulpAmount);
        }

        IVester(unipVester).transferStakeValues(_sender, receiver);
        IVester(ulpVester).transferStakeValues(_sender, receiver);
    }

    function _validateReceiver(address _receiver) private view {
        require(IRewardTracker(stakedUnipTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: stakedUnipTracker.averageStakedAmounts > 0");
        require(IRewardTracker(stakedUnipTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: stakedUnipTracker.cumulativeRewards > 0");

        require(IRewardTracker(bonusUnipTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: bonusUnipTracker.averageStakedAmounts > 0");
        require(IRewardTracker(bonusUnipTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: bonusUnipTracker.cumulativeRewards > 0");

        require(IRewardTracker(feeUnipTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: feeUnipTracker.averageStakedAmounts > 0");
        require(IRewardTracker(feeUnipTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: feeUnipTracker.cumulativeRewards > 0");

        require(IVester(unipVester).transferredAverageStakedAmounts(_receiver) == 0, "RewardRouter: unipVester.transferredAverageStakedAmounts > 0");
        require(IVester(unipVester).transferredCumulativeRewards(_receiver) == 0, "RewardRouter: unipVester.transferredCumulativeRewards > 0");

        require(IRewardTracker(stakedUlpTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: stakedUlpTracker.averageStakedAmounts > 0");
        require(IRewardTracker(stakedUlpTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: stakedUlpTracker.cumulativeRewards > 0");

        require(IRewardTracker(feeUlpTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: feeUlpTracker.averageStakedAmounts > 0");
        require(IRewardTracker(feeUlpTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: feeUlpTracker.cumulativeRewards > 0");

        require(IVester(ulpVester).transferredAverageStakedAmounts(_receiver) == 0, "RewardRouter: unipVester.transferredAverageStakedAmounts > 0");
        require(IVester(ulpVester).transferredCumulativeRewards(_receiver) == 0, "RewardRouter: unipVester.transferredCumulativeRewards > 0");

        require(IERC20(unipVester).balanceOf(_receiver) == 0, "RewardRouter: unipVester.balance > 0");
        require(IERC20(ulpVester).balanceOf(_receiver) == 0, "RewardRouter: ulpVester.balance > 0");
    }

    function _compound(address _account) private {
        _compoundUnip(_account);
        _compoundUlp(_account);
    }

    function _compoundUnip(address _account) private {
        uint256 esUnipAmount = IRewardTracker(stakedUnipTracker).claimForAccount(_account, _account);
        if (esUnipAmount > 0) {
            _stakeUnip(_account, _account, esUnip, esUnipAmount);
        }

        uint256 bnUnipAmount = IRewardTracker(bonusUnipTracker).claimForAccount(_account, _account);
        if (bnUnipAmount > 0) {
            IRewardTracker(feeUnipTracker).stakeForAccount(_account, _account, bnUnip, bnUnipAmount);
        }
    }

    function _compoundUlp(address _account) private {
        uint256 esUnipAmount = IRewardTracker(stakedUlpTracker).claimForAccount(_account, _account);
        if (esUnipAmount > 0) {
            _stakeUnip(_account, _account, esUnip, esUnipAmount);
        }
    }

    function _stakeUnip(address _fundingAccount, address _account, address _token, uint256 _amount) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        IRewardTracker(stakedUnipTracker).stakeForAccount(_fundingAccount, _account, _token, _amount);
        IRewardTracker(bonusUnipTracker).stakeForAccount(_account, _account, stakedUnipTracker, _amount);
        IRewardTracker(feeUnipTracker).stakeForAccount(_account, _account, bonusUnipTracker, _amount);

        emit StakeUnip(_account, _token, _amount);
    }

    function _unstakeUnip(address _account, address _token, uint256 _amount, bool _shouldReduceBnUnip) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        uint256 balance = IRewardTracker(stakedUnipTracker).stakedAmounts(_account);

        IRewardTracker(feeUnipTracker).unstakeForAccount(_account, bonusUnipTracker, _amount, _account);
        IRewardTracker(bonusUnipTracker).unstakeForAccount(_account, stakedUnipTracker, _amount, _account);
        IRewardTracker(stakedUnipTracker).unstakeForAccount(_account, _token, _amount, _account);

        if (_shouldReduceBnUnip) {
            uint256 bnUnipAmount = IRewardTracker(bonusUnipTracker).claimForAccount(_account, _account);
            if (bnUnipAmount > 0) {
                IRewardTracker(feeUnipTracker).stakeForAccount(_account, _account, bnUnip, bnUnipAmount);
            }

            uint256 stakedBnUnip = IRewardTracker(feeUnipTracker).depositBalances(_account, bnUnip);
            if (stakedBnUnip > 0) {
                uint256 reductionAmount = stakedBnUnip.mul(_amount).div(balance);
                IRewardTracker(feeUnipTracker).unstakeForAccount(_account, bnUnip, reductionAmount, _account);
                IMintable(bnUnip).burn(_account, reductionAmount);
            }
        }

        emit UnstakeUnip(_account, _token, _amount);
    }
}

