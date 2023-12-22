// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./Ownable.sol";

import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";

contract ELMT is ERC20, Ownable {
    IUniswapV2Router02 public immutable uniswapV2Router;

    address public immutable uniswapV2Pair;
    address public constant deadAddress = address(0xdead);

    uint256 public maxTransactionAmount;
    uint256 public swapTokensAtAmount;
    uint256 public maxWallet;

    uint256 public supply;

    address public feesWallet;

    bool public limitsInEffect = true;
    bool public tradingActive = false;
    bool public swapEnabled = true;

    // Initial distribution for the rp, tres, team and lp
    uint256 public constant INITIAL_ELMT_REWARDS_POOL = 300000 ether;
    uint256 public constant INITIAL_ELMT_TREASURY = 8000 ether;
    uint256 public constant INITIAL_ELMT_TEAM = 32000 ether;
    uint256 public constant INITIAL_ELMT_LP = 60000 ether;

    // Have the tokens been distributed
    bool public tokensDistributed = false;

    // blacklist
    mapping(address => bool) public _isBlacklisted;

    bool private swapping;

    uint256 public maxWalletPercent = 1;
    uint256 public maxTxPercent = 1;

    // fees
    uint256 public buyFees = 8;
    uint256 public sellFees = 8;

    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) public _isExcludedMaxTransactionAmount;

    mapping(address => bool) public automatedMarketMakerPairs;

    constructor(address _feesWallet) ERC20("Elements Finance", "ELMT") {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

        excludeFromMaxTransaction(address(_uniswapV2Router), true);
        uniswapV2Router = _uniswapV2Router;

        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());
        excludeFromMaxTransaction(address(uniswapV2Pair), true);
        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);

        uint256 totalSupply = 400_000 * 1e18;
        supply = totalSupply;

        maxTransactionAmount = (supply * maxTxPercent) / 100;
        swapTokensAtAmount = (supply * 5) / 10000;
        maxWallet = (supply * maxWalletPercent) / 100;

        feesWallet = _feesWallet;

        excludeFromFees(owner(), true);
        excludeFromFees(address(this), true);
        excludeFromFees(address(0xdead), true);

        excludeFromMaxTransaction(owner(), true);
        excludeFromMaxTransaction(address(this), true);
        excludeFromMaxTransaction(address(0xdead), true);

        _approve(owner(), address(uniswapV2Router), totalSupply);
    }

    receive() external payable {}

    function enableTrading() external onlyOwner {
        tradingActive = true;
    }

    function distributeTokens(address _rewardsPool, address _treasury, address _team, address _lp) external onlyOwner {
        require(!tokensDistributed, "only can distribute once");
        require(_rewardsPool != address(0), "!_rewardsPool");
        require(_treasury != address(0), "!_treasury");
        require(_team != address(0), "!_team");
        require(_lp != address(0), "!_lp");
        tokensDistributed = true;
        _mint(_rewardsPool, INITIAL_ELMT_REWARDS_POOL);
        _mint(_treasury, INITIAL_ELMT_TREASURY);
        _mint(_team, INITIAL_ELMT_TEAM);
        _mint(_lp, INITIAL_ELMT_LP);
    }

    function blacklistMalicious(address account, bool value) external onlyOwner {
        _isBlacklisted[account] = value;
    }

    function updatemaxTxPercent(uint256 value) external onlyOwner {
        maxTxPercent = value;
        updateLimits();
    }

    function setSwapEnabled(bool state) public onlyOwner {
        swapEnabled = state;
    }

    function setLimitsInEffect(bool state) public onlyOwner {
        limitsInEffect = state;
    }

    function setFees(uint buy, uint sell) public onlyOwner {
        require(buy <= 10, "Elmt: Too much buy fees");
        require(sell <= 10, "Elmt: Too much sell fees");

        buyFees = buy;
        sellFees = sell;
    }

    function updatemaxWalletPercent(uint256 value) external onlyOwner {
        maxWalletPercent = value;
        updateLimits();
    }

    function excludeFromMaxTransaction(address account, bool state) public onlyOwner {
        _isExcludedMaxTransactionAmount[account] = state;
    }

    function excludeFromFees(address account, bool state) public onlyOwner {
        _isExcludedFromFees[account] = state;
    }

    function updateFeesWallet(address wallet) external onlyOwner {
        feesWallet = wallet;
    }

    function updateLimits() private {
        maxTransactionAmount = (supply * maxTxPercent) / 100;
        swapTokensAtAmount = (supply * 5) / 10000; // 0.05% swap wallet;
        maxWallet = (supply * maxWalletPercent) / 100;
    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        require(pair != uniswapV2Pair, "The pair cannot be removed from automatedMarketMakerPairs");
        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;
    }

    function isExcludedFromFees(address account) public view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!_isBlacklisted[from] && !_isBlacklisted[to], "Blacklisted address");

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if (limitsInEffect) {
            if (from != owner() && to != owner() && to != address(0) && to != address(0xdead) && !swapping) {
                if (!tradingActive) {
                    require(_isExcludedFromFees[from] || _isExcludedFromFees[to], "Trading is not active.");
                }

                //when buy
                if (automatedMarketMakerPairs[from] && !_isExcludedMaxTransactionAmount[to]) {
                    require(amount <= maxTransactionAmount, "Buy transfer amount exceeds the maxTransactionAmount.");
                    require(amount + balanceOf(to) <= maxWallet, "Max wallet exceeded");
                }
                //when sell
                else if (automatedMarketMakerPairs[to] && !_isExcludedMaxTransactionAmount[from]) {
                    require(amount <= maxTransactionAmount, "Sell transfer amount exceeds the maxTransactionAmount.");
                } else if (!_isExcludedMaxTransactionAmount[to]) {
                    require(amount + balanceOf(to) <= maxWallet, "Max wallet exceeded");
                }
            }
        }

        bool canSwap = balanceOf(address(this)) >= swapTokensAtAmount;

        if (canSwap && !swapping && swapEnabled && !automatedMarketMakerPairs[from] && !_isExcludedFromFees[from] && !_isExcludedFromFees[to]) {
            swapping = true;

            swapBack();

            swapping = false;
        }

        bool isSelling = automatedMarketMakerPairs[to];
        bool isBuying = automatedMarketMakerPairs[from];

        uint256 fees = 0;
        uint256 tokensForBurn = 0;

        bool takeFee = !swapping;

        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        if (takeFee) {
            if (isSelling && sellFees > 0) {
                fees = (amount * sellFees) / 100;
            } else if (isBuying && buyFees > 0) {
                fees = (amount * buyFees) / 100;
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
        if (contractBalance == 0) {
            return;
        }

        if (contractBalance > swapTokensAtAmount * 20) {
            contractBalance = swapTokensAtAmount * 20;
        }

        swapTokensForEth(contractBalance);

        (success, ) = address(feesWallet).call{value: address(this).balance}("");
    }
}

