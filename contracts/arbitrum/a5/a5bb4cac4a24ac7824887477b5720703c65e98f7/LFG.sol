// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./Ownable.sol";
import "./EnumerableSet.sol";
import "./SafeMath.sol";

import "./ERC20.sol";
import "./Pausable.sol";

interface IUniswapV2Factory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    )
        external
        payable
        returns (uint amountToken, uint amountETH, uint liquidity);
}

contract LFG is ERC20, Pausable, Ownable {
    using SafeMath for uint256;
    IUniswapV2Router02 private uniswapV2Router;
    address private WETH;

    mapping(address => bool) private pairs;
    uint8 private constant _decimals = 18;
    bool private inSwap = false;
    bool private tradingOpen = false;
    uint256 private tradingTime = 1684753200;
    address private uniswapV2Pair;
    bool private isSwapAndLp = false;

    address public _payee;

    uint256 public _burnFee = 0;
    uint256 public _liquidityFee = 60;

    bool public limited;
    uint256 public maxHoldingAmount;

    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor(
        uint256 _initialSupply,
        address _swap
    ) ERC20("LineFi Game Token", "LFG") {
        _mint(msg.sender, _initialSupply);
        _payee = msg.sender;

        uniswapV2Router = IUniswapV2Router02(_swap);
        WETH = uniswapV2Router.WETH();

        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
            address(this),
            WETH
        );

        pairs[uniswapV2Pair] = true;
    }

    function decimals() public pure override returns (uint8) {
        return _decimals;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setLimit(
        bool _limited,
        uint256 _maxHoldingAmount
    ) external onlyOwner {
        limited = _limited;
        maxHoldingAmount = _maxHoldingAmount;
    }

    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    function addPairs(address toPair, bool _enable) public onlyOwner {
        require(!pairs[toPair], "This pair is already excluded");

        pairs[toPair] = _enable;
    }

    function pair(address _pair) public view virtual onlyOwner returns (bool) {
        return pairs[_pair];
    }

    function setPayee(address payee) external onlyOwner {
        _payee = payee;
    }

    function setLiquidityFeePercent(uint256 liquidityFee) external onlyOwner {
        _liquidityFee = liquidityFee;
    }

    function setBurnFee(uint256 burnFee) external onlyOwner {
        _burnFee = burnFee;
    }

    function setIsSwapAndLp(bool _isSwapAndLp) external onlyOwner {
        isSwapAndLp = _isSwapAndLp;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override whenNotPaused {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        uint256 fromBalance = balanceOf(from);
        require(
            fromBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        if (!tradingOpen) {
            if (block.timestamp >= tradingTime) {
                tradingOpen = true;
            }
        }
        if (tradingOpen) {
            if (from != address(this) && pairs[to]) {
                uint256 burnAmount = amount.mul(_burnFee).div(10 ** 3);
                uint256 liquidityAmount = amount.mul(_liquidityFee).div(
                    10 ** 3
                );
                if (liquidityAmount > 0) {
                    _swapTransfer(from, address(this), liquidityAmount);
                }
                if (burnAmount > 0) {
                    _swapBurn(from, burnAmount);
                }
                if (liquidityAmount > 0) {
                    if (!isSwapAndLp) {
                        swapTokensForEth(liquidityAmount, _payee);
                    } else if (isSwapAndLp && !inSwap) {
                        swapAndLiquify(liquidityAmount);
                    }
                }

                super._transfer(
                    from,
                    to,
                    amount.sub(burnAmount).sub(liquidityAmount)
                );
            } else {
                if (limited && from == uniswapV2Pair) {
                    require(
                        super.balanceOf(to) + amount <= maxHoldingAmount,
                        "Forbid"
                    );
                }
                super._transfer(from, to, amount);
            }
        } else {
            if (to == uniswapV2Pair || from == uniswapV2Pair) {
                if (from == owner() || to == owner()) {
                    super._transfer(from, to, amount);
                } else {
                    require(false, "Trading isn't open");
                }
            } else {
                super._transfer(from, to, amount);
            }
        }
    }

    function manualswap() external onlyOwner {
        uint256 contractBalance = balanceOf(address(this));
        swapTokensForEth(contractBalance, _payee);
    }

    function manualBurn(uint256 amount) public virtual onlyOwner {
        _burn(address(this), amount);
    }

    function swapAndLiquify(uint256 _tokenBalance) private lockTheSwap {
        uint256 half = _tokenBalance.div(2);
        uint256 otherHalf = _tokenBalance.sub(half);
        uint256 initialBalance = address(this).balance;

        swapTokensForEth(half, address(this));
        addLiquidity(otherHalf, address(this).balance.sub(initialBalance));
    }

    function swapTokensForEth(
        uint256 tokenAmount,
        address to
    ) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WETH;

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            to,
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 _ethAmount) private {
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.addLiquidityETH{value: _ethAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            _payee,
            block.timestamp
        );
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    function setTrading(uint256 _tradingTime) external onlyOwner {
        tradingTime = _tradingTime;
    }

    function withdraw(address token) public onlyOwner {
        if (token == address(0)) {
            uint amount = address(this).balance;
            (bool success, ) = payable(_payee).call{value: amount}("");

            require(success, "Failed to send Ether");
        } else {
            uint256 amount = ERC20(token).balanceOf(address(this));
            ERC20(token).transfer(_payee, amount);
        }
    }

    receive() external payable {}
}

