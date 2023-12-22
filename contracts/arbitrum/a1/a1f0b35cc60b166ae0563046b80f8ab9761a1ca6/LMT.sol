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
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function factory() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

contract LMT is ERC20, Pausable, Ownable {
    using SafeMath for uint256;
    IUniswapV2Router02 private uniswapV2Router;
    address private USDT;

    mapping(address => bool) private pairs;
    uint256 public constant maxSupply = 1000000000 * 1e18;
    uint8 private constant _decimals = 18;
    bool private inSwap = false;
    bool private tradingOpen = false;
    uint256 private tradingTime = 1684926000;
    address private uniswapV2Pair;
    bool private isSwapAndLp = false;

    address public _payee;

    uint256 public _burnFee = 15;
    uint256 public _liquidityFee = 45;

    bool public limited;
    uint256 public maxHoldingAmount;

    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor(
        uint256 _initialSupply,
        address _swap,
        address _usdt
    ) ERC20("LineFi Metaverse Token", "LMT") {
        _mint(msg.sender, _initialSupply);
        _payee = msg.sender;

        uniswapV2Router = IUniswapV2Router02(_swap);

        USDT = _usdt;

        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
            address(this),
            USDT
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
        require(
            maxSupply >= _amount.add(totalSupply()),
            "Exceeded the total supply"
        );
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
                        swapTokensForUSDT(liquidityAmount, _payee);
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
        swapTokensForUSDT(contractBalance, _payee);
    }

    function manualBurn(uint256 amount) public virtual onlyOwner {
        _burn(address(this), amount);
    }

    function swapAndLiquify(uint256 _tokenBalance) private lockTheSwap {
        uint256 half = _tokenBalance.div(2);
        uint256 otherHalf = _tokenBalance.sub(half);
        uint256 initialBalance = ERC20(USDT).balanceOf(address(this));

        swapTokensForUSDT(half, address(this));
        addLiquidity(
            otherHalf,
            ERC20(USDT).balanceOf(address(this)).sub(initialBalance)
        );
    }

    function swapTokensForUSDT(
        uint256 tokenAmount,
        address to
    ) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = USDT;

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            to,
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 _usdtAmount) private {
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        ERC20(USDT).approve(address(uniswapV2Router), _usdtAmount);

        uniswapV2Router.addLiquidity(
            address(this),
            USDT,
            tokenAmount,
            _usdtAmount,
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

