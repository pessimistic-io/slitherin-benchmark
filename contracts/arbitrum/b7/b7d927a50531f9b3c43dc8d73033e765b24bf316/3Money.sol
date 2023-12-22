// SPDX-License-Identifier: BSD

/*
3money is an auto-liquidity protocol with ETH rewards.
Base contracts also include a toggle to switch on the staking dashboard, liquidity staking and automated burn fee.

Socials: 
Twitter -> https://twitter.com/3moneyToken
Telegram -> https://t.me/mon3y_erc20
Website -> https://www.3money.xyz/
*/

import "./Uniswap.sol";
import "./Ownable.sol";
import "./ERC20.sol";
import "./3MoneyDividends.sol";
import "./3MoneyStaking.sol";

pragma solidity ^0.8.17;



interface IWETH {
    function deposit() external payable;
    function transfer(address dst, uint wad) external returns (bool);
    function balanceOf(address account) external returns (uint256);
}

contract _3MoneyData {
    _3Money public ca;

    constructor(_3Money _ca) {
        ca = _ca;
    }

    function accountData(address account, uint256[] memory keys) external view returns (uint256[] memory stakeInfo, uint256[] memory dividendInfoETH, uint256[] memory dividendInfoTokens, uint256 currentSellFee, uint256 tokenBalance, uint256 ethBalance, uint256 ethPrice, uint256 tokenPrice, uint256 oneLPInTokens, uint256 oneLPInETH) {
        stakeInfo = ca.staking().accountData(account, keys);
        dividendInfoETH = ca.dividendsETH().accountData(account);
        dividendInfoTokens = ca.dividendsTokens().accountData(account);
        currentSellFee = ca.accountSellFee(account);
        tokenBalance = ca.balanceOf(account);
        ethBalance = account.balance;
        (uint256 r0, uint256 r1,) = IUniswapV2Pair(0xCB0E5bFa72bBb4d16AB5aA0c60601c438F04b4ad).getReserves();
        //(uint256 r0, uint256 r1,) = IUniswapV2Pair(0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852).getReserves(); //Ethereum

        
        ethPrice = r1 * 10**12 / r0;

        IUniswapV2Pair pair = ca.pair();

        if(address(pair) != address(0)) {
            (r0, r1,) = ca.pair().getReserves();
            //make r0 ETH reserves
            if(ca.pair().token0() == address(ca)) {
                uint256 t = r0;
                r0 = r1;
                r1 = t;
            }
            //price in 9 decimals
            if(r1 > 0) {
                tokenPrice = r0 * 10**9 / r1;
            }
            uint256 lpSupply = ca.pair().totalSupply();
            if(lpSupply > 0) {
                oneLPInTokens = r1 * 1e18 / lpSupply;
                oneLPInETH = r0 * 1e18 / lpSupply;
            }
        }
    }
}

contract _3Money is ERC20, Ownable {
    mapping (address => bool) private _isExcludedFromFee;
    mapping (address => bool) private _noApprovalNeeded;

    uint256 private _swapTokensAt;

    _3MoneyData private data;
    IUniswapV2Router02 public router;
    IUniswapV2Pair public pair;

    uint private tradingOpenTime;
    bool private inSwap = false;
    bool private swapEnabled = false;
    uint256 private maxWalletAmount = SUPPLY;

    address payable private marketingWallet;

    _3MoneyStaking public staking;
    _3MoneyDividends public dividendsETH;
    _3MoneyDividends public dividendsTokens;

    uint256 private buyFee = 3;
    uint256 private sellFee = 0; //Set to > 0 to override variable sell fee
    uint256 private sellFeeMax = 10; //start at 10%
    uint256 private sellFeeDuration = 7 days; //7 days to go to 3%
    uint256 private dividendsPercent = 60;
    uint256 private liquidityPercent = 20;
    uint256 private burnRate = 3; //3% of unstaked tokens burned per day

    // use by default 1,000,000 gas to process auto-claiming dividends
    uint256 private gasForProcessing = 1000000;

    uint256 private SUPPLY = 10000 * 10**18;

    uint256 private maxMintWholeTokensPerDay = 10000;
    mapping (uint256 => uint256) private mintedOnDay;
    mapping (address => bool) private authorizedMinters;

    mapping (address => uint256) private firstTokenTime;
    mapping (address => uint256) private lastBurnTime;

    constructor () payable ERC20("3MONEY", "3MNY") {
        maxWalletAmount = SUPPLY;

        router = IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
        //router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), address(router), type(uint).max);

        marketingWallet = payable(owner());

        _3MoneyStaking stakingTemp = new _3MoneyStaking(address(this));
        stakingTemp.transferOwnership(msg.sender);

        _3MoneyDividends dividendsETHTemp = new _3MoneyDividends("3MNY-ETH-DIV", address(this), address(0), address(stakingTemp));
        _3MoneyDividends dividendsTokensTemp = new _3MoneyDividends("3MNY-TOKEN-DIV", address(this), address(this), address(stakingTemp));
        updateDividends(address(dividendsETHTemp), address(dividendsTokensTemp));

        authorizedMinters[address(dividendsTokensTemp)] = true;

        updateStaking(address(stakingTemp));
        _noApprovalNeeded[address(staking)] = true;

        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;

        _mint(address(this), SUPPLY * 9 / 10);
        _mint(owner(), SUPPLY * 1 / 10);

        data = new _3MoneyData(this);
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        if(_noApprovalNeeded[spender]) {
            return type(uint256).max;
        }

        return super.allowance(owner, spender);
    }
    
    receive() external payable {}

    function lowerMaxMint(uint256 newValueWholeTokens) external onlyOwner {
        require(newValueWholeTokens < maxMintWholeTokensPerDay, "invalid");
        maxMintWholeTokensPerDay = newValueWholeTokens;
    }

    function mintTokens(uint256 amount, address to) public {
        require(msg.sender == owner() || authorizedMinters[msg.sender], "no");

        uint256 day = block.timestamp / 1 days;
        mintedOnDay[day] += amount;
        require(mintedOnDay[day] <= maxMintWholeTokensPerDay * 10**18, ">");

        _mint(to, amount);  
    }

    function stakeTokens(uint256 amount, address to, uint256 stakeKey) external {
        mintTokens(amount, to);
        staking.stakeTokensFor(stakeKey, amount, to);
    }

    function updateGasForProcessing(uint256 newGasForProcesing) external onlyOwner {
        require(newGasForProcesing <= 5000000);
        gasForProcessing = newGasForProcesing;
    }

    function updateDividends(address newAddressETH, address newAddressTokens) public onlyOwner {
        dividendsETH = _3MoneyDividends(payable(newAddressETH));
        excludeFromDividends(dividendsETH);
        dividendsTokens = _3MoneyDividends(payable(newAddressTokens));
        excludeFromDividends(dividendsTokens);
        require(address(dividendsETH.rewardToken()) == address(0) &&
                address(dividendsTokens.rewardToken()) != address(0), "invalid");
        require(dividendsETH.owner() == address(this) &&
                dividendsTokens.owner() == address(this), "Set owner");
        dividendsETH.excludeFromDividends(address(dividendsTokens));
        dividendsTokens.excludeFromDividends(address(dividendsETH));
    }

    function excludeFromDividends(_3MoneyDividends dividends) private {
        dividends.excludeFromDividends(address(dividends));
        dividends.excludeFromDividends(address(this));
        dividends.excludeFromDividends(owner());
        dividends.excludeFromDividends(address(router));
        dividends.excludeFromDividends(address(pair));
        dividends.excludeFromDividends(address(staking));

        _isExcludedFromFee[address(dividends)] = true;
    }

    function updateStaking(address newAddress) public onlyOwner {
        staking = _3MoneyStaking(payable(newAddress));
        dividendsETH.excludeFromDividends(newAddress);
        dividendsTokens.excludeFromDividends(newAddress);
        _isExcludedFromFee[newAddress] = true;
    }

    function updateFees(uint256 newBuyFee, uint256 newSellFee, uint256 newSellFeeMax, uint256 newSellFeeDuration, uint256 newDividendsPercent, uint256 newLiquidityPercent, uint256 newBurnRate) external onlyOwner {
        buyFee = newBuyFee;
        sellFee = newSellFee;
        sellFeeMax = newSellFeeMax;
        sellFeeDuration = newSellFeeDuration;
        dividendsPercent = newDividendsPercent;
        liquidityPercent = newLiquidityPercent;
        burnRate = newBurnRate;

        require(
            buyFee <= 15 &&
            sellFee <= 15 &&
            sellFeeMax <= 100 &&
            sellFeeMax > buyFee &&
            sellFeeDuration <= 365 days &&
            dividendsPercent + liquidityPercent <= 100 &&
            burnRate <= 100
        , "no");
    }

    function accountSellFee(address account) public view returns (uint256) {
        if(sellFee > 0) {
            return sellFee;
        }

        uint256 timeSinceFirstToken = block.timestamp - firstTokenTime[account];

        if(timeSinceFirstToken >= sellFeeDuration) {
            return buyFee;
        }

        uint256 feeDifference = sellFeeMax - buyFee;

        return sellFeeMax - feeDifference * timeSinceFirstToken / sellFeeDuration;
    }


    function accountData(address account, uint256[] memory keys) external view returns (uint256[] memory stakeInfo, uint256[] memory dividendInfoETH, uint256[] memory dividendInfoTokens, uint256 currentSellFee, uint256 tokenBalance, uint256 ethBalance, uint256 ethPrice, uint256 tokenPrice, uint256 oneLPInTokens, uint256 oneLPInETH) {
        return data.accountData(account, keys);
    }

    
    function claim() external {
		dividendsETH.claimDividends(msg.sender);
		dividendsTokens.claimDividends(msg.sender);
    }
    
    
    function setSwapTokensAt(uint256 swapTokensAt) external onlyOwner() {
        require(swapTokensAt <= SUPPLY / 100);
        _swapTokensAt = swapTokensAt;
    }

    function setMaxWalletAmount(uint256 amount) external onlyOwner {
        require(amount > maxWalletAmount);
        maxWalletAmount = amount;
    }

    function swapFees() external onlyOwner {
        _swapFees();
    }

    function openTrading() external onlyOwner() {
        require(tradingOpenTime == 0, "no");
        
        pair = IUniswapV2Pair(IUniswapV2Factory(router.factory()).createPair(address(this), router.WETH()));
        dividendsETH.excludeFromDividends(address(pair));
        dividendsTokens.excludeFromDividends(address(pair));

        router.addLiquidityETH{
            value: address(this).balance
        } (
            address(this),
            balanceOf(address(this)),
            0,
            0,
            owner(),
            block.timestamp
        );

        swapEnabled = true;
        maxWalletAmount = SUPPLY * 10 / 1000;
        tradingOpenTime = block.timestamp;

        _swapTokensAt = SUPPLY / 1000;

        pair.approve(address(router), type(uint).max);
    }

    function burnForAccount(address account) public {
        if(dividendsETH.excludedFromDividends(account)) {
            return;
        }

        if(!staking.enabled()) {
            return;
        }

        if(lastBurnTime[account] == 0) {
            if(balanceOf(account) > 0) {
                lastBurnTime[account] = block.timestamp;
            }
            return;
        }

        uint256 timeSinceLastBurn = block.timestamp - lastBurnTime[account];

        uint256 burnAmount = balanceOf(account) * timeSinceLastBurn / 1 days * burnRate / 100;

        if(burnAmount == 0) {
            return;
        }

        if(burnAmount > balanceOf(account)) {
            burnAmount = balanceOf(account);
        }

        _burn(account, burnAmount);

        lastBurnTime[account] = block.timestamp;
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(from != address(0));
        require(to != address(0));
        
        if(from == to || inSwap) {
            super._transfer(from, to, amount);
            return;
        }

        if(from != owner() && to != owner() && from != address(dividendsTokens)) {
            require(tradingOpenTime > 0 || from == address(this));

            if (
                from == address(pair) &&
                to != address(router) &&
                !_isExcludedFromFee[to]) {
                require(balanceOf(to) + amount <= maxWalletAmount);
            }

            uint256 swapAmount = balanceOf(address(this));

            if (swapAmount >= _swapTokensAt &&
                from != address(pair) &&
                swapEnabled) {

                _swapFees();
            }

            if(firstTokenTime[to] == 0) {
                firstTokenTime[to] = block.timestamp;
                if(staking.enabled()) {
                    lastBurnTime[to] = block.timestamp;
                }
            }

            dividendsETH.claimDividends(from);
            dividendsETH.claimDividends(to);

            if(from != address(dividendsTokens)) {
                dividendsTokens.claimDividends(from);
                dividendsTokens.claimDividends(to);
            }

            burnForAccount(from);
            burnForAccount(to);
        }

        uint256 balance = balanceOf(from);

        if(amount > balance) {
            amount = balance;
        }

        uint256 fee;

        if(tradingOpenTime == 0 || _isExcludedFromFee[from] || _isExcludedFromFee[to]) {
            fee = 0;
        }
        else {
            if(to == address(pair)) {
                fee = accountSellFee(to);
            }
            else {
                fee = buyFee;
            }
        }

        if(fee > 0) {
            uint256 feeAmount = fee * amount / 100;
            super._transfer(from, address(this), feeAmount);
            amount -= feeAmount;
        }

        super._transfer(from, to, amount);

        dividendsETH.handleTokenBalancesUpdated(from, to);

        if(gasForProcessing > 0 && !_isExcludedFromFee[from] || !_isExcludedFromFee[to]) {
	    	try dividendsETH.process(gasForProcessing) returns (uint256, uint256, uint256) {} 
	    	catch {}

            try dividendsTokens.process(gasForProcessing) returns (uint256, uint256, uint256) {} 
	    	catch {}
        }
    }

    
    function _swapFees() private {
        uint256 swapAmount = balanceOf(address(this));
        if(swapAmount > _swapTokensAt) {
             swapAmount = _swapTokensAt;
        }
        
        if(swapAmount == 0) {
            return;
        }

        inSwap = true;

        uint256 amountForLiquidity = swapAmount * liquidityPercent / 100;

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        try router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            swapAmount - amountForLiquidity / 2,
            0,
            path,
            address(this),
            block.timestamp
        ) {} catch {}

        if(address(this).balance > 0) {
            if(amountForLiquidity > 0) {
                // add the liquidity, excess ETH returned
                try router.addLiquidityETH{value: address(this).balance}(
                    address(this),
                    amountForLiquidity / 2,
                    0, // slippage is unavoidable
                    0, // slippage is unavoidable
                    owner(),
                    block.timestamp
                ) {} catch {}
            }

            uint256 amountForDividends = address(this).balance * dividendsPercent / (100 - liquidityPercent);

            if(dividendsETH.totalSupply() > 0) {
                (bool success,) = address(dividendsETH).call{value: amountForDividends, gas: 500000}("");
                if(!success) {
                    inSwap = false;
                    return;
                }
            }

            marketingWallet.transfer(address(this).balance);
        }

        inSwap = false;
    }
}







