// SPDX-License-Identifier: MIT

import "./SafeMath.sol";
import "./Ownable.sol";
import "./ERC20.sol";
import "./ISharesDist.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";

pragma solidity ^0.8.4;

contract AAAA is ERC20, Ownable {
    using SafeMath for uint256;

    address public sushiPair;
    address public sushiRouterAddress = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;


    address public teamPool;
    address public rewardsPool;

    uint256 public rewardsFee;
    uint256 public liquidityPoolFee;
    uint256 public teamPoolFee;
    uint256 public cashoutFee;
    uint256 public totalFees;

    uint256 public swapTokensAmount;
    uint256 public totalClaimed = 0;
    bool public isTradingEnabled = true;
    bool public swapLiquifyEnabled = true;

    uint16 public buyTax = 0;
    uint16 public sellTax = 1000;


    uint16 public maxTransferAmountRate = 500;
    uint16 public maxBalanceAmountRate = 500;

    IUniswapV2Router02 private sushiRouter;
    ISharesDist private sharesDist;
    uint256 private rwSwap;
    bool private swapping = false;

    mapping(address => bool) public isBlacklisted;
    mapping(address => bool) public automatedMarketMakerPairs;
    mapping(address => bool) private _excludedFromAntiWhale;


    event UpdatesushiRouter(
        address indexed newAddress,
        address indexed oldAddress
    );

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event LiquidityWalletUpdated(
        address indexed newLiquidityWallet,
        address indexed oldLiquidityWallet
    );

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    event Cashout(
        address indexed account,
        uint256 amount,
        uint256 indexed blockTime
    );

    event Compound(
        address indexed account,
        uint256 amount,
        uint256 indexed blockTime
    );

    event MaxTransferAmountRateUpdated(address indexed operator, uint256 previousRate, uint256 newRate);
    event maxBalanceAmountRateUpdated(address indexed operator, uint256 previousRate, uint256 newRate);
     
    modifier antiWhale(address sender, address recipient, uint256 amount) {
        if (maxTransferAmount() > 0) {
            if (
                _excludedFromAntiWhale[sender] == false
                && _excludedFromAntiWhale[recipient] == false
            ) {
                require(amount <= maxTransferAmount(), "Transfer amount exceeds the maxTransferAmount");
                if (sender == sushiPair) {
                    require(balanceOf(recipient).add(amount) <= maxBalanceAmount(), "Transfer would exceed the maxBalanceAmount of the recipient");
                }
            }
        }
        _;
    }
    constructor(
        address[3] memory addresses,
        uint8[5] memory fees,
        uint256 swapAmount
    )
        ERC20("AAAAAA", "AAAA")
    {
        _excludedFromAntiWhale[msg.sender] = true;
        _excludedFromAntiWhale[address(0)] = true;
        _excludedFromAntiWhale[address(this)] = true;
        _excludedFromAntiWhale[BURN_ADDRESS] = true;
        _excludedFromAntiWhale[addresses[0]] = true;
        _excludedFromAntiWhale[addresses[1]] = true;

        require(
            addresses[0] != address(0) && addresses[1] != address(0) && addresses[2] != address(0),
            "CONSTR:1"
        );
        teamPool = addresses[0];
        rewardsPool = addresses[1];
        sharesDist = ISharesDist(addresses[2]);

        require(sushiRouterAddress != address(0), "CONSTR:2");
        IUniswapV2Router02 _sushiRouter = IUniswapV2Router02(sushiRouterAddress);

        address _sushiPair = IUniswapV2Factory(_sushiRouter.factory()).createPair(_sushiRouter.WETH(),address(this));

        sushiRouter = _sushiRouter;
        sushiPair = _sushiPair;

        _setAutomatedMarketMakerPair(_sushiPair, true);

        require(
            fees[0] != 0 && fees[1] != 0 && fees[2] != 0 && fees[3] != 0,
            "CONSTR:3"
        );
        teamPoolFee = fees[0];
        rewardsFee = fees[1];
        liquidityPoolFee = fees[2];
        cashoutFee = fees[3];
        rwSwap = fees[4];

        totalFees = rewardsFee.add(liquidityPoolFee).add(teamPoolFee);

        require(swapAmount > 0, "CONSTR:7");
        swapTokensAmount = swapAmount * (10**18);
    }

    function migrate(address[] memory addresses_, uint256[] memory balances_) external onlyOwner {
        for (uint256 i = 0; i < addresses_.length; i++) {
            _mint(addresses_[i], balances_[i]);
        }
    }

    function burn(address account, uint256 amount) external onlyOwner {
        _burn(account, amount);
    }

    function updatesushiRouterAddress(address newAddress) external onlyOwner {
        require(
            newAddress != address(sushiRouter),
            "TKN:1"
        );
        emit UpdatesushiRouter(newAddress, address(sushiRouter));
        IUniswapV2Router02	 _sushiRouter = IUniswapV2Router02(newAddress);
        address _sushiPair = IUniswapV2Factory(sushiRouter.factory()).createPair(
            address(this),
            _sushiRouter.WETH()
        );
        sushiPair = _sushiPair;
        sushiRouterAddress = newAddress;
    }

    function updateSwapTokensAmount(uint256 newVal) external onlyOwner {
        swapTokensAmount = newVal;
    }

    function updateTeamPool(address payable newVal) external onlyOwner {
        teamPool = newVal;
    }

    function updateRewardsPool(address payable newVal) external onlyOwner {
        rewardsPool = newVal;
    }

    function updateRewardsFee(uint256 newVal) external onlyOwner {
        rewardsFee = newVal;
        totalFees = rewardsFee.add(liquidityPoolFee).add(teamPoolFee);
    }

    function updateLiquidityFee(uint256 newVal) external onlyOwner {
        liquidityPoolFee = newVal;
        totalFees = rewardsFee.add(liquidityPoolFee).add(teamPoolFee);
    }

    function updateTeamFee(uint256 newVal) external onlyOwner {
        teamPoolFee = newVal;
        totalFees = rewardsFee.add(liquidityPoolFee).add(teamPoolFee);
    }

    function updateCashoutFee(uint256 newVal) external onlyOwner {
        cashoutFee = newVal;
    }

    function updateRwSwapFee(uint256 newVal) external onlyOwner {
        rwSwap = newVal;
    }

    function updateSwapLiquify(bool newVal) external onlyOwner {
        swapLiquifyEnabled = newVal;
    }

    function updateIsTradingEnabled(bool newVal) external onlyOwner {
        isTradingEnabled = newVal;
    }

    function setAutomatedMarketMakerPair(address pair, bool value)
        external
        onlyOwner
    {
        require(
            pair != sushiPair,
            "TKN:2"
        );

        _setAutomatedMarketMakerPair(pair, value);
    }

    function blacklistAddress(address account, bool value)
        external
        onlyOwner
    {
        isBlacklisted[account] = value;
    }

    function updateBuyTax(uint16 value) external onlyOwner {
        require(value <= 2000);
        buyTax = value;
    }

    function updateSellTax(uint16 value) external onlyOwner {
        require(value <= 2000);
        sellTax = value;
    }

    // Private methods

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(
            automatedMarketMakerPairs[pair] != value,
            "TKN:3"
        );
        automatedMarketMakerPairs[pair] = value;

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override antiWhale(from, to, amount) {
        require(
            !isBlacklisted[from] && !isBlacklisted[to],
            "BLACKLISTED"
        );
        require(from != address(0), "ERC20:1");
        require(to != address(0), "ERC20:2");
        if (from != owner() && to != sushiPair && to != address(sushiRouter) && to != address(this) && from != address(this)) {
            require(isTradingEnabled, "TRADING_DISABLED");
        }
        if (from == sushiPair && buyTax != 0) {
            uint256 taxAmount = amount * buyTax/10000;
            uint256 sendAmount = amount - taxAmount;
            require (amount == taxAmount + sendAmount, "invalid Tax Amount");
            super._transfer(from, address(this), taxAmount);
            super._transfer(from, to, sendAmount);
        } else if (to == sushiPair && sellTax != 0) {
            uint256 taxAmount = amount * sellTax/10000;
            uint256 sendAmount = amount - taxAmount;
            require (amount == taxAmount + sendAmount, "invalid Tax Amount");
            super._transfer(from, address(this), taxAmount);
            super._transfer(from, to, sendAmount);
        } else {
            super._transfer(from, to, amount);
        }
    }

    function swapAndSendToFee(address destination, uint256 tokens) private {
        uint256 initialWETHBalance = address(this).balance;

        swapTokensForWETH(tokens); 
        uint256 newBalance = (address(this).balance).sub(initialWETHBalance);
        payable(destination).transfer(newBalance);
    }

    function swapAndLiquify(uint256 tokens) private {
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);
        uint256 initialBalance = address(this).balance;
        swapTokensForWETH(half);

        uint256 newBalance = address(this).balance.sub(initialBalance);
        addLiquidity(otherHalf, newBalance);
        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForWETH(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = sushiRouter.WETH();

        _approve(address(this), address(sushiRouter), tokenAmount);

        sushiRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of WETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(sushiRouter), tokenAmount);

        // add the liquidity
        sushiRouter.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0),
            block.timestamp
        );
    }

    // External shares methods

    function createsharesWithTokens(uint256 amount_) external {
        address sender = _msgSender();
        require(
            sender != address(0),
            "NC:2"
        );
        require(!isBlacklisted[sender], "BLACKLISTED");
        require(
            sender != teamPool && sender != rewardsPool,
            "NC:4"
        );
        require(
            balanceOf(sender) >= amount_,
            "NC:5"
        );

        uint256 contractTokenBalance = balanceOf(address(this));
        bool swapAmountOk = contractTokenBalance >= swapTokensAmount;
        if (
            swapAmountOk &&
            swapLiquifyEnabled &&
            !swapping &&
            sender != owner() &&
            !automatedMarketMakerPairs[sender]
        ) {
            swapping = true;

            uint256 teamTokens = contractTokenBalance
                .mul(teamPoolFee)
                .div(100);

            swapAndSendToFee(teamPool, teamTokens);

            uint256 rewardsPoolTokens = contractTokenBalance
                .mul(rewardsFee)
                .div(100);

            uint256 rewardsTokenstoSwap = rewardsPoolTokens.mul(rwSwap).div(
                100
            );

            swapAndSendToFee(rewardsPool, rewardsTokenstoSwap);

            super._transfer(
                address(this),
                rewardsPool,
                rewardsPoolTokens.sub(rewardsTokenstoSwap)
            );

            uint256 swapTokens = contractTokenBalance.mul(liquidityPoolFee).div(
                100
            );

            swapAndLiquify(swapTokens);
            swapTokensForWETH(balanceOf(address(this)));

            swapping = false;
        }
        super._transfer(sender, address(this), amount_);
        sharesDist.createShare(sender, amount_);
    }

    function cashoutReward(uint256 blocktime) external {
        address sender = _msgSender();
        require(
            sender != address(0),
            "CASHOUT:1"
        );
        require(
            !isBlacklisted[sender],
            "BLACKLISTED"
        );
        require(
            sender != teamPool && sender != rewardsPool,
            "CASHOUT:3"
        );
        uint256 rewardAmount = sharesDist.getShareReward(sender, blocktime);
        require(
            rewardAmount > 0,
            "CASHOUT:4"
        );

        if (swapLiquifyEnabled) {
            uint256 feeAmount;
            if (cashoutFee > 0) {
                feeAmount = rewardAmount.mul(cashoutFee).div(100);
                swapAndSendToFee(rewardsPool, feeAmount);
            }
            rewardAmount -= feeAmount;
        }
        super._transfer(rewardsPool, sender, rewardAmount);
        sharesDist.cashoutShareReward(sender, blocktime);
        totalClaimed += rewardAmount;

        emit Cashout(sender, rewardAmount, blocktime);
    }

    function cashoutAll() external {
        address sender = _msgSender();
        require(
            sender != address(0),
            "CASHOUT:5"
        );
        require(
            !isBlacklisted[sender],
            "BLACKLISTED"
        );
        require(
            sender != teamPool && sender != rewardsPool,
            "CASHOUT:7"
        );
        uint256 rewardAmount = sharesDist.getAllSharesRewards(sender);
        require(
            rewardAmount > 0,
            "CASHOUT:8"
        );
        if (swapLiquifyEnabled) {
            uint256 feeAmount;
            if (cashoutFee > 0) {
                feeAmount = rewardAmount.mul(cashoutFee).div(100);
                swapAndSendToFee(rewardsPool, feeAmount);
            }
            rewardAmount -= feeAmount;
        }
        super._transfer(rewardsPool, sender, rewardAmount);
        sharesDist.cashoutAllSharesRewards(sender);
        totalClaimed += rewardAmount;

        emit Cashout(sender, rewardAmount, 0);
    }

    function compoundsharesRewards(uint256 blocktime) external {
        address sender = _msgSender();
        require(
            sender != address(0),
            "COMP:1"
        );
        require(
            !isBlacklisted[sender],
            "BLACKLISTED"
        );
        require(
            sender != teamPool && sender != rewardsPool,
            "COMP:2"
        );
        uint256 rewardAmount = sharesDist.getShareReward(sender, blocktime);
        require(
            rewardAmount > 0,
            "COMP:3"
        );

        uint256 contractTokenBalance = balanceOf(address(this));
        bool swapAmountOk = contractTokenBalance >= swapTokensAmount;
        if (
            swapAmountOk &&
            swapLiquifyEnabled &&
            !swapping &&
            sender != owner() &&
            !automatedMarketMakerPairs[sender]
        ) {
            swapping = true;

            uint256 teamTokens = contractTokenBalance
                .mul(teamPoolFee)
                .div(100);

            swapAndSendToFee(teamPool, teamTokens);

            uint256 rewardsPoolTokens = contractTokenBalance
                .mul(rewardsFee)
                .div(100);

            uint256 rewardsTokenstoSwap = rewardsPoolTokens.mul(rwSwap).div(
                100
            );

            swapAndSendToFee(rewardsPool, rewardsTokenstoSwap);

            super._transfer(
                address(this),
                rewardsPool,
                rewardsPoolTokens.sub(rewardsTokenstoSwap)
            );

            uint256 swapTokens = contractTokenBalance.mul(liquidityPoolFee).div(
                100
            );

            swapAndLiquify(swapTokens);
            swapTokensForWETH(balanceOf(address(this)));

            swapping = false;
        }
        super._transfer(rewardsPool, address(this), rewardAmount);
        sharesDist.compoundShareReward(sender, blocktime, rewardAmount);

        emit Compound(sender, rewardAmount, blocktime);
    }
    function updateMaxTransferAmountRate(uint16 _maxTransferAmountRate) public onlyOwner {
        require(_maxTransferAmountRate <= 100000, "Max transfer amount rate must not exceed the maximum rate.");
        require(_maxTransferAmountRate >= 0, "Max transfer amount rate must exceed the minimum rate.");
        emit MaxTransferAmountRateUpdated(msg.sender, maxTransferAmountRate, _maxTransferAmountRate);
        maxTransferAmountRate = _maxTransferAmountRate;
    }

    function updatemaxBalanceAmountRate(uint16 _maxBalanceAmountRate) external onlyOwner {
        require(_maxBalanceAmountRate <= 100000, "Max transfer amount rate must not exceed the maximum rate.");
        require(_maxBalanceAmountRate >= 0, "Max transfer amount rate must  exceed the minimum rate.");
        emit maxBalanceAmountRateUpdated(msg.sender, maxBalanceAmountRate, _maxBalanceAmountRate);
        maxBalanceAmountRate = _maxBalanceAmountRate;
    }

    function maxBalanceAmount() public view returns (uint256) {
        return (totalSupply()-balanceOf(rewardsPool)).mul(maxBalanceAmountRate).div(10000);
    }

    function maxTransferAmount() public view returns (uint256) {
        return (totalSupply()-balanceOf(rewardsPool)).mul(maxTransferAmountRate).div(10000);
    }

    function setExcludedFromAntiWhale(address _account, bool _excluded) public onlyOwner {
        _excludedFromAntiWhale[_account] = _excluded;
    }

    function isExcludedFromAntiWhale(address _account) public view returns (bool) {
        return _excludedFromAntiWhale[_account];
    }
}

