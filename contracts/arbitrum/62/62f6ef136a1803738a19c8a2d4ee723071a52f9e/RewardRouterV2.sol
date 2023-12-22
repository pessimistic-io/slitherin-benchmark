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
import "./IUlpManager.sol";
import "./Governable.sol";

contract RewardRouterV2 is ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized;

    address public weth;

    address public unity;
    address public esUnity;
    address public bnUnity;

    address public ulp; // UNITY Liquidity Provider token

    address public stakedUnityTracker;
    address public bonusUnityTracker;
    address public feeUnityTracker;

    address public stakedUlpTracker;
    address public feeUlpTracker;

    address public ulpManager;

    address public unityVester;
    address public ulpVester;

    mapping (address => address) public pendingReceivers;

    event StakeUnity(address account, address token, uint256 amount);
    event UnstakeUnity(address account, address token, uint256 amount);

    event StakeUlp(address account, uint256 amount);
    event UnstakeUlp(address account, uint256 amount);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    function initialize(
        address _weth,
        address _unity,
        address _esUnity,
        address _bnUnity,
        address _ulp,
        address _stakedUnityTracker,
        address _bonusUnityTracker,
        address _feeUnityTracker,
        address _feeUlpTracker,
        address _stakedUlpTracker,
        address _ulpManager,
        address _unityVester,
        address _ulpVester
    ) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;

        weth = _weth;

        unity = _unity;
        esUnity = _esUnity;
        bnUnity = _bnUnity;

        ulp = _ulp;

        stakedUnityTracker = _stakedUnityTracker;
        bonusUnityTracker = _bonusUnityTracker;
        feeUnityTracker = _feeUnityTracker;

        feeUlpTracker = _feeUlpTracker;
        stakedUlpTracker = _stakedUlpTracker;

        ulpManager = _ulpManager;

        unityVester = _unityVester;
        ulpVester = _ulpVester;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function batchStakeUnityForAccount(address[] memory _accounts, uint256[] memory _amounts) external nonReentrant onlyGov {
        address _unity = unity;
        for (uint256 i = 0; i < _accounts.length; i++) {
            _stakeUnity(msg.sender, _accounts[i], _unity, _amounts[i]);
        }
    }

    function stakeUnityForAccount(address _account, uint256 _amount) external nonReentrant onlyGov {
        _stakeUnity(msg.sender, _account, unity, _amount);
    }

    function stakeUnity(uint256 _amount) external nonReentrant {
        _stakeUnity(msg.sender, msg.sender, unity, _amount);
    }

    function stakeEsUnity(uint256 _amount) external nonReentrant {
        _stakeUnity(msg.sender, msg.sender, esUnity, _amount);
    }

    function unstakeUnity(uint256 _amount) external nonReentrant {
        _unstakeUnity(msg.sender, unity, _amount, true);
    }

    function unstakeEsUnity(uint256 _amount) external nonReentrant {
        _unstakeUnity(msg.sender, esUnity, _amount, true);
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

        address account = msg.sender;
        IRewardTracker(stakedUlpTracker).unstakeForAccount(account, feeUlpTracker, _ulpAmount, account);
        IRewardTracker(feeUlpTracker).unstakeForAccount(account, ulp, _ulpAmount, account);
        uint256 amountOut = IUlpManager(ulpManager).removeLiquidityForAccount(account, _tokenOut, _ulpAmount, _minOut, _receiver);

        emit UnstakeUlp(account, _ulpAmount);

        return amountOut;
    }

    function unstakeAndRedeemUlpETH(uint256 _ulpAmount, uint256 _minOut, address payable _receiver) external nonReentrant returns (uint256) {
        require(_ulpAmount > 0, "RewardRouter: invalid _ulpAmount");

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

        IRewardTracker(feeUnityTracker).claimForAccount(account, account);
        IRewardTracker(feeUlpTracker).claimForAccount(account, account);

        IRewardTracker(stakedUnityTracker).claimForAccount(account, account);
        IRewardTracker(stakedUlpTracker).claimForAccount(account, account);
    }

    function claimEsUnity() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(stakedUnityTracker).claimForAccount(account, account);
        IRewardTracker(stakedUlpTracker).claimForAccount(account, account);
    }

    function claimFees() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeUnityTracker).claimForAccount(account, account);
        IRewardTracker(feeUlpTracker).claimForAccount(account, account);
    }

    function compound() external nonReentrant {
        _compound(msg.sender);
    }

    function compoundForAccount(address _account) external nonReentrant onlyGov {
        _compound(_account);
    }

    function handleRewards(
        bool _shouldClaimUnity,
        bool _shouldStakeUnity,
        bool _shouldClaimEsUnity,
        bool _shouldStakeEsUnity,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external nonReentrant {
        address account = msg.sender;

        uint256 unityAmount = 0;
        if (_shouldClaimUnity) {
            uint256 unityAmount0 = IVester(unityVester).claimForAccount(account, account);
            uint256 unityAmount1 = IVester(ulpVester).claimForAccount(account, account);
            unityAmount = unityAmount0.add(unityAmount1);
        }

        if (_shouldStakeUnity && unityAmount > 0) {
            _stakeUnity(account, account, unity, unityAmount);
        }

        uint256 esUnityAmount = 0;
        if (_shouldClaimEsUnity) {
            uint256 esUnityAmount0 = IRewardTracker(stakedUnityTracker).claimForAccount(account, account);
            uint256 esUnityAmount1 = IRewardTracker(stakedUlpTracker).claimForAccount(account, account);
            esUnityAmount = esUnityAmount0.add(esUnityAmount1);
        }

        if (_shouldStakeEsUnity && esUnityAmount > 0) {
            _stakeUnity(account, account, esUnity, esUnityAmount);
        }

        if (_shouldStakeMultiplierPoints) {
            uint256 bnUnityAmount = IRewardTracker(bonusUnityTracker).claimForAccount(account, account);
            if (bnUnityAmount > 0) {
                IRewardTracker(feeUnityTracker).stakeForAccount(account, account, bnUnity, bnUnityAmount);
            }
        }

        if (_shouldClaimWeth) {
            if (_shouldConvertWethToEth) {
                uint256 weth0 = IRewardTracker(feeUnityTracker).claimForAccount(account, address(this));
                uint256 weth1 = IRewardTracker(feeUlpTracker).claimForAccount(account, address(this));

                uint256 wethAmount = weth0.add(weth1);
                IWETH(weth).withdraw(wethAmount);

                payable(account).sendValue(wethAmount);
            } else {
                IRewardTracker(feeUnityTracker).claimForAccount(account, account);
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
        require(IERC20(unityVester).balanceOf(msg.sender) == 0, "RewardRouter: sender has vested tokens");
        require(IERC20(ulpVester).balanceOf(msg.sender) == 0, "RewardRouter: sender has vested tokens");

        _validateReceiver(_receiver);
        pendingReceivers[msg.sender] = _receiver;
    }

    function acceptTransfer(address _sender) external nonReentrant {
        require(IERC20(unityVester).balanceOf(_sender) == 0, "RewardRouter: sender has vested tokens");
        require(IERC20(ulpVester).balanceOf(_sender) == 0, "RewardRouter: sender has vested tokens");

        address receiver = msg.sender;
        require(pendingReceivers[_sender] == receiver, "RewardRouter: transfer not signalled");
        delete pendingReceivers[_sender];

        _validateReceiver(receiver);
        _compound(_sender);

        uint256 stakedUnity = IRewardTracker(stakedUnityTracker).depositBalances(_sender, unity);
        if (stakedUnity > 0) {
            _unstakeUnity(_sender, unity, stakedUnity, false);
            _stakeUnity(_sender, receiver, unity, stakedUnity);
        }

        uint256 stakedEsUnity = IRewardTracker(stakedUnityTracker).depositBalances(_sender, esUnity);
        if (stakedEsUnity > 0) {
            _unstakeUnity(_sender, esUnity, stakedEsUnity, false);
            _stakeUnity(_sender, receiver, esUnity, stakedEsUnity);
        }

        uint256 stakedBnUnity = IRewardTracker(feeUnityTracker).depositBalances(_sender, bnUnity);
        if (stakedBnUnity > 0) {
            IRewardTracker(feeUnityTracker).unstakeForAccount(_sender, bnUnity, stakedBnUnity, _sender);
            IRewardTracker(feeUnityTracker).stakeForAccount(_sender, receiver, bnUnity, stakedBnUnity);
        }

        uint256 esUnityBalance = IERC20(esUnity).balanceOf(_sender);
        if (esUnityBalance > 0) {
            IERC20(esUnity).transferFrom(_sender, receiver, esUnityBalance);
        }

        uint256 ulpAmount = IRewardTracker(feeUlpTracker).depositBalances(_sender, ulp);
        if (ulpAmount > 0) {
            IRewardTracker(stakedUlpTracker).unstakeForAccount(_sender, feeUlpTracker, ulpAmount, _sender);
            IRewardTracker(feeUlpTracker).unstakeForAccount(_sender, ulp, ulpAmount, _sender);

            IRewardTracker(feeUlpTracker).stakeForAccount(_sender, receiver, ulp, ulpAmount);
            IRewardTracker(stakedUlpTracker).stakeForAccount(receiver, receiver, feeUlpTracker, ulpAmount);
        }

        IVester(unityVester).transferStakeValues(_sender, receiver);
        IVester(ulpVester).transferStakeValues(_sender, receiver);
    }

    function _validateReceiver(address _receiver) private view {
        require(IRewardTracker(stakedUnityTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: stakedUnityTracker.averageStakedAmounts > 0");
        require(IRewardTracker(stakedUnityTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: stakedUnityTracker.cumulativeRewards > 0");

        require(IRewardTracker(bonusUnityTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: bonusUnityTracker.averageStakedAmounts > 0");
        require(IRewardTracker(bonusUnityTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: bonusUnityTracker.cumulativeRewards > 0");

        require(IRewardTracker(feeUnityTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: feeUnityTracker.averageStakedAmounts > 0");
        require(IRewardTracker(feeUnityTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: feeUnityTracker.cumulativeRewards > 0");

        require(IVester(unityVester).transferredAverageStakedAmounts(_receiver) == 0, "RewardRouter: unityVester.transferredAverageStakedAmounts > 0");
        require(IVester(unityVester).transferredCumulativeRewards(_receiver) == 0, "RewardRouter: unityVester.transferredCumulativeRewards > 0");

        require(IRewardTracker(stakedUlpTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: stakedUlpTracker.averageStakedAmounts > 0");
        require(IRewardTracker(stakedUlpTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: stakedUlpTracker.cumulativeRewards > 0");

        require(IRewardTracker(feeUlpTracker).averageStakedAmounts(_receiver) == 0, "RewardRouter: feeUlpTracker.averageStakedAmounts > 0");
        require(IRewardTracker(feeUlpTracker).cumulativeRewards(_receiver) == 0, "RewardRouter: feeUlpTracker.cumulativeRewards > 0");

        require(IVester(ulpVester).transferredAverageStakedAmounts(_receiver) == 0, "RewardRouter: unityVester.transferredAverageStakedAmounts > 0");
        require(IVester(ulpVester).transferredCumulativeRewards(_receiver) == 0, "RewardRouter: unityVester.transferredCumulativeRewards > 0");

        require(IERC20(unityVester).balanceOf(_receiver) == 0, "RewardRouter: unityVester.balance > 0");
        require(IERC20(ulpVester).balanceOf(_receiver) == 0, "RewardRouter: ulpVester.balance > 0");
    }

    function _compound(address _account) private {
        _compoundUnity(_account);
        _compoundUlp(_account);
    }

    function _compoundUnity(address _account) private {
        uint256 esUnityAmount = IRewardTracker(stakedUnityTracker).claimForAccount(_account, _account);
        if (esUnityAmount > 0) {
            _stakeUnity(_account, _account, esUnity, esUnityAmount);
        }

        uint256 bnUnityAmount = IRewardTracker(bonusUnityTracker).claimForAccount(_account, _account);
        if (bnUnityAmount > 0) {
            IRewardTracker(feeUnityTracker).stakeForAccount(_account, _account, bnUnity, bnUnityAmount);
        }
    }

    function _compoundUlp(address _account) private {
        uint256 esUnityAmount = IRewardTracker(stakedUlpTracker).claimForAccount(_account, _account);
        if (esUnityAmount > 0) {
            _stakeUnity(_account, _account, esUnity, esUnityAmount);
        }
    }

    function _stakeUnity(address _fundingAccount, address _account, address _token, uint256 _amount) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        IRewardTracker(stakedUnityTracker).stakeForAccount(_fundingAccount, _account, _token, _amount);
        IRewardTracker(bonusUnityTracker).stakeForAccount(_account, _account, stakedUnityTracker, _amount);
        IRewardTracker(feeUnityTracker).stakeForAccount(_account, _account, bonusUnityTracker, _amount);

        emit StakeUnity(_account, _token, _amount);
    }

    function _unstakeUnity(address _account, address _token, uint256 _amount, bool _shouldReduceBnUnity) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        uint256 balance = IRewardTracker(stakedUnityTracker).stakedAmounts(_account);

        IRewardTracker(feeUnityTracker).unstakeForAccount(_account, bonusUnityTracker, _amount, _account);
        IRewardTracker(bonusUnityTracker).unstakeForAccount(_account, stakedUnityTracker, _amount, _account);
        IRewardTracker(stakedUnityTracker).unstakeForAccount(_account, _token, _amount, _account);

        if (_shouldReduceBnUnity) {
            uint256 bnUnityAmount = IRewardTracker(bonusUnityTracker).claimForAccount(_account, _account);
            if (bnUnityAmount > 0) {
                IRewardTracker(feeUnityTracker).stakeForAccount(_account, _account, bnUnity, bnUnityAmount);
            }

            uint256 stakedBnUnity = IRewardTracker(feeUnityTracker).depositBalances(_account, bnUnity);
            if (stakedBnUnity > 0) {
                uint256 reductionAmount = stakedBnUnity.mul(_amount).div(balance);
                IRewardTracker(feeUnityTracker).unstakeForAccount(_account, bnUnity, reductionAmount, _account);
                IMintable(bnUnity).burn(_account, reductionAmount);
            }
        }

        emit UnstakeUnity(_account, _token, _amount);
    }
}

