// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "./IERC20.sol";
import "./SafeERC20.sol";

import "./IUniswapV2.sol";
import "./KobeOwnerChild.sol";
import "./IWETH.sol";
import "./IKobe.sol";

contract KobeReferralRouter is KobeOwnerChild {
    using SafeERC20 for IERC20;

    address private immutable KOBE;
    address private TREASURY;
    address private constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address private constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

    address private ethPair;
    address private usdtPair;

    bool private isWhitelisted = false;

    uint256 public reduceFeeBy;
    uint256 public referralFee;

    event SwapWithReferral(address indexed user, address indexed referral, address indexed sendTo, bool ethOrUsdt, uint256 amountIn, uint256 amountOut, uint256 refAmount, uint256 treasuryAmount);

    modifier verifyWhitelisted {
        if (!isWhitelisted) {
            isWhitelisted = IKobe(KOBE).isAddressWhitelisted(address(this));
            require(isWhitelisted, "Module not launched");
        }
        _;
    }

    constructor(
        address _treasury,
        address _kobe,
        address _registry,
        uint256 _reduceFeeBy,
        uint256 _referralFee
    ) KobeOwnerChild(_registry) {
        require(_referralFee <= _reduceFeeBy, "Fee too big");
        TREASURY = _treasury;
        KOBE = _kobe;

        ethPair = IKobe(_kobe).ethPair();
        usdtPair = IKobe(_kobe).usdtPair();

        uint256 _kobeBuyFee = IKobe(_kobe).buyFee();
        require(_reduceFeeBy <= _kobeBuyFee, "Fee bigger than buyFee");

        reduceFeeBy = _reduceFeeBy;
        referralFee = _referralFee;
    }

    function changeFees(uint256 _reduceFeeBy, uint256 _referralFee) external onlyOwner {
        require(_referralFee <= _reduceFeeBy, "Fee too big");
        uint256 _kobeBuyFee = IKobe(KOBE).buyFee();
        require(_reduceFeeBy <= _kobeBuyFee, "Fee bigger than buyFee");
        reduceFeeBy = _reduceFeeBy;
        referralFee = _referralFee;
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountOut) {
        uint amountInWithFee = amountIn * 997;
        uint numerator = amountInWithFee * reserveOut;
        uint denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function _doSwap(address _from, address _pair) internal {
        (address token0,) = sortTokens(_from, KOBE);
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(_pair).getReserves();
        (uint reserveInput, uint reserveOutput) = _from == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
        uint256 amountInput = IERC20(_from).balanceOf(_pair) - reserveInput;
        uint256 amountOutput = getAmountOut(amountInput, reserveInput, reserveOutput);
        (uint amount0Out, uint amount1Out) = _from == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
        IUniswapV2Pair(_pair).swap(amount0Out, amount1Out, address(this), new bytes(0));
    }

    function _buyWithEth() internal {
        uint256 _amt = address(this).balance;
        IWETH(WETH).deposit{value: _amt}();
        IERC20(WETH).safeTransfer(ethPair, _amt);
        _doSwap(WETH, ethPair);
    }

    function _buyWithUsdt() internal {
        _doSwap(USDT, usdtPair);
    }

    function buy(
        address _referral,
        bool _ethOrUsdt,
        uint256 _amount,
        address _to,
        uint256 _amountOutMin
    ) external payable verifyWhitelisted {
        require(_referral != msg.sender, "Cannot refer yourself");

        if (_ethOrUsdt) {
            IERC20(USDT).safeTransferFrom(msg.sender, usdtPair, _amount);
        } else {
            _amount = msg.value;
        }

        require(_amount > 0, "Amount 0");

        if (_ethOrUsdt) {
            _buyWithUsdt();
        } else {
            _buyWithEth();
        }

        // check amountOutMin
        uint256 _myBal = IERC20(KOBE).balanceOf(address(this));
        uint256 _originalBuyFee = IKobe(KOBE).buyFee();
        uint256 _reducedFee = _originalBuyFee - reduceFeeBy;
        
        uint256 _sendToTreasury = _myBal * _reducedFee / 10000;
        uint256 _sendToRef = _myBal * referralFee / 10000;
        uint256 _sendToUser = _myBal - _sendToTreasury - _sendToRef;
        require(_sendToUser >= _amountOutMin, "Slippage");

        if (_referral == address(0)) {
            IERC20(KOBE).safeTransfer(TREASURY, _sendToTreasury + _sendToRef);
        } else {
            IERC20(KOBE).safeTransfer(TREASURY, _sendToTreasury);
            IERC20(KOBE).safeTransfer(_referral, _sendToRef);
        }

        IERC20(KOBE).safeTransfer(_to, _sendToUser);

        emit SwapWithReferral(msg.sender, _referral, _to, _ethOrUsdt, _amount, _sendToUser, _sendToRef, _sendToTreasury);
    }

    receive() external payable {}
}
