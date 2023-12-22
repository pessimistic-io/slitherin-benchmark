// SPDX-License-Identifier: MIT
/*
 *  ARBridge - $AP
 *
 *  Real-time bridge solutions between Arbitrum and Ethereum network that
 *  seamlessly connects these two ecosystems, facilitating efficient token transfers
 *
 *  @Docs: https://docs.arbridge.net/
 *  @Telegram: https://t.me/arbridg3lobby
 *  @Website: https://arbridge.net/
 *  @Twitter: https://twitter.com/ARBridg3
 */
pragma solidity 0.8.17;

import "./Address.sol";
import "./ERC20.sol";
import "./AccessControl.sol";
import "./Pausable.sol";

import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";

import "./IBridgeToken.sol";


contract ARBridge is ERC20, AccessControl, IBridgeToken {
    using Address for address payable;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

    uint256 private constant DENOMINATOR = 1000;

    uint256 private constant DEFAULT_MAX_TRANSACTION = 20; // Default: 2[%]
    uint256 private constant DEFAULT_MAX_WALLET = 30; // Default: 3[%]
    uint256 private constant DEFAULT_SWAP_TOKENS_AT = 25; // Default: 0.025[%]

    uint256 private constant DEFAULT_BUY_MARKETING_FEE = 100; // Default: 10[%]
    uint256 private constant DEFAULT_BUY_LIQUIDITY_FEE = 50; // Default: 5[%]

    uint256 private constant DEFAULT_SELL_MARKETING_FEE = 200; // Default: 20[%]
    uint256 private constant DEFAULT_SELL_LIQUIDITY_FEE = 100; // Default: 10[%]

    IUniswapV2Router02 immutable public router;
    address public marketingWallet;
    address public liquidityWallet;

    bool private swapping;    
    bool private swapEnabled = true;
    bool private limitsEnabled = true;
    bool private tradeEnabled;

    uint256 public buyTotalFee;
    uint256 public buyMarketingFee;
    uint256 public buyLiquidityFee;

    uint256 public sellTotalFee;
    uint256 public sellMarketingFee;
    uint256 public sellLiquidityFee;

    uint256 public tokensForMarketing;
    uint256 public tokensForLiquidity;

    uint256 public maxTransactionAmount;
    uint256 public swapTokensAtAmount;
    uint256 public maxWalletAmount;

    mapping(address => bool) public isExcludedFromFees;
    mapping(address => bool) public isExcludedMaxTransactionAmount;

    mapping(address => bool) pairs;


    event MaxTxUpdated(uint256 newMax);
    event MaxWalletUpdated(uint256 newMax);
    event BuyFeesUpdated(
        uint256 marketingFee,
        uint256 liquidityFee
    );
    event SellFeesUpdated(
        uint256 marketingFee,
        uint256 liquidityFee
    );
    event WalletUpdated(address newWallet);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiquidity
    );

    constructor(address _router) ERC20("TESTDONTBUY", "TESTDONTBUY") {
        address _defaultAdmin = _msgSender();
        // ACL configs
        _grantRole(ADMIN_ROLE, _defaultAdmin);
        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);

        // Default configuration
        marketingWallet = payable(_defaultAdmin);
        liquidityWallet = _defaultAdmin;

        uint256 totalSupply = 1_000_000 * 1e18;

        maxTransactionAmount = (totalSupply * DEFAULT_MAX_TRANSACTION) / DENOMINATOR;
        maxWalletAmount = (totalSupply * DEFAULT_MAX_WALLET) / DENOMINATOR;
        swapTokensAtAmount = (totalSupply * DEFAULT_SWAP_TOKENS_AT) / 10000; // 0.05% swap wallet

        // Buy side
        buyMarketingFee = DEFAULT_BUY_MARKETING_FEE;
        buyLiquidityFee = DEFAULT_BUY_LIQUIDITY_FEE;
        buyTotalFee = DEFAULT_BUY_MARKETING_FEE + DEFAULT_BUY_LIQUIDITY_FEE;

        // Sell side
        sellMarketingFee = DEFAULT_SELL_MARKETING_FEE;
        sellLiquidityFee = DEFAULT_SELL_LIQUIDITY_FEE;
        sellTotalFee = DEFAULT_SELL_MARKETING_FEE + DEFAULT_SELL_LIQUIDITY_FEE;

        excludeFromFees(address(this), true);
        excludeFromFees(address(0xdead), true);
        excludeFromFees(_defaultAdmin, true);

        excludeFromMaxTransaction(address(this), true);
        excludeFromMaxTransaction(address(0xdead), true);
        excludeFromMaxTransaction(_defaultAdmin, true);

        router = IUniswapV2Router02(_router);

        _mint(_defaultAdmin, totalSupply);
    }

    modifier whenNotSwap() {
        //if(!swapping) {
            swapping = true;
            _;
            swapping = false;
        //}
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

        if (limitsEnabled) {
            if (
                !isExcludedFromFees[tx.origin] &&
                !isExcludedFromFees[from] &&
                !isExcludedFromFees[to] &&
                to != address(0) &&
                to != address(0xdead) &&
                !swapping
            ) {
                if (!tradeEnabled) {
                    require(
                        isExcludedFromFees[from] || isExcludedFromFees[to],
                        "Trading is not active."
                    );
                }
                //when buy
                if (
                    pairs[from] &&
                    !isExcludedMaxTransactionAmount[to]
                ) {
                    require(
                        amount <= maxTransactionAmount,
                        "Buy transfer amount exceeds the maxTransactionAmount."
                    );
                    require(
                        amount + balanceOf(to) <= maxWalletAmount,
                        "Max wallet exceeded"
                    );
                }
                //when sell
                else if (
                    pairs[to] &&
                    !isExcludedMaxTransactionAmount[from]
                ) {
                    require(
                        amount <= maxTransactionAmount,
                        "Sell transfer amount exceeds the maxTransactionAmount."
                    );
                } else if (!isExcludedMaxTransactionAmount[to]) {
                    require(
                        amount + balanceOf(to) <= maxWalletAmount,
                        "Max wallet exceeded"
                    );
                }
            }
        }

        uint256 contractTokenBalance = balanceOf(address(this));
        bool canSwap = contractTokenBalance >= swapTokensAtAmount;
        if (
            swapEnabled &&
            !swapping &&
            !pairs[from] &&
            !isExcludedFromFees[from] &&
            !isExcludedFromFees[to]
        ) { 
            _swap();
        }
        bool takeFee = !swapping;
        // if any account belongs to isExcludedFromFees account then remove the fee
        if (isExcludedFromFees[from] || isExcludedFromFees[to] || isExcludedFromFees[tx.origin]) {
            takeFee = false;
        }
        // only take fees on buys/sells, do not take on wallet transfers
        if (takeFee) {
            uint256 fees = 0;
            // on sell
            if (pairs[to] && sellTotalFee > 0) {
                fees = (amount * sellTotalFee) / DENOMINATOR;
                tokensForLiquidity += (fees * sellLiquidityFee) / sellTotalFee;
                tokensForMarketing += (fees * sellMarketingFee) / sellTotalFee;
            }
            // on buy
            else if (pairs[from] && buyTotalFee > 0) {
                fees = (amount * buyTotalFee) / DENOMINATOR;
                tokensForLiquidity += (fees * buyLiquidityFee) / buyTotalFee;
                tokensForMarketing += (fees * buyMarketingFee) / buyTotalFee;
            }

            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }

            amount -= fees;
        }
        super._transfer(from, to, amount);
    }

    function _swapExactTokensForETH(uint256 amount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        _approve(address(this), address(router), amount);

        // make the swap
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function _addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(router), tokenAmount);

        // add the liquidity
        router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            liquidityWallet,
            block.timestamp
        );
    }

    function _swap() private whenNotSwap {
        uint256 contractBalance = balanceOf(address(this));
        uint256 totalTokensToSwap = tokensForLiquidity + tokensForMarketing;

        if (contractBalance == 0 || totalTokensToSwap == 0) {
            return;
        }

        if (contractBalance > swapTokensAtAmount * 20) {
            contractBalance = swapTokensAtAmount * 20;
        }

        // Halve the amount of liquidity tokens
        uint256 liquidityTokens = (contractBalance * tokensForLiquidity) / totalTokensToSwap / 2;
        uint256 amountToSwapForETH = contractBalance - liquidityTokens;

        uint256 initialETHBalance = address(this).balance;

        _swapExactTokensForETH(amountToSwapForETH);
        
        uint256 ethBalance = address(this).balance - initialETHBalance;

        uint256 ethForMarketing = (ethBalance * tokensForMarketing) / totalTokensToSwap;
        uint256 ethForLiquidity = ethBalance - ethForMarketing;

        tokensForLiquidity = 0;
        tokensForMarketing = 0;

        if (liquidityTokens > 0 && ethForLiquidity > 0) {
            _addLiquidity(liquidityTokens, ethForLiquidity);
            emit SwapAndLiquify(
                amountToSwapForETH,
                ethForLiquidity,
                liquidityTokens
            );
        }
        payable(marketingWallet).sendValue(address(this).balance);    
    }
    
    function withdraw(address to, uint256 amount) external override onlyRole(BRIDGE_ROLE) returns (bool) {
        _mint(to, amount);
        return true;
    }

    function deposit(address to, uint256 amount) external override onlyRole(BRIDGE_ROLE) returns (bool) {
        _burn(to, amount);
        return true;
    }

    function enableTrading() external onlyRole(ADMIN_ROLE) {
        require(!tradeEnabled, "already enabled");
        tradeEnabled = true;
        swapEnabled = true;
    }

    function removeLimits() external onlyRole(ADMIN_ROLE) {
        limitsEnabled = false;
    }

    function updateSwapTokensAtAmount(uint256 percentage) external onlyRole(ADMIN_ROLE) {
        require(percentage >= 1 && percentage <= 500, "invalid");
        swapTokensAtAmount = (totalSupply() * percentage) / 10000; 
    }

    function updateMaxTxnAmount(uint256 percentage) external onlyRole(ADMIN_ROLE) {
        require(percentage >= 5, "too low");
        maxTransactionAmount = (totalSupply() * percentage) / DENOMINATOR;   

        emit MaxTxUpdated(maxTransactionAmount);
    }

    function updateMaxWalletAmount(uint256 percentage) external onlyRole(ADMIN_ROLE) {
        require(percentage >= 5, "too low");
        maxWalletAmount = (totalSupply() * percentage) / DENOMINATOR;

        emit MaxWalletUpdated(maxWalletAmount);
    }

    function updateBuyFees(uint256 marketingFee, uint256 liquidityFee) external onlyRole(ADMIN_ROLE)  {
        buyMarketingFee = marketingFee;
        buyLiquidityFee = liquidityFee;
        buyTotalFee = marketingFee + liquidityFee;
        require(buyTotalFee <= 250, "too high");

        emit BuyFeesUpdated(marketingFee, liquidityFee);
    }

    function updateSellFees(uint256 marketingFee, uint256 liquidityFee) external onlyRole(ADMIN_ROLE)  {
        sellMarketingFee = marketingFee;
        sellLiquidityFee = liquidityFee;
        sellTotalFee = marketingFee + liquidityFee;
        require(sellTotalFee <= 400, "too high");

        emit SellFeesUpdated(marketingFee, liquidityFee);
    }

    function excludeFromMaxTransaction(address account, bool excluded) public onlyRole(ADMIN_ROLE) {
        isExcludedMaxTransactionAmount[account] = excluded;
    }

    function excludeFromFees(address account, bool excluded) public onlyRole(ADMIN_ROLE) {
        isExcludedFromFees[account] = excluded;
    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyRole(ADMIN_ROLE) {
        pairs[pair] = value;
    }

    function swapBack() external onlyRole(ADMIN_ROLE) {
        _swap();
    }

    function updateMarketingWallet(address wallet) external onlyRole(ADMIN_ROLE) {
        marketingWallet = payable(wallet);

        emit WalletUpdated(wallet);
    }

    function updateLiquidityWallet(address wallet) external onlyRole(ADMIN_ROLE) {
        liquidityWallet = wallet;

        emit WalletUpdated(wallet);
    }

    function updateSwapEnabled(bool enabled) external onlyRole(ADMIN_ROLE) {
        swapEnabled = enabled;
    }

    function updateAdmin(address _admin) external onlyRole(ADMIN_ROLE) {
        _grantRole(ADMIN_ROLE, _admin);
    }

    function updateBridge(address _bridge) external onlyRole(ADMIN_ROLE) {
        _grantRole(BRIDGE_ROLE, _bridge);
    }

    receive() external payable {}
}
