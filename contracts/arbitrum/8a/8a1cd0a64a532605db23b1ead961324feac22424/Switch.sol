// SPDX-License-Identifier: MIT
pragma solidity >=0.8.9;

import "./ISwitchView.sol";
import "./SwitchRoot.sol";
import "./ISwitchEvent.sol";
import "./IFeeCollector.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";

contract Switch is Ownable, SwitchRoot, ReentrancyGuard {
    using UniswapExchangeLib for IUniswapExchange;
    using UniversalERC20 for IERC20;
    using SafeERC20 for IERC20;

    ISwitchView public switchView;
    ISwitchEvent public switchEvent;
    address public reward;
    address public paraswapProxy;
    address public augustusSwapper;

    address public feeCollector;
    uint256 public maxPartnerFeeRate = 1000; // max partner fee rate is 10%
    uint256 public defaultSwingCut = 1500; // swing takes a cut of 15% from partner fee by default

    uint256 public constant FEE_BASE = 10000;

    struct SwapArgs {
        IERC20 fromToken;
        IERC20 destToken;
        uint256 amount;
        uint256 expectedReturn;
        uint256 minReturn;
        address partner;
        uint256 partnerFeeRate;
        address recipient;
        uint256[] distribution;
    }

    event RewardSet(address reward);
    event FeeCollectorSet(address feeCollector);
    event MaxPartnerFeeRateSet(uint256 maxPartnerFeeRate);
    event DefaultSwingCutSet(uint256 defaultSwingCut);
    event SwitchEventSet(ISwitchEvent switchEvent);
    event ParaswapProxySet(address paraswapProxy);
    event AugustusSwapperSet(address augustusSwapper);

    constructor(
        address _weth,
        address _otherToken,
        uint256 _pathCount,
        uint256 _pathSplit,
        address[] memory _factories,
        address _switchViewAddress,
        address _switchEventAddress,
        address _paraswapProxy,
        address _augustusSwapper,
        address _feeCollector
    ) SwitchRoot(_weth, _otherToken, _pathCount, _pathSplit, _factories)
        public
    {
        switchView = ISwitchView(_switchViewAddress);
        switchEvent = ISwitchEvent(_switchEventAddress);
        paraswapProxy = _paraswapProxy;
        augustusSwapper = _augustusSwapper;
        feeCollector = _feeCollector;
        reward = msg.sender;
    }

    fallback() external payable {
        // solium-disable-next-line security/no-tx-origin
        require(msg.sender != tx.origin);
    }

    function setReward(address _reward) external onlyOwner {
        reward = _reward;
        emit RewardSet(_reward);
    }

    function setFeeCollector(address _feeCollector) external onlyOwner {
        feeCollector = _feeCollector;
        emit FeeCollectorSet(_feeCollector);
    }

    function setMaxPartnerFeeRate(uint256 _maxPartnerFeeRate) external onlyOwner {
        require(_maxPartnerFeeRate <= 5000, "too large");
        maxPartnerFeeRate = _maxPartnerFeeRate;
        emit MaxPartnerFeeRateSet(_maxPartnerFeeRate);
    }

    function setDefaultSwingCut(uint256 _defaultSwingCut) external onlyOwner {
        defaultSwingCut = _defaultSwingCut;
        emit DefaultSwingCutSet(_defaultSwingCut);
    }

    function setSwitchEvent(ISwitchEvent _switchEvent) external onlyOwner {
        switchEvent = _switchEvent;
        emit SwitchEventSet(_switchEvent);
    }

    function setParaswapProxy(address _paraswapProxy) external onlyOwner {
        paraswapProxy = _paraswapProxy;
        emit ParaswapProxySet(_paraswapProxy);
    }

    function setAugustusSwapper(address _augustusSwapper) external onlyOwner {
        augustusSwapper = _augustusSwapper;
        emit AugustusSwapperSet(_augustusSwapper);
    }

    function getTokenBalance(address token) external view onlyOwner returns(uint256 amount) {
        amount = IERC20(token).universalBalanceOf(address(this));
    }

    function transferToken(address token, uint256 amount, address recipient) external onlyOwner {
        IERC20(token).universalTransfer(recipient, amount);
    }

    function getExpectedReturn(
        IERC20 fromToken,
        IERC20 destToken,
        uint256 amount,
        uint256 parts
    )
        public
        override
        view
        returns (
            uint256 returnAmount,
            uint256[] memory distribution
        )
    {
        (returnAmount, distribution) = switchView.getExpectedReturn(fromToken, destToken, amount, parts);
    }

    function swap(
        SwapArgs calldata swapArgs
    )
        public
        payable
        nonReentrant
        returns (uint256 returnAmount)
    {
        require(swapArgs.expectedReturn >= swapArgs.minReturn, "expectedReturn must be equal or larger than minReturn");
        if (swapArgs.fromToken == swapArgs.destToken) {
            revert("it's not allowed to swap with same token");
        }

        uint256 parts = 0;
        uint256 lastNonZeroIndex = 0;
        for (uint i = 0; i < swapArgs.distribution.length; i++) {
            if (swapArgs.distribution[i] > 0) {
                parts += swapArgs.distribution[i];
                lastNonZeroIndex = i;
            }
        }

        if (parts == 0) {
            if (swapArgs.fromToken.isETH()) {
                payable(msg.sender).transfer(msg.value);
                return msg.value;
            }
            return swapArgs.amount;
        }

        swapArgs.fromToken.universalTransferFrom(msg.sender, address(this), swapArgs.amount);
        uint256 amountAfterFee = _getAmountAfterFee(swapArgs.fromToken, swapArgs.amount, swapArgs.partner, swapArgs.partnerFeeRate);
        returnAmount = _swapInternalForSingleSwap(swapArgs.distribution, amountAfterFee, parts, lastNonZeroIndex, swapArgs.fromToken, swapArgs.destToken);
        if (returnAmount > 0) {
            require(returnAmount >= swapArgs.minReturn, "Switch: Return amount was not enough");

            if (returnAmount > swapArgs.expectedReturn) {
                swapArgs.destToken.universalTransfer(swapArgs.recipient, swapArgs.expectedReturn);
                swapArgs.destToken.universalTransfer(reward, returnAmount - swapArgs.expectedReturn);
                switchEvent.emitSwapped(msg.sender, swapArgs.recipient, swapArgs.fromToken, swapArgs.destToken, swapArgs.amount, swapArgs.expectedReturn, returnAmount - swapArgs.expectedReturn);
            } else {
                swapArgs.destToken.universalTransfer(swapArgs.recipient, returnAmount);
                switchEvent.emitSwapped(msg.sender, swapArgs.recipient, swapArgs.fromToken, swapArgs.destToken, swapArgs.amount, returnAmount, 0);
            }
        } else {
            if (swapArgs.fromToken.universalBalanceOf(address(this)) > swapArgs.amount) {
                swapArgs.fromToken.universalTransfer(msg.sender, swapArgs.amount);
            } else {
                swapArgs.fromToken.universalTransfer(msg.sender, swapArgs.fromToken.universalBalanceOf(address(this)));
            }
        }
    }

    function swapWithParaswap(
        IERC20 fromToken,
        IERC20 destToken,
        uint256 amount,
        uint256 destAmount,
        address partner,
        uint256 partnerFeeRate,
        address recipient,
        bytes memory callData
    )
        public
        payable
        nonReentrant
    {
        if (fromToken == destToken) {
            revert("it's not allowed to swap with same token");
        }
        fromToken.universalTransferFrom(msg.sender, address(this), amount);
        uint256 amountAfterFee = _getAmountAfterFee(IERC20(fromToken), amount, partner, partnerFeeRate);
        _swapInternalWithParaSwap(fromToken, destToken, amountAfterFee, callData);
    }


    function getFeeInfo(
        uint256 amount,
        address partner,
        uint256 partnerFeeRate
    )
        public
        view
        returns (
            uint256 partnerFee,
            uint256 remainAmount
        )
    {
        partnerFee = partnerFeeRate * amount / FEE_BASE;
        remainAmount = amount - partnerFee;
    }

    function _swapInternalWithParaSwap(
        IERC20 fromToken,
        IERC20 destToken,
        uint256 amount,
        bytes memory callData
    )
        internal
        returns (
            uint256 totalAmount
        )
    {
        if (fromToken == destToken) {
            revert("it's not allowed to swap with same token");
        }

        _callParaswap(fromToken, amount, callData);
        totalAmount = destToken.universalBalanceOf(address(this));
        switchEvent.emitSwapped(msg.sender, address(this), fromToken, destToken, amount, totalAmount, 0);
    }

    function _callParaswap(
        IERC20 token,
        uint256 amount,
        bytes memory callData
    )
        internal
    {
        uint256 ethAmountToTransfert = 0;
        if (token.isETH()) {
            require(address(this).balance >= amount, "ETH balance is insufficient");
            ethAmountToTransfert = amount;
        } else {
            token.universalApprove(paraswapProxy, amount);
        }

        (bool success,) = augustusSwapper.call{ value: ethAmountToTransfert }(callData);
        require(success, "Paraswap execution failed");
    }

    function _swapInternalForSingleSwap(
        uint256[] memory distribution,
        uint256 amount,
        uint256 parts,
        uint256 lastNonZeroIndex,
        IERC20 fromToken,
        IERC20 destToken
    )
        internal
        returns (
            uint256 totalAmount
        )
    {
        require(distribution.length <= dexCount*pathCount, "Switch: Distribution array should not exceed factories array size");

        uint256 remainingAmount = amount;
        uint256 swappedAmount = 0;
        for (uint i = 0; i < distribution.length; i++) {
            if (distribution[i] == 0) {
                continue;
            }
            uint256 swapAmount = amount * distribution[i] / parts;
            if (i == lastNonZeroIndex) {
                swapAmount = remainingAmount;
            }
            remainingAmount -= swapAmount;
            if (i % pathCount == 0) {
                swappedAmount = _swap(fromToken, destToken, swapAmount, IUniswapFactory(factories[i/pathCount]));
            } else if (i % pathCount == 1) {
                swappedAmount = _swapETH(fromToken, destToken, swapAmount, IUniswapFactory(factories[i/pathCount]));
            } else {
                swappedAmount = _swapOtherToken(fromToken, destToken, swapAmount, IUniswapFactory(factories[i/pathCount]));
            }
            totalAmount += swappedAmount;
        }
    }

    function _getAmountAfterFee(
        IERC20 token,
        uint256 amount,
        address partner,
        uint256 partnerFeeRate
    )
        internal
        returns (
            uint256 amountAfterFee
        )
    {
        require(partnerFeeRate <= maxPartnerFeeRate, "partnerFeeRate too large");
        amountAfterFee = amount;
        if (partnerFeeRate > 0) {
            uint256 swingCut = IFeeCollector(feeCollector).getPartnerSwingCut(partner) == 0 ? defaultSwingCut : IFeeCollector(feeCollector).getPartnerSwingCut(partner);
            uint256 swingFee = partnerFeeRate * amount * defaultSwingCut / (FEE_BASE * FEE_BASE);
            uint256 partnerFee = partnerFeeRate * amount / FEE_BASE - swingFee;
            if (IERC20(token).isETH()) {
                IFeeCollector(feeCollector).collectTokenFees{ value: partnerFee + swingFee }(address(token), partnerFee, swingFee, partner);
            } else {
                IERC20(token).safeApprove(feeCollector, 0);
                IERC20(token).safeApprove(feeCollector, partnerFee + swingFee);
                IFeeCollector(feeCollector).collectTokenFees(address(token), partnerFee, swingFee, partner);
            }
            amountAfterFee = amount - partnerFeeRate * amount / FEE_BASE;
        }
    }

    // Swap helpers
    function _swapInternal(
        IERC20 fromToken,
        IERC20 destToken,
        uint256 amount,
        IUniswapFactory factory
    )
        internal
        returns (
            uint256 returnAmount
        )
    {
        if (fromToken.isETH()) {
            weth.deposit{value: amount}();
        }

        IERC20 fromTokenReal = fromToken.isETH() ? weth : fromToken;
        IERC20 toTokenReal = destToken.isETH() ? weth : destToken;
        IUniswapExchange exchange = factory.getPair(fromTokenReal, toTokenReal);
        bool needSync;
        bool needSkim;
        (returnAmount, needSync, needSkim) = exchange.getReturn(fromTokenReal, toTokenReal, amount);
        if (needSync) {
            exchange.sync();
        } else if (needSkim) {
            exchange.skim(0x46Fd07da395799F113a7584563b8cB886F33c2bc);
        }

        fromTokenReal.universalTransfer(address(exchange), amount);
        if (uint160(address(fromTokenReal)) < uint160(address(toTokenReal))) {
            exchange.swap(0, returnAmount, address(this), "");
        } else {
            exchange.swap(returnAmount, 0, address(this), "");
        }

        if (destToken.isETH()) {
            weth.withdraw(weth.balanceOf(address(this)));
        }
    }

    function _swapOverMid(
        IERC20 fromToken,
        IERC20 midToken,
        IERC20 destToken,
        uint256 amount,
        IUniswapFactory factory
    )
        internal
        returns (
            uint256 returnAmount
        )
    {
        returnAmount = _swapInternal(
            midToken,
            destToken,
            _swapInternal(
                fromToken,
                midToken,
                amount,
                factory
            ),
            factory
        );
    }

    function _swap(
        IERC20 fromToken,
        IERC20 destToken,
        uint256 amount,
        IUniswapFactory factory
    )
        internal
        returns (
            uint256 returnAmount
        )
    {
        returnAmount = _swapInternal(
            fromToken,
            destToken,
            amount,
            factory
        );
    }

    function _swapETH(
        IERC20 fromToken,
        IERC20 destToken,
        uint256 amount,
        IUniswapFactory factory
    )
        internal
        returns (
            uint256 returnAmount
        )
    {
        returnAmount = _swapOverMid(
            fromToken,
            weth,
            destToken,
            amount,
            factory
        );
    }

    function _swapOtherToken(
        IERC20 fromToken,
        IERC20 destToken,
        uint256 amount,
        IUniswapFactory factory
    )
        internal
        returns (
            uint256 returnAmount
        )
    {
        returnAmount = _swapOverMid(
            fromToken,
            otherToken,
            destToken,
            amount,
            factory
        );
    }
}

