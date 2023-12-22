// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./SafeMath.sol";
import "./Context.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./ERC20.sol";
import "./IERC20Metadata.sol";
import "./IUniswapFactory.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapRouter02.sol";

contract Moeta is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapRouter02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;

    bool private swapping;

    address public marketingFees;
    address public arbFees;
    address public smolFees;

    bool public limitsInEffect = true;
    bool public tradingActive = false;
    bool public swapEnabled = false;

    uint256 public buyTotalFees;
    uint256 public sellTotalFees;

    /******************/

    // exlcude from fees and max transaction amount
    mapping(address => bool) private _isExcludedFromFees;

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping(address => bool) public automatedMarketMakerPairs;

    event ExcludeFromFees(address indexed account, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    constructor(
        address _marketingFees,
        address _arbFees,
        address _smolFees
    ) ERC20("Moeta Coin", "MOETA") {
        IUniswapRouter02 _uniswapV2Router = IUniswapRouter02(
            0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506
        );
        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = IUniswapFactory(_uniswapV2Router.factory()).createPair(
            address(this),
            _uniswapV2Router.WETH()
        );
        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);

        // SETUP TOKEN DETAILS
        uint256 totalSupply = 100_000_000_000 * 1e9;

        // fees at beginning anti bot
        buyTotalFees = 10;
        sellTotalFees = 10;

        marketingFees = _marketingFees; // will receive marketing fees
        arbFees = _arbFees; // will recieve fees used to buy ARB
        smolFees = _smolFees; // will recieve fees used to buy smols

        // exclude from paying fees
        excludeFromFees(owner(), true);
        excludeFromFees(address(this), true);
        excludeFromFees(address(0xdead), true);

        _mint(msg.sender, totalSupply);
    }

    function decimals() public view virtual override returns (uint8) {
        return 9;
    }

    receive() external payable {}

    // once enabled, can never be turned off
    function enableTrading() external onlyOwner {
        tradingActive = true;
        swapEnabled = true;
    }

    // remove limits after token is stable
    function removeLimits() external onlyOwner {
        limitsInEffect = false;
        buyTotalFees = 3;
        sellTotalFees = 3;
    }

    function setFeesToNormal() external onlyOwner {
        buyTotalFees = 3;
        sellTotalFees = 3;
    }

    function updateBuyFees(uint256 _buyTotalFees) external onlyOwner {
        buyTotalFees = _buyTotalFees;
        require(buyTotalFees <= 3, "Must keep fees at 3% or less");
    }

    function updateSellFees(uint256 _sellTotalFees) external onlyOwner {
        sellTotalFees = _sellTotalFees;
        require(sellTotalFees <= 3, "Must keep fees at 3% or less");
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function setAutomatedMarketMakerPair(
        address pair,
        bool value
    ) public onlyOwner {
        require(
            pair != uniswapV2Pair,
            "The pair cannot be removed from automatedMarketMakerPairs"
        );

        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function updateMarketingFeesAddress(
        address newmarketingFees
    ) external onlyOwner {
        marketingFees = newmarketingFees;
    }

    function updateArbFeesAddress(address newArbFees) external onlyOwner {
        arbFees = newArbFees;
    }

    function updateSmolFeesAddress(address newSmolFees) external onlyOwner {
        smolFees = newSmolFees;
    }

    function isExcludedFromFees(address account) public view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if (limitsInEffect) {
            if (
                from != owner() &&
                to != owner() &&
                to != address(0) &&
                to != address(0xdead) &&
                !swapping
            ) {
                if (!tradingActive) {
                    require(
                        _isExcludedFromFees[from] || _isExcludedFromFees[to],
                        "Trading is not active."
                    );
                }
            }
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= 0;

        if (
            canSwap &&
            swapEnabled &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            !_isExcludedFromFees[from] &&
            !_isExcludedFromFees[to]
        ) {
            swapping = true;

            swapBack();

            swapping = false;
        }

        bool takeFee = !swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        uint256 fees = 0;
        // only take fees on buys/sells, do not take on wallet transfers
        if (takeFee) {
            // on sell
            if (automatedMarketMakerPairs[to] && sellTotalFees > 0) {
                fees = amount.mul(sellTotalFees).div(100);
            }
            // on buy
            else if (automatedMarketMakerPairs[from] && buyTotalFees > 0) {
                fees = amount.mul(buyTotalFees).div(100);
            }

            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }

            amount -= fees;
        }

        super._transfer(from, to, amount);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function swapBack() private {
        uint256 contractBalance = balanceOf(address(this));
        bool success;

        if (contractBalance < 1e9) {
            return;
        }

        swapTokensForEth(contractBalance);

        uint256 ethPortion = address(this).balance / 3;
        (success, ) = address(marketingFees).call{value: ethPortion}("");
        (success, ) = address(arbFees).call{value: ethPortion}("");
        (success, ) = address(smolFees).call{value: address(this).balance}("");
    }
}

