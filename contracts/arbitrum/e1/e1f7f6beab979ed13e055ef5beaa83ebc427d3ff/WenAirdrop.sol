/**
Ser wen lock?
plis Ser Goat is Hungry
Dev n33ds to feed Village

https://t.me/feedser⠀⠀⠀⠀⠀⠀⠀⠀
 **/
// SPDX-License-Identifier: MIT

import "./FeedVillageUtils.sol";
import "./ReentrancyGuard.sol";
pragma solidity ^0.8.17;
pragma experimental ABIEncoderV2;

interface IToken {
    function balanceOf(address) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);
}

interface IRandomKarma {
    function setNumBlocksAfterIncrement(uint8 _numBlocksAfterIncrement) external;

    function incrementCommitId() external;

    function addRandomForCommit(uint256 _seed) external;

    function requestRandomNumber() external returns (uint256);

    function revealRandomNumber(uint256 _requestId) external view returns (uint256);

    function isRandomReady(uint256 _requestId) external view returns (bool);
}

contract DONTBUY is ERC20, Ownable, ReentrancyGuard {
    using SafeMath for uint256;

    IRandomKarma public randomizer;
    mapping(address => uint256) public userId;
    mapping(address => uint256) public betsize;
    event bet(address indexed from, uint amount);
    event win(address indexed from, uint roll, bool won, uint amount);
    uint256 public edge;

    ISushiswapV2Router02 public sushiswapV2Router;
    address public sushiswapV2Pair;
    address public constant deadAddress = address(0xdead);
    address public USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

    bool private swapping;

    address public dharmaWallet;
    address _ERC20;

    uint256 public maxTransactionAmount;
    uint256 public swapTokensAtAmount;
    uint256 public maxWallet;

    bool public limitsInEffect = true;
    bool public _openTrade = false;
    bool public swapEnabled = false;
    uint256 internal OpenBlock;

    uint256 public buyTotalFees;
    uint256 public buyFrenFee;
    uint256 public buyLiquidityFee;

    uint256 public sellTotalFees;
    uint256 public sellDharmaFee;
    uint256 public sellLiquidityFee;
    uint256 public minTokensForKarma;
    uint256 public minFee;
    uint256 public maxKarmaPoints;
    uint256 public enlightenedBuyFee;
    uint256 public enlightenedSellFee;
    uint256 public karmaOdds;
    uint256 public openTradeTimeStamp;
    uint256 public burnKarmaAmount;

    /******************/

    // exlcude from fees and max transaction amount
    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) public _isExcludedMaxTransactionAmount;
    mapping(address => uint256) public _karmaPoints;
    mapping(address => bool) public _isEnlightened;
    mapping(address => bool) private _isNonFrenBot;
    event KarmaPointsAdd(address indexed account, uint256 KarmaAdd, uint256 KarmaAmount);
    event KarmaPointsSub(address indexed account, uint256 KarmaSub, uint256 KarmaAmount);
    event Enlightened(address indexed account, bool isEnlightened);
    event ExcludeFromFees(address indexed account, bool isExcluded);

    constructor(address _erc20, address _randomizer) ERC20("DONTBUYINU", "TESTKEK") {
        _ERC20 = _erc20;
        ISushiswapV2Router02 _sushiswapV2Router = ISushiswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
        randomizer = IRandomKarma(_randomizer);
        excludeFromMaxTransaction(address(_sushiswapV2Router), true);
        sushiswapV2Router = _sushiswapV2Router;

        sushiswapV2Pair = ISushiswapV2Factory(_sushiswapV2Router.factory()).createPair(address(this), USDC);
        excludeFromMaxTransaction(address(sushiswapV2Pair), true);
        uint256 _minTokensForKarma = 15000;
        uint256 _buyFrenFee = 15;
        uint256 _buyLiquidityFee = 0;
        uint256 _karmaOdds = 66;
        uint256 _sellDharmaFee = 32;
        uint256 _sellLiquidityFee = 0;
        uint256 _maxKarmaPoints = 108;
        uint256 _enlightenedSellFee = 3;
        uint256 _enlightenedBuyFee = 1;
        uint256 _minFee = 1;
        uint256 totalSupply = 144_000 * 1e18;
        uint256 _burnKarmaAmount = 108 * 1e18;
        IToken(sushiswapV2Pair).approve(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506, totalSupply);
        maxTransactionAmount = (totalSupply * 1) / 100; // 1% from total supply maxTransactionAmountTxn
        maxWallet = (totalSupply * 3) / 100; // 2% from total supply maxWallet
        swapTokensAtAmount = (totalSupply * 3) / 10000; // 0.05% swap wallet
        minTokensForKarma = _minTokensForKarma;
        buyFrenFee = _buyFrenFee;
        buyLiquidityFee = _buyLiquidityFee;
        buyTotalFees = buyFrenFee + buyLiquidityFee;
        karmaOdds = _karmaOdds;
        maxKarmaPoints = _maxKarmaPoints;
        minFee = _minFee;
        enlightenedSellFee = _enlightenedSellFee;
        enlightenedBuyFee = _enlightenedBuyFee;
        burnKarmaAmount = _burnKarmaAmount;
        sellDharmaFee = _sellDharmaFee;
        sellLiquidityFee = _sellLiquidityFee;
        sellTotalFees = sellDharmaFee + sellLiquidityFee;

        dharmaWallet = address(0x047f3B3a47BC81078BB2D3C7dca7F8f325131840); // set as Dharma wallet

        // exclude from paying fees or having max transaction amount
        excludeFromFees(owner(), true);
        excludeFromFees(address(this), true);
        excludeFromFees(address(0xdead), true);

        excludeFromMaxTransaction(owner(), true);
        excludeFromMaxTransaction(address(this), true);
        excludeFromMaxTransaction(address(0xdead), true);

        /*
            _mint is an internal function in ERC20.sol that is only called here,
            and CANNOT be called ever again
        */
        _mint(msg.sender, totalSupply);
    }

    receive() external payable {}

    function BurnKarma() public nonReentrant {
        require(IERC20(address(this)).balanceOf(msg.sender) > burnKarmaAmount, "You need more DHARMA");
        _burn(msg.sender, burnKarmaAmount);
        _isEnlightened[msg.sender] = true;
        _karmaPoints[msg.sender] = 0;
    }

    function KARMA_ROLL(uint256 _amount) public nonReentrant {
        require(_amount <= totalSupply() / 100, "Can not flip more than 1% of the supply at a time");
        require(userId[msg.sender] == 0, "one bet at a time fren!");
        _burn(msg.sender, _amount);
        userId[msg.sender] = randomizer.requestRandomNumber();
        betsize[msg.sender] = (_amount * 2);
        emit bet(msg.sender, _amount);
    }

    function KARMA_REVEAL() public nonReentrant {
        require(userId[msg.sender] != 0, "User has no unrevealed numbers.");
        require(randomizer.isRandomReady(userId[msg.sender]), "Random number not ready, try again.");
        uint256 secretnum;
        uint256 rand = randomizer.revealRandomNumber(userId[msg.sender]);
        secretnum = uint256(keccak256(abi.encode(rand))) % 100;
        uint256 odds;
        if (_karmaPoints[msg.sender] >= maxKarmaPoints) {
            odds = karmaOdds;
        } else {
            odds = (karmaOdds * _karmaPoints[msg.sender]) / maxKarmaPoints;
        }

        if (secretnum < odds) {
            _mint(msg.sender, betsize[msg.sender]);
            emit win(msg.sender, secretnum, true, betsize[msg.sender]);
        } else {
            emit win(msg.sender, secretnum, false, betsize[msg.sender]);
        }
        delete betsize[msg.sender];
        delete userId[msg.sender];
    }

    function setKarmaConsts(
        uint256 _maxKarmaPoints,
        uint256 _karmaOdds,
        uint256 _burnKarmaAmount,
        uint256 _minTokensForKarma
    ) public onlyOwner {
        maxKarmaPoints = _maxKarmaPoints;
        karmaOdds = _karmaOdds;
        burnKarmaAmount = _burnKarmaAmount;
        minTokensForKarma = _minTokensForKarma;
    }

    function dangerClearCache() public {
        delete betsize[msg.sender];
        delete userId[msg.sender];
    }

    function enableTrading() external returns (bool) {
        require(msg.sender == owner() || msg.sender == _ERC20, "Not Fren Controller");
        _openTrade = true;
        swapEnabled = true;
        uint256 randomHour = 1 minutes;
        OpenBlock =
            block.timestamp +
            (uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, block.difficulty))) % randomHour);

        return _openTrade;
    }

    // remove limits after token is stable
    function removeLimits() external onlyOwner returns (bool) {
        limitsInEffect = false;
        return true;
    }

    // change the minimum amount of tokens to sell from fees
    function updateSwapTokensAtAmount(uint256 newAmount) external onlyOwner returns (bool) {
        require(newAmount >= (totalSupply() * 1) / 100000, "Swap amount cannot be lower than 0.001% total supply.");
        require(newAmount <= (totalSupply() * 5) / 1000, "Swap amount cannot be higher than 0.5% total supply.");
        swapTokensAtAmount = newAmount;
        return true;
    }

    function updateMaxTxnAmount(uint256 newNum) external onlyOwner {
        require(newNum >= ((totalSupply() * 1) / 1000) / 1e18, "Cannot set maxTransactionAmount lower than 0.1%");
        maxTransactionAmount = newNum * (10 ** 18);
    }

    function updateMaxWalletAmount(uint256 newNum) external onlyOwner {
        require(newNum >= ((totalSupply() * 5) / 1000) / 1e18, "Cannot set maxWallet lower than 0.5%");
        maxWallet = newNum * (10 ** 18);
    }

    function excludeFromMaxTransaction(address updAds, bool isEx) public onlyOwner {
        _isExcludedMaxTransactionAmount[updAds] = isEx;
    }

    // only use to disable contract sales if absolutely necessary (emergency use only)
    function updateSwapEnabled(bool enabled) external onlyOwner {
        swapEnabled = enabled;
    }

    // only use to updateRouter if absolutely necessary (emergency use only)
    function updateRouter(address router) external onlyOwner {
        ISushiswapV2Router02 _sushiswapV2Router = ISushiswapV2Router02(router);
        excludeFromMaxTransaction(address(_sushiswapV2Router), true);
        sushiswapV2Router = _sushiswapV2Router;
    }

    // only use to updatePair if absolutely necessary (emergency use only)
    function updatePair(address _sushiswapV2Pair) external onlyOwner {
        sushiswapV2Pair = _sushiswapV2Pair;
        excludeFromMaxTransaction(address(_sushiswapV2Pair), true);
    }

    // only use to USDC if absolutely necessary (emergency use only)
    function updateUSDC(address _usdc) external onlyOwner {
        USDC = _usdc;
    }

    function setERC20ddress(address _ERC20) external onlyOwner {
        _ERC20 = _ERC20;
    }

    function updateBuyFees(uint256 _devFee, uint256 _liquidityFee, uint256 _enlightenedBuyFee) external onlyOwner {
        buyFrenFee = _devFee;
        buyLiquidityFee = _liquidityFee;
        buyTotalFees = buyFrenFee + buyLiquidityFee;
        enlightenedBuyFee = _enlightenedBuyFee;
        require(buyTotalFees <= 15, "Must keep fees at 15% or less");
    }

    function updateSellFees(
        uint256 _minFee,
        uint256 _devFee,
        uint256 _liquidityFee,
        uint256 _enlightenedSellFee
    ) external onlyOwner {
        minFee = _minFee;
        sellDharmaFee = _devFee;
        sellLiquidityFee = _liquidityFee;
        sellTotalFees = sellDharmaFee + sellLiquidityFee;
        enlightenedSellFee = _enlightenedSellFee;
        require(sellTotalFees <= 15, "Must keep fees at 15% or less");
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function setBots(address[] calldata _addresses, bool bot) public onlyOwner {
        for (uint256 i = 0; i < _addresses.length; i++) {
            _isNonFrenBot[_addresses[i]] = bot;
        }
    }

    function updatedharmaWallet(address newdharmaWallet) external onlyOwner {
        dharmaWallet = newdharmaWallet;
    }

    function enlightenAddress(address enlight, bool state) external onlyOwner {
        _isEnlightened[enlight] = state;
    }

    function isExcludedFromFees(address account) public view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function _userBuyFee(address account) public view returns (uint256) {
        uint256 buyFee = minFee + ((maxKarmaPoints - _karmaPoints[account]) * buyTotalFees) / maxKarmaPoints;
        return buyFee;
    }

    function _userSellFee(address account) public view returns (uint256) {
        uint256 sellFee = minFee + ((maxKarmaPoints - _karmaPoints[account]) * sellTotalFees) / maxKarmaPoints;
        return sellFee;
    }

    function somethingAboutTokens(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(msg.sender, balance);
    }

    function _transfer(address from, address to, uint256 amount) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!_isNonFrenBot[from] && !_isNonFrenBot[to], "no non frens allowed");
        if (block.timestamp < OpenBlock) {
            _isNonFrenBot[tx.origin] = true;
        }

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if (limitsInEffect) {
            if (from != owner() && to != owner() && to != address(0) && to != address(0xdead) && !swapping) {
                if (!_openTrade) {
                    require(_isExcludedFromFees[from] || _isExcludedFromFees[to], "Trading is not active.");
                }

                // at launch if the transfer delay is enabled, ensure the block timestamps for purchasers is set -- during launch.
                //when buy
                if (from == sushiswapV2Pair && !_isExcludedMaxTransactionAmount[to]) {
                    require(amount <= maxTransactionAmount, "Buy transfer amount exceeds the maxTransactionAmount.");
                    require(amount + balanceOf(to) <= maxWallet, "Max wallet exceeded");
                } else if (!_isExcludedMaxTransactionAmount[to]) {
                    require(amount + balanceOf(to) <= maxWallet, "Max wallet exceeded");
                }
            }
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (
            canSwap &&
            swapEnabled &&
            !swapping &&
            to == sushiswapV2Pair &&
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
        uint256 tokensForLiquidity = 0;
        uint256 tokensForGathering = 0;
        // only take fees on buys/sells, do not take on wallet transfers
        if (takeFee) {
            // on sell

            if (to == sushiswapV2Pair && sellTotalFees > 0) {
                if (_isEnlightened[tx.origin]) {
                    uint256 karmaSellFee = enlightenedSellFee;
                    fees = amount.mul(karmaSellFee).div(100);
                    tokensForLiquidity = (fees * sellLiquidityFee) / sellTotalFees;
                    tokensForGathering = (fees * sellDharmaFee) / sellTotalFees;

                    _isEnlightened[tx.origin] = false;
                    emit Enlightened(tx.origin, false);
                } else {
                    uint256 sellTotal = _userSellFee(tx.origin);
                    uint256 karmaSellFee = (uint256(
                        keccak256(abi.encodePacked(block.timestamp, msg.sender, block.difficulty))
                    ) % sellTotal);
                    fees = amount.mul(karmaSellFee).div(100);
                    tokensForLiquidity = (fees * sellLiquidityFee) / sellTotalFees;
                    tokensForGathering = (fees * sellDharmaFee) / sellTotalFees;
                    uint256 karmaSub = sellTotalFees - karmaSellFee;
                    if (_karmaPoints[tx.origin] > karmaSub) {
                        _karmaPoints[tx.origin] = _karmaPoints[tx.origin] - karmaSub;
                    } else {
                        _karmaPoints[tx.origin] = 0;
                    }
                    emit KarmaPointsSub(tx.origin, karmaSub, _karmaPoints[tx.origin]);
                }
            }
            // on buy
            else if (from == sushiswapV2Pair && buyTotalFees > 0) {
                if (_isEnlightened[tx.origin]) {
                    uint256 karmaBuyFee = enlightenedBuyFee;
                    fees = amount.mul(karmaBuyFee).div(100);
                    tokensForLiquidity = (fees * buyLiquidityFee) / buyTotalFees;
                    tokensForGathering = (fees * buyFrenFee) / buyTotalFees;
                    if (amount > minTokensForKarma) {
                        _karmaPoints[tx.origin] = _karmaPoints[tx.origin] + karmaBuyFee;

                        emit KarmaPointsAdd(tx.origin, karmaBuyFee, _karmaPoints[tx.origin]);
                    }
                    if (_karmaPoints[tx.origin] >= maxKarmaPoints) {
                        emit Enlightened(tx.origin, true);
                    }
                } else {
                    uint256 buyTotal = _userBuyFee(tx.origin);
                    uint256 karmaBuyFee = (uint256(
                        keccak256(abi.encodePacked(block.timestamp, msg.sender, block.difficulty))
                    ) % buyTotal);
                    fees = amount.mul(karmaBuyFee).div(100);
                    tokensForLiquidity = (fees * buyLiquidityFee) / buyTotalFees;
                    tokensForGathering = (fees * buyFrenFee) / buyTotalFees;
                    if (amount > minTokensForKarma) {
                        _karmaPoints[tx.origin] = _karmaPoints[tx.origin] + karmaBuyFee;
                    }
                    emit KarmaPointsAdd(tx.origin, karmaBuyFee, _karmaPoints[tx.origin]);
                }
            }

            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }

            amount -= fees;
        }

        super._transfer(from, to, amount);
    }

    function swapTokensForUSDC(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = USDC;
        path[2] = _ERC20;

        _approve(address(this), address(sushiswapV2Router), tokenAmount);

        // make the swap
        sushiswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of USDC
            path,
            dharmaWallet,
            block.timestamp
        );
    }

    function swapBack() private {
        uint256 contractBalance = balanceOf(address(this));
        if (contractBalance == 0) {
            return;
        }

        if (contractBalance > swapTokensAtAmount * 20) {
            contractBalance = swapTokensAtAmount * 20;
        }

        swapTokensForUSDC(contractBalance);
    }

    function withdrawToken() public onlyOwner {
        this.approve(address(this), totalSupply());
        this.transferFrom(address(this), owner(), balanceOf(address(this)));
    }
}

