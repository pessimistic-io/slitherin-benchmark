// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

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
import "./IXlpManager.sol";
import "./Governable.sol";

contract RewardRouterV2 is IRewardRouterV2, ReentrancyGuard, Governable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address payable;

    bool public isInitialized;

    address public weth;

    address public lex;
    address public esLex;
    address public bnLex;

    address public xlp; // LEX Liquidity Provider token

    address public stakedLexTracker;
    address public bonusLexTracker;
    address public feeLexTracker;

    address public override stakedXlpTracker;
    address public override feeXlpTracker;

    address public xlpManager;

    address public lexVester;
    address public xlpVester;

    mapping(address => address) public pendingReceivers;

    event StakeLex(address account, address token, uint256 amount);
    event UnstakeLex(address account, address token, uint256 amount);

    event StakeXlp(address account, uint256 amount);
    event UnstakeXlp(address account, uint256 amount);

    receive() external payable {
        require(msg.sender == weth, "Router: invalid sender");
    }

    function initialize(
        address _weth,
        address _lex,
        address _esLex,
        address _bnLex,
        address _xlp,
        address _stakedLexTracker,
        address _bonusLexTracker,
        address _feeLexTracker,
        address _feeXlpTracker,
        address _stakedXlpTracker,
        address _xlpManager,
        address _lexVester,
        address _xlpVester
    ) external onlyGov {
        require(!isInitialized, "RewardRouter: already initialized");
        isInitialized = true;

        weth = _weth;

        lex = _lex;
        esLex = _esLex;
        bnLex = _bnLex;

        xlp = _xlp;

        stakedLexTracker = _stakedLexTracker;
        bonusLexTracker = _bonusLexTracker;
        feeLexTracker = _feeLexTracker;

        feeXlpTracker = _feeXlpTracker;
        stakedXlpTracker = _stakedXlpTracker;

        xlpManager = _xlpManager;

        lexVester = _lexVester;
        xlpVester = _xlpVester;
    }

    // to help users who accidentally send their tokens to this contract
    function withdrawToken(address _token, address _account, uint256 _amount) external onlyGov {
        IERC20(_token).safeTransfer(_account, _amount);
    }

    function batchStakeLexForAccount(
        address[] memory _accounts,
        uint256[] memory _amounts
    ) external nonReentrant onlyGov {
        address _lex = lex;
        for (uint256 i = 0; i < _accounts.length; i++) {
            _stakeLex(msg.sender, _accounts[i], _lex, _amounts[i]);
        }
    }

    function stakeLexForAccount(address _account, uint256 _amount) external nonReentrant onlyGov {
        _stakeLex(msg.sender, _account, lex, _amount);
    }

    function stakeLex(uint256 _amount) external nonReentrant {
        _stakeLex(msg.sender, msg.sender, lex, _amount);
    }

    function stakeEsLex(uint256 _amount) external nonReentrant {
        _stakeLex(msg.sender, msg.sender, esLex, _amount);
    }

    function unstakeLex(uint256 _amount) external nonReentrant {
        _unstakeLex(msg.sender, lex, _amount, true);
    }

    function unstakeEsLex(uint256 _amount) external nonReentrant {
        _unstakeLex(msg.sender, esLex, _amount, true);
    }

    function mintAndStakeXlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minXlp
    ) external nonReentrant returns (uint256) {
        require(_amount > 0, "RewardRouter: invalid _amount");

        address account = msg.sender;
        uint256 xlpAmount = IXlpManager(xlpManager).addLiquidityForAccount(
            account,
            account,
            _token,
            _amount,
            _minUsdg,
            _minXlp
        );
        IRewardTracker(feeXlpTracker).stakeForAccount(account, account, xlp, xlpAmount);
        IRewardTracker(stakedXlpTracker).stakeForAccount(
            account,
            account,
            feeXlpTracker,
            xlpAmount
        );

        emit StakeXlp(account, xlpAmount);

        return xlpAmount;
    }

    function mintAndStakeXlpETH(
        uint256 _minUsdg,
        uint256 _minXlp
    ) external payable nonReentrant returns (uint256) {
        require(msg.value > 0, "RewardRouter: invalid msg.value");

        IWETH(weth).deposit{ value: msg.value }();
        IERC20(weth).approve(xlpManager, msg.value);

        address account = msg.sender;
        uint256 xlpAmount = IXlpManager(xlpManager).addLiquidityForAccount(
            address(this),
            account,
            weth,
            msg.value,
            _minUsdg,
            _minXlp
        );

        IRewardTracker(feeXlpTracker).stakeForAccount(account, account, xlp, xlpAmount);
        IRewardTracker(stakedXlpTracker).stakeForAccount(
            account,
            account,
            feeXlpTracker,
            xlpAmount
        );

        emit StakeXlp(account, xlpAmount);

        return xlpAmount;
    }

    function unstakeAndRedeemXlp(
        address _tokenOut,
        uint256 _xlpAmount,
        uint256 _minOut,
        address _receiver
    ) external nonReentrant returns (uint256) {
        require(_xlpAmount > 0, "RewardRouter: invalid _xlpAmount");

        address account = msg.sender;
        IRewardTracker(stakedXlpTracker).unstakeForAccount(
            account,
            feeXlpTracker,
            _xlpAmount,
            account
        );
        IRewardTracker(feeXlpTracker).unstakeForAccount(account, xlp, _xlpAmount, account);
        uint256 amountOut = IXlpManager(xlpManager).removeLiquidityForAccount(
            account,
            _tokenOut,
            _xlpAmount,
            _minOut,
            _receiver
        );

        emit UnstakeXlp(account, _xlpAmount);

        return amountOut;
    }

    function unstakeAndRedeemXlpETH(
        uint256 _xlpAmount,
        uint256 _minOut,
        address payable _receiver
    ) external nonReentrant returns (uint256) {
        require(_xlpAmount > 0, "RewardRouter: invalid _xlpAmount");

        address account = msg.sender;
        IRewardTracker(stakedXlpTracker).unstakeForAccount(
            account,
            feeXlpTracker,
            _xlpAmount,
            account
        );
        IRewardTracker(feeXlpTracker).unstakeForAccount(account, xlp, _xlpAmount, account);
        uint256 amountOut = IXlpManager(xlpManager).removeLiquidityForAccount(
            account,
            weth,
            _xlpAmount,
            _minOut,
            address(this)
        );

        IWETH(weth).withdraw(amountOut);

        _receiver.sendValue(amountOut);

        emit UnstakeXlp(account, _xlpAmount);

        return amountOut;
    }

    function claim() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeLexTracker).claimForAccount(account, account);
        IRewardTracker(feeXlpTracker).claimForAccount(account, account);

        IRewardTracker(stakedLexTracker).claimForAccount(account, account);
        IRewardTracker(stakedXlpTracker).claimForAccount(account, account);
    }

    function claimEsLex() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(stakedLexTracker).claimForAccount(account, account);
        IRewardTracker(stakedXlpTracker).claimForAccount(account, account);
    }

    function claimFees() external nonReentrant {
        address account = msg.sender;

        IRewardTracker(feeLexTracker).claimForAccount(account, account);
        IRewardTracker(feeXlpTracker).claimForAccount(account, account);
    }

    function compound() external nonReentrant {
        _compound(msg.sender);
    }

    function compoundForAccount(address _account) external nonReentrant onlyGov {
        _compound(_account);
    }

    function handleRewards(
        bool _shouldClaimLex,
        bool _shouldStakeLex,
        bool _shouldClaimEsLex,
        bool _shouldStakeEsLex,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external nonReentrant {
        address account = msg.sender;

        uint256 lexAmount = 0;
        if (_shouldClaimLex) {
            uint256 lexAmount0 = IVester(lexVester).claimForAccount(account, account);
            uint256 lexAmount1 = IVester(xlpVester).claimForAccount(account, account);
            lexAmount = lexAmount0.add(lexAmount1);
        }

        if (_shouldStakeLex && lexAmount > 0) {
            _stakeLex(account, account, lex, lexAmount);
        }

        uint256 esLexAmount = 0;
        if (_shouldClaimEsLex) {
            uint256 esLexAmount0 = IRewardTracker(stakedLexTracker).claimForAccount(
                account,
                account
            );
            uint256 esLexAmount1 = IRewardTracker(stakedXlpTracker).claimForAccount(
                account,
                account
            );
            esLexAmount = esLexAmount0.add(esLexAmount1);
        }

        if (_shouldStakeEsLex && esLexAmount > 0) {
            _stakeLex(account, account, esLex, esLexAmount);
        }

        if (_shouldStakeMultiplierPoints) {
            uint256 bnLexAmount = IRewardTracker(bonusLexTracker).claimForAccount(account, account);
            if (bnLexAmount > 0) {
                IRewardTracker(feeLexTracker).stakeForAccount(account, account, bnLex, bnLexAmount);
            }
        }

        if (_shouldClaimWeth) {
            if (_shouldConvertWethToEth) {
                uint256 weth0 = IRewardTracker(feeLexTracker).claimForAccount(
                    account,
                    address(this)
                );
                uint256 weth1 = IRewardTracker(feeXlpTracker).claimForAccount(
                    account,
                    address(this)
                );

                uint256 wethAmount = weth0.add(weth1);
                IWETH(weth).withdraw(wethAmount);

                payable(account).sendValue(wethAmount);
            } else {
                IRewardTracker(feeLexTracker).claimForAccount(account, account);
                IRewardTracker(feeXlpTracker).claimForAccount(account, account);
            }
        }
    }

    function batchCompoundForAccounts(address[] memory _accounts) external nonReentrant onlyGov {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _compound(_accounts[i]);
        }
    }

    // the _validateReceiver function checks that the averageStakedAmounts and cumulativeRewards
    // values of an account are zero, this is to help ensure that vesting calculations can be
    // done correctly
    // averageStakedAmounts and cumulativeRewards are updated if the claimable reward for an account
    // is more than zero
    // it is possible for multiple transfers to be sent into a single account, using signalTransfer and
    // acceptTransfer, if those values have not been updated yet
    // for XLP transfers it is also possible to transfer XLP into an account using the StakedXlp contract
    function signalTransfer(address _receiver) external nonReentrant {
        require(
            IERC20(lexVester).balanceOf(msg.sender) == 0,
            "RewardRouter: sender has vested tokens"
        );
        require(
            IERC20(xlpVester).balanceOf(msg.sender) == 0,
            "RewardRouter: sender has vested tokens"
        );

        _validateReceiver(_receiver);
        pendingReceivers[msg.sender] = _receiver;
    }

    function acceptTransfer(address _sender) external nonReentrant {
        require(
            IERC20(lexVester).balanceOf(_sender) == 0,
            "RewardRouter: sender has vested tokens"
        );
        require(
            IERC20(xlpVester).balanceOf(_sender) == 0,
            "RewardRouter: sender has vested tokens"
        );

        address receiver = msg.sender;
        require(pendingReceivers[_sender] == receiver, "RewardRouter: transfer not signalled");
        delete pendingReceivers[_sender];

        _validateReceiver(receiver);
        _compound(_sender);

        uint256 stakedLex = IRewardTracker(stakedLexTracker).depositBalances(_sender, lex);
        if (stakedLex > 0) {
            _unstakeLex(_sender, lex, stakedLex, false);
            _stakeLex(_sender, receiver, lex, stakedLex);
        }

        uint256 stakedEsLex = IRewardTracker(stakedLexTracker).depositBalances(_sender, esLex);
        if (stakedEsLex > 0) {
            _unstakeLex(_sender, esLex, stakedEsLex, false);
            _stakeLex(_sender, receiver, esLex, stakedEsLex);
        }

        uint256 stakedBnLex = IRewardTracker(feeLexTracker).depositBalances(_sender, bnLex);
        if (stakedBnLex > 0) {
            IRewardTracker(feeLexTracker).unstakeForAccount(_sender, bnLex, stakedBnLex, _sender);
            IRewardTracker(feeLexTracker).stakeForAccount(_sender, receiver, bnLex, stakedBnLex);
        }

        uint256 esLexBalance = IERC20(esLex).balanceOf(_sender);
        if (esLexBalance > 0) {
            IERC20(esLex).transferFrom(_sender, receiver, esLexBalance);
        }

        uint256 xlpAmount = IRewardTracker(feeXlpTracker).depositBalances(_sender, xlp);
        if (xlpAmount > 0) {
            IRewardTracker(stakedXlpTracker).unstakeForAccount(
                _sender,
                feeXlpTracker,
                xlpAmount,
                _sender
            );
            IRewardTracker(feeXlpTracker).unstakeForAccount(_sender, xlp, xlpAmount, _sender);

            IRewardTracker(feeXlpTracker).stakeForAccount(_sender, receiver, xlp, xlpAmount);
            IRewardTracker(stakedXlpTracker).stakeForAccount(
                receiver,
                receiver,
                feeXlpTracker,
                xlpAmount
            );
        }

        IVester(lexVester).transferStakeValues(_sender, receiver);
        IVester(xlpVester).transferStakeValues(_sender, receiver);
    }

    function _validateReceiver(address _receiver) private view {
        require(
            IRewardTracker(stakedLexTracker).averageStakedAmounts(_receiver) == 0,
            "RewardRouter: stakedLexTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(stakedLexTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: stakedLexTracker.cumulativeRewards > 0"
        );

        require(
            IRewardTracker(bonusLexTracker).averageStakedAmounts(_receiver) == 0,
            "RewardRouter: bonusLexTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(bonusLexTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: bonusLexTracker.cumulativeRewards > 0"
        );

        require(
            IRewardTracker(feeLexTracker).averageStakedAmounts(_receiver) == 0,
            "RewardRouter: feeLexTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(feeLexTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: feeLexTracker.cumulativeRewards > 0"
        );

        require(
            IVester(lexVester).transferredAverageStakedAmounts(_receiver) == 0,
            "RewardRouter: lexVester.transferredAverageStakedAmounts > 0"
        );
        require(
            IVester(lexVester).transferredCumulativeRewards(_receiver) == 0,
            "RewardRouter: lexVester.transferredCumulativeRewards > 0"
        );

        require(
            IRewardTracker(stakedXlpTracker).averageStakedAmounts(_receiver) == 0,
            "RewardRouter: stakedXlpTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(stakedXlpTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: stakedXlpTracker.cumulativeRewards > 0"
        );

        require(
            IRewardTracker(feeXlpTracker).averageStakedAmounts(_receiver) == 0,
            "RewardRouter: feeXlpTracker.averageStakedAmounts > 0"
        );
        require(
            IRewardTracker(feeXlpTracker).cumulativeRewards(_receiver) == 0,
            "RewardRouter: feeXlpTracker.cumulativeRewards > 0"
        );

        require(
            IVester(xlpVester).transferredAverageStakedAmounts(_receiver) == 0,
            "RewardRouter: lexVester.transferredAverageStakedAmounts > 0"
        );
        require(
            IVester(xlpVester).transferredCumulativeRewards(_receiver) == 0,
            "RewardRouter: lexVester.transferredCumulativeRewards > 0"
        );

        require(IERC20(lexVester).balanceOf(_receiver) == 0, "RewardRouter: lexVester.balance > 0");
        require(IERC20(xlpVester).balanceOf(_receiver) == 0, "RewardRouter: xlpVester.balance > 0");
    }

    function _compound(address _account) private {
        _compoundLex(_account);
        _compoundXlp(_account);
    }

    function _compoundLex(address _account) private {
        uint256 esLexAmount = IRewardTracker(stakedLexTracker).claimForAccount(_account, _account);
        if (esLexAmount > 0) {
            _stakeLex(_account, _account, esLex, esLexAmount);
        }

        uint256 bnLexAmount = IRewardTracker(bonusLexTracker).claimForAccount(_account, _account);
        if (bnLexAmount > 0) {
            IRewardTracker(feeLexTracker).stakeForAccount(_account, _account, bnLex, bnLexAmount);
        }
    }

    function _compoundXlp(address _account) private {
        uint256 esLexAmount = IRewardTracker(stakedXlpTracker).claimForAccount(_account, _account);
        if (esLexAmount > 0) {
            _stakeLex(_account, _account, esLex, esLexAmount);
        }
    }

    function _stakeLex(
        address _fundingAccount,
        address _account,
        address _token,
        uint256 _amount
    ) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        IRewardTracker(stakedLexTracker).stakeForAccount(
            _fundingAccount,
            _account,
            _token,
            _amount
        );
        IRewardTracker(bonusLexTracker).stakeForAccount(
            _account,
            _account,
            stakedLexTracker,
            _amount
        );
        IRewardTracker(feeLexTracker).stakeForAccount(_account, _account, bonusLexTracker, _amount);

        emit StakeLex(_account, _token, _amount);
    }

    function _unstakeLex(
        address _account,
        address _token,
        uint256 _amount,
        bool _shouldReduceBnLex
    ) private {
        require(_amount > 0, "RewardRouter: invalid _amount");

        uint256 balance = IRewardTracker(stakedLexTracker).stakedAmounts(_account);

        IRewardTracker(feeLexTracker).unstakeForAccount(
            _account,
            bonusLexTracker,
            _amount,
            _account
        );
        IRewardTracker(bonusLexTracker).unstakeForAccount(
            _account,
            stakedLexTracker,
            _amount,
            _account
        );
        IRewardTracker(stakedLexTracker).unstakeForAccount(_account, _token, _amount, _account);

        if (_shouldReduceBnLex) {
            uint256 bnLexAmount = IRewardTracker(bonusLexTracker).claimForAccount(
                _account,
                _account
            );
            if (bnLexAmount > 0) {
                IRewardTracker(feeLexTracker).stakeForAccount(
                    _account,
                    _account,
                    bnLex,
                    bnLexAmount
                );
            }

            uint256 stakedBnLex = IRewardTracker(feeLexTracker).depositBalances(_account, bnLex);
            if (stakedBnLex > 0) {
                uint256 reductionAmount = stakedBnLex.mul(_amount).div(balance);
                IRewardTracker(feeLexTracker).unstakeForAccount(
                    _account,
                    bnLex,
                    reductionAmount,
                    _account
                );
                IMintable(bnLex).burn(_account, reductionAmount);
            }
        }

        emit UnstakeLex(_account, _token, _amount);
    }
}

