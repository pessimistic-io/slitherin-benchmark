// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {SafeMath} from "./SafeMath.sol";
import {Ownable} from "./Ownable.sol";
import {IERC20} from "./IERC20.sol";

import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";

abstract contract IERC20Extented is IERC20 {
    function decimals() external view virtual returns (uint8);

    function name() external view virtual returns (string memory);

    function symbol() external view virtual returns (string memory);
}

contract CATOSHI is IERC20, IERC20Extented, Ownable {
    using SafeMath for uint256;
    string private constant _name = "CATOSHI";
    string private constant _symbol = "CATS";
    uint8 private constant _decimals = 18;
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _isExcludedFromFee;
    uint256 private constant _tTotal = 11000000 * 10 ** 18; // 6 million
    uint256 public _priceImpact = 2;
    uint256 private _firstBlock;
    uint256 private _botBlocks;
    uint256 public _maxWalletAmount;
    uint256 private _maxSellAmountETH = 50000000000000000000; // 50 ETH
    uint256 private _minBuyETH = 0; //10000000000000000; // 0.01 ETH
    uint256 private _minSellETH = 0; //10000000000000000; // 0.01 ETH

    // fees
    uint256 public _liquidityFee = 1; // divided by 100
    uint256 private _previousLiquidityFee = _liquidityFee;
    uint256 public _marketingFee; // divided by 100
    uint256 private _previousMarketingFee = _marketingFee;
    uint256 public _teamFee; // divided by 100
    uint256 private _previousTeamFee = _teamFee;

    uint256 private _marketingPercent = 50;
    uint256 private _teamPercent = 50;

    struct FeeBreakdown {
        uint256 tLiquidity;
        uint256 tMarketing;
        uint256 tTeam;
        uint256 tAmount;
    }

    mapping(address => bool) private bots;
    address payable private _marketingAddress = payable(0);
    address payable private _teamAddress = payable(0);
    address private presaleRouter;
    address private presaleAddress;
    IUniswapV2Router02 private sushiRouter;
    address public sushiPair;
    uint256 private _maxTxAmount;

    bool private tradingOpen = false;
    bool private inSwap = false;
    bool private presale = true;
    bool private pairSwapped = false;
    bool public _priceImpactSellLimitEnabled = false;
    bool public _ETHsellLimitEnabled = false;
    uint256 public _minTokenBeforeSwap = 1000 * 10 ** 18;

    address public bridge;

    event EndedPresale(bool presale);
    event MaxTxAmountUpdated(uint256 _maxTxAmount);
    event PercentsUpdated(uint256 _marketingPercent, uint256 _teamPercent);
    event FeesUpdated(
        uint256 _marketingFee,
        uint256 _liquidityFee,
        uint256 _teamFee
    );
    event PriceImpactUpdated(uint256 _priceImpact);
    event ExcludedFromFees(address account);
    event IncludedInFees(address account);
    event MaxWalletAmountUpdated(uint256 amount);
    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);

    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor(address _bridge) {
        //Mainnet
        IUniswapV2Router02 _sushiRouter = IUniswapV2Router02(
            0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506
        );

        // Testnet
        // IUniswapV2Router02 _sushiRouter = IUniswapV2Router02(
        //     0xD99D1c33F9fC3444f8101754aBC46c52416550D1
        // );
        sushiRouter = _sushiRouter;
        _approve(address(this), address(sushiRouter), _tTotal);
        sushiPair = IUniswapV2Factory(_sushiRouter.factory()).createPair(
            address(this),
            _sushiRouter.WETH()
        );
        IERC20(sushiPair).approve(address(sushiRouter), type(uint256).max);

        _maxTxAmount = _tTotal; // start off transaction limit at 100% of total supply
        _maxWalletAmount = _tTotal.div(1); // 100%
        _priceImpact = 100;

        bridge = _bridge;
        _balances[_bridge] = _tTotal;

        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[_bridge] = true;
        _isExcludedFromFee[address(this)] = true;
        emit Transfer(address(0), _bridge, _tTotal);
    }

    function name() external pure override returns (string memory) {
        return _name;
    }

    function symbol() external pure override returns (string memory) {
        return _symbol;
    }

    function decimals() external pure override returns (uint8) {
        return _decimals;
    }

    function totalSupply() external pure override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function isBot(address account) public view returns (bool) {
        return bots[account];
    }

    function setBridge(address _bridge) external onlyOwner {
        bridge = _bridge;
    }

    function transfer(
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) external override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function removeAllFee() private {
        if (_marketingFee == 0 && _liquidityFee == 0 && _teamFee == 0) return;
        _previousMarketingFee = _marketingFee;
        _previousLiquidityFee = _liquidityFee;
        _previousTeamFee = _teamFee;

        _marketingFee = 0;
        _liquidityFee = 0;
        _teamFee = 0;
    }

    function setBotFee() private {
        _previousMarketingFee = _marketingFee;
        _previousLiquidityFee = _liquidityFee;
        _previousTeamFee = _teamFee;

        _marketingFee = 3;
        _liquidityFee = 0;
        _teamFee = 0;
    }

    function restoreAllFee() private {
        _marketingFee = _previousMarketingFee;
        _liquidityFee = _previousLiquidityFee;
        _teamFee = _previousTeamFee;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    // calculate price based on pair reserves
    function getTokenPriceETH(uint256 amount) external view returns (uint256) {
        IERC20Extented token0 = IERC20Extented(
            IUniswapV2Pair(sushiPair).token0()
        ); //CATS
        IERC20Extented token1 = IERC20Extented(
            IUniswapV2Pair(sushiPair).token1()
        ); //ETH

        require(token0.decimals() != 0, "ERR: decimals cannot be zero");

        (uint112 Res0, uint112 Res1, ) = IUniswapV2Pair(sushiPair)
            .getReserves();
        if (pairSwapped) {
            token0 = IERC20Extented(IUniswapV2Pair(sushiPair).token1()); //CATS
            token1 = IERC20Extented(IUniswapV2Pair(sushiPair).token0()); //ETH
            (Res1, Res0, ) = IUniswapV2Pair(sushiPair).getReserves();
        }

        uint res1 = Res1 * (10 ** token0.decimals());
        return ((amount * res1) / (Res0 * (10 ** token0.decimals()))); // return amount of token1 needed to buy token0
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        bool takeFee = true;

        if (
            from != owner() &&
            to != owner() &&
            !presale &&
            from != address(this) &&
            to != address(this) &&
            from != bridge &&
            to != bridge
        ) {
            require(tradingOpen);
            if (from != presaleRouter && from != presaleAddress) {
                require(amount <= _maxTxAmount);
            }
            if (from == sushiPair && to != address(sushiRouter)) {
                //buys

                if (
                    block.timestamp <= _firstBlock.add(_botBlocks) &&
                    from != presaleRouter &&
                    from != presaleAddress
                ) {
                    bots[to] = true;
                }

                uint256 ethAmount = this.getTokenPriceETH(amount);

                require(
                    ethAmount >= _minBuyETH,
                    "you must buy at least min ETH worth of token"
                );
                require(
                    balanceOf(to).add(amount) <= _maxWalletAmount,
                    "wallet balance after transfer must be less than max wallet amount"
                );
            }

            if (!inSwap && from != sushiPair) {
                //sells, transfers
                require(!bots[from] && !bots[to]);

                uint256 ethAmount = this.getTokenPriceETH(amount);

                require(
                    ethAmount >= _minSellETH,
                    "you must sell at least the min ETH worth of token"
                );

                if (_ETHsellLimitEnabled) {
                    require(
                        ethAmount <= _maxSellAmountETH,
                        "you cannot sell more than the max ETH amount per transaction"
                    );
                } else if (_priceImpactSellLimitEnabled) {
                    require(
                        amount <=
                            balanceOf(sushiPair).mul(_priceImpact).div(100)
                    ); // price impact limit
                }

                if (to != sushiPair) {
                    require(
                        balanceOf(to).add(amount) <= _maxWalletAmount,
                        "wallet balance after transfer must be less than max wallet amount"
                    );
                }

                uint256 contractTokenBalance = balanceOf(address(this));

                if (contractTokenBalance > _minTokenBeforeSwap) {
                    swapAndLiquify(contractTokenBalance);
                }
                uint256 contractETHBalance = address(this).balance;
                if (contractETHBalance > 0) {
                    sendETHToFee(address(this).balance);
                }
            }
        }

        if (_isExcludedFromFee[from] || _isExcludedFromFee[to] || presale) {
            takeFee = false;
        } else if (bots[from] || bots[to]) {
            setBotFee();
            takeFee = true;
        }

        if (presale) {
            require(
                from == owner() ||
                    from == presaleRouter ||
                    from == presaleAddress ||
                    from == bridge
            );
        }

        _tokenTransfer(from, to, amount, takeFee);
        restoreAllFee();
    }

    function swapTokensForETH(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = sushiRouter.WETH();
        _approve(address(this), address(sushiRouter), tokenAmount);
        sushiRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        _approve(address(this), address(sushiRouter), tokenAmount);

        // add the liquidity
        sushiRouter.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
    }

    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        uint256 autoLPamount = _liquidityFee.mul(contractTokenBalance).div(
            _marketingFee.add(_teamFee).add(_liquidityFee)
        );

        // split the contract balance into halves
        uint256 half = autoLPamount.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForETH(otherHalf); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = (
            (address(this).balance.sub(initialBalance)).mul(half)
        ).div(otherHalf);

        // add liquidity to pancakeswap
        addLiquidity(half, newBalance);
    }

    function sendETHToFee(uint256 amount) private {
        _marketingAddress.transfer(amount.mul(_marketingPercent).div(100));
        _teamAddress.transfer(amount.mul(_teamPercent).div(100));
    }

    function openTrading(uint256 botBlocks) private {
        _firstBlock = block.timestamp;
        _botBlocks = botBlocks;
        tradingOpen = true;
    }

    function manualswap() external {
        require(_msgSender() == _marketingAddress);
        uint256 contractBalance = balanceOf(address(this));
        if (contractBalance > 0) {
            swapTokensForETH(contractBalance);
        }
    }

    function manualsend() external {
        require(_msgSender() == _marketingAddress);
        uint256 contractETHBalance = address(this).balance;
        if (contractETHBalance > 0) {
            sendETHToFee(contractETHBalance);
        }
    }

    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        bool takeFee
    ) private {
        if (!takeFee) {
            removeAllFee();
        }
        _transferStandard(sender, recipient, amount);
        restoreAllFee();
    }

    function _transferStandard(
        address sender,
        address recipient,
        uint256 amount
    ) private {
        FeeBreakdown memory fees;
        fees.tMarketing = amount.mul(_marketingFee).div(100);
        fees.tLiquidity = amount.mul(_liquidityFee).div(100);
        fees.tTeam = amount.mul(_teamFee).div(100);

        fees.tAmount = amount.sub(fees.tMarketing).sub(fees.tLiquidity).sub(
            fees.tTeam
        );

        _balances[sender] = _balances[sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(fees.tAmount);
        _balances[address(this)] = _balances[address(this)].add(
            fees.tMarketing.add(fees.tLiquidity).add(fees.tTeam)
        );

        emit Transfer(sender, recipient, fees.tAmount);
    }

    receive() external payable {}

    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
        emit ExcludedFromFees(account);
    }

    function includeInFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = false;
        emit IncludedInFees(account);
    }

    function removeBot(address account) external onlyOwner {
        bots[account] = false;
    }

    function addBot(address account) external onlyOwner {
        bots[account] = true;
    }

    function setMaxTxAmount(uint256 maxTxAmount) external onlyOwner {
        require(
            maxTxAmount > _tTotal.div(10000),
            "Amount must be greater than 0.01% of supply"
        );
        require(
            maxTxAmount <= _tTotal,
            "Amount must be less than or equal to totalSupply"
        );
        _maxTxAmount = maxTxAmount;
        emit MaxTxAmountUpdated(_maxTxAmount);
    }

    function setMaxWalletAmount(uint256 maxWalletAmount) external onlyOwner {
        require(
            maxWalletAmount > _tTotal.div(200),
            "Amount must be greater than 0.5% of supply"
        );
        require(
            maxWalletAmount <= _tTotal,
            "Amount must be less than or equal to totalSupply"
        );
        _maxWalletAmount = maxWalletAmount;
        emit MaxWalletAmountUpdated(_maxWalletAmount);
    }

    function setTaxes(
        uint256 marketingFee,
        uint256 liquidityFee,
        uint256 teamFee
    ) external onlyOwner {
        uint256 totalFee = marketingFee.add(liquidityFee).add(teamFee);
        require(totalFee < 15, "Sum of fees must be less than 15%");

        _marketingFee = marketingFee;
        _liquidityFee = liquidityFee;
        _teamFee = teamFee;

        _previousMarketingFee = _marketingFee;
        _previousLiquidityFee = _liquidityFee;
        _previousTeamFee = _teamFee;

        uint256 totalETHfees = _marketingFee.add(_teamFee);

        _marketingPercent = (_marketingFee.mul(100)).div(totalETHfees);
        _teamPercent = (_teamFee.mul(100)).div(totalETHfees);

        emit FeesUpdated(_marketingFee, _liquidityFee, _teamFee);
        emit PercentsUpdated(_marketingPercent, _teamPercent);
    }

    function updateMinTokenBeforeSwap(
        uint256 minTokenBeforeSwap
    ) external onlyOwner {
        _minTokenBeforeSwap = minTokenBeforeSwap;
        emit MinTokensBeforeSwapUpdated(_minTokenBeforeSwap);
    }

    function setPriceImpact(uint256 priceImpact) external onlyOwner {
        require(
            priceImpact <= 100,
            "max price impact must be less than or equal to 100"
        );
        require(
            priceImpact > 0,
            "cant prevent sells, choose value greater than 0"
        );
        _priceImpact = priceImpact;
        emit PriceImpactUpdated(_priceImpact);
    }

    function setPresaleRouterAndAddress(
        address router,
        address wallet
    ) external onlyOwner {
        presaleRouter = router;
        presaleAddress = wallet;
        excludeFromFee(presaleRouter);
        excludeFromFee(presaleAddress);
    }

    function endPresale(uint256 botBlocks) external onlyOwner {
        require(presale == true, "presale already ended");
        presale = false;
        openTrading(botBlocks);
        emit EndedPresale(presale);
    }

    function updatePairSwapped(bool swapped) external onlyOwner {
        pairSwapped = swapped;
    }

    function updateMinBuySellETH(
        uint256 minBuyETH,
        uint256 minSellETH
    ) external onlyOwner {
        require(
            minBuyETH <= 100000000000000000,
            "cant make the limit higher than 0.1 ETH"
        );
        require(
            minSellETH <= 100000000000000000,
            "cant make the limit higher than 0.1 ETH"
        );
        _minBuyETH = minBuyETH;
        _minSellETH = minSellETH;
    }

    function updateMaxSellAmountETH(uint256 maxSellETH) external onlyOwner {
        require(
            maxSellETH >= 1000000000000000000,
            "cant make the limit lower than 1 ETH"
        );
        _maxSellAmountETH = maxSellETH;
    }

    function updateMarketingAddress(
        address payable marketingAddress
    ) external onlyOwner {
        _marketingAddress = marketingAddress;
    }

    function updateTeamAddress(address payable teamAddress) external onlyOwner {
        _teamAddress = teamAddress;
    }

    function enableETHsellLimit() external onlyOwner {
        require(_ETHsellLimitEnabled == false, "already enabled");
        _ETHsellLimitEnabled = true;
        _priceImpactSellLimitEnabled = false;
    }

    function disableETHsellLimit() external onlyOwner {
        require(_ETHsellLimitEnabled == true, "already disabled");
        _ETHsellLimitEnabled = false;
    }

    function enablePriceImpactSellLimit() external onlyOwner {
        require(_priceImpactSellLimitEnabled == false, "already enabled");
        _priceImpactSellLimitEnabled = true;
        _ETHsellLimitEnabled = false;
    }

    function disablePriceImpactSellLimit() external onlyOwner {
        require(_priceImpactSellLimitEnabled == true, "already disabled");
        _priceImpactSellLimitEnabled = false;
    }
}

