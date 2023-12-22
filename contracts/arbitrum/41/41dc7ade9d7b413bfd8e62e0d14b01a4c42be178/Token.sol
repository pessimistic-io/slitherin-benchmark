
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.1;

import "./ERC20.sol";
import "./Ownable.sol";
import "./Address.sol";
import "./SafeMath.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";

/*

    Twitter: https://twitter.com/PEPEDoge_AI

    Telegram: https://t.me/PEPEDogeAI

    Website: http://pepedogeai.vip

*/

contract Token is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    address public constant deadAddress = address(0xdead);

    address public marketingWallet;
    address public buybackWallet;

    bool private swapping;

    uint256 public swapTokensAtAmount;
    uint256 public maxWallet;

    bool public tradingActive = false;
    bool public swapEnabled = false;

    uint256 public buyTotalFees;
    uint256 public buyMarketingFee;
    uint256 public buyBuyBackFee;

    uint256 public sellTotalFees;
    uint256 public sellMarketingFee;
    uint256 public sellBuyBackFee;

    uint256 public tokensForMarketing;
    uint256 public tokensForBuyBack;

    // exlcude from fees and max transaction amount
    mapping(address => bool) private _isExcludedFromFees;

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping(address => bool) public automatedMarketMakerPairs;

    event ExcludeFromFees(address indexed account, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    constructor(address _router) ERC20("PEPE DOGE AI", "PDA") {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            _router
        );

        uniswapV2Router = _uniswapV2Router;

        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);

        uint256 totalSupply = 2_000_000_000 * 1e18;

        maxWallet = (totalSupply * 20) / 1000; // 1% from total supply maxWallet
        swapTokensAtAmount = (totalSupply * 1) / 10000;

        buyMarketingFee = 4;
        buyBuyBackFee = 3;
        buyTotalFees = buyMarketingFee + buyBuyBackFee;

        sellMarketingFee = 4;
        sellBuyBackFee = 3;
        sellTotalFees = sellMarketingFee + sellBuyBackFee;

        marketingWallet = address(0x57f797fa2054fF25A83bb159701800DaC3E7d612);
        buybackWallet = address(0x74444d9fA3AB3b907c318a9DBCb7f1263f1382D4);

        // exclude from paying fees or having max transaction amount
        excludeFromFees(owner(), true);
        excludeFromFees(address(this), true);
        excludeFromFees(address(0xdead), true);

        /*
            _mint is an internal function in ERC20.sol that is only called here,
            and CANNOT be called ever again
        */
        _mint(msg.sender, totalSupply);
    }

    receive() external payable {}

    function updateMarketingWallet(address mw) external onlyOwner {
        marketingWallet = mw;
    }

    function updateBuyBackWallet(address bb) external onlyOwner {
        buybackWallet = bb;
    }

    // once enabled, can never be turned off
    function enableTrading() external onlyOwner {
        tradingActive = true;
        swapEnabled = true;
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function setAutomatedMarketMakerPair(address pair, bool value)
        public
        onlyOwner
    {
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

    // change the minimum amount of tokens to sell from fees
    function updateSwapTokensAtAmount(uint256 newAmount)
        external
        onlyOwner
        returns (bool)
    {
        require(
            newAmount >= (totalSupply() * 1) / 100000 / 1e18,
            "Swap amount cannot be lower than 0.001% total supply."
        );
        require(
            newAmount <= (totalSupply() * 5) / 1000 / 1e18,
            "Swap amount cannot be higher than 0.5% total supply."
        );
        swapTokensAtAmount = newAmount * (10**18);
        return true;
    }

    function updateMaxWalletAmount(uint256 newNum) external onlyOwner {
        require(
            newNum >= ((totalSupply() * 1) / 1000) / 1e18,
            "Cannot set maxWallet lower than 0.1%"
        );
        maxWallet = newNum * (10**18);
    }

    function updateBuyFees(
        uint256 _marketingFee,
        uint256 _buybackFee
    ) external onlyOwner {
        buyMarketingFee = _marketingFee;
        buyBuyBackFee = _buybackFee;
        buyTotalFees = buyMarketingFee + buyBuyBackFee;
        require(buyTotalFees <= 40, "Must keep fees at 40% or less");
    }

    function updateSellFees(
        uint256 _marketingFee,
        uint256 _buybackFee
    ) external onlyOwner {
        sellMarketingFee = _marketingFee;
        sellBuyBackFee = _buybackFee;
        sellTotalFees = sellMarketingFee + sellBuyBackFee;
        require(sellTotalFees <= 40, "Must keep fees at 40% or less");
    }

    function clearStuckEthBalance() external onlyOwner {
        uint256 amountETH = address(this).balance;
        (bool success, ) = payable(_msgSender()).call{value: amountETH}(new bytes(0));
        require(success, 'ETH_TRANSFER_FAILED');
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function swapBack() private {
        uint256 contractBalance = balanceOf(address(this));
        uint256 totalTokensToSwap = tokensForBuyBack + tokensForMarketing;
        bool success;

        if (contractBalance == 0 || totalTokensToSwap == 0) {
            return;
        }

        if (contractBalance > swapTokensAtAmount * 20) {
            contractBalance = swapTokensAtAmount * 20;
        }

        
        uint256 amountToSwapForETH = contractBalance;

        uint256 initialETHBalance = address(this).balance;

        swapTokensForEth(amountToSwapForETH);

        uint256 ethBalance = address(this).balance.sub(initialETHBalance);

        uint256 ethForBuyBack = ethBalance.mul(tokensForBuyBack).div(
            totalTokensToSwap
        );

        tokensForBuyBack = 0;
        tokensForMarketing = 0;

        (success, ) = address(marketingWallet).call{
            value: ethForBuyBack
        }("");
        (success, ) = address(buybackWallet).call{
            value: address(this).balance
        }("");
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

        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

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
                tokensForBuyBack += (fees * sellBuyBackFee) / sellTotalFees;
                tokensForMarketing += (fees * sellMarketingFee) / sellTotalFees;
            }
            // on buy
            else if (automatedMarketMakerPairs[from] && buyTotalFees > 0) {
                fees = amount.mul(buyTotalFees).div(100);
                tokensForBuyBack += (fees * buyBuyBackFee) / buyTotalFees;
                tokensForMarketing += (fees * buyMarketingFee) / buyTotalFees;
            }

            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }

            amount -= fees;
        }

        super._transfer(from, to, amount);
    }
}
