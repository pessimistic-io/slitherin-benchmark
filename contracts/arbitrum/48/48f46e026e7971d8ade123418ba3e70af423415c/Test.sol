// SPDX-License-Identifier: AGPL-3.0-or-later

/*



*/

pragma solidity ^0.8.13;

import "./ERC20.sol";

import "./IUniswapV2Router02.sol";
import "./IUniswapV2Factory.sol";
import "./DividendDistributor.sol";

abstract contract Auth {
    address internal owner;
    mapping(address => bool) internal authorizations;

    constructor(address _owner) {
        owner = _owner;
        authorizations[_owner] = true;
    }

    modifier onlyOwner() {
        require(isOwner(msg.sender), "!OWNER");
        _;
    }

    modifier authorized() {
        require(isAuthorized(msg.sender), "!AUTHORIZED");
        _;
    }

    function authorize(address adr) public onlyOwner {
        authorizations[adr] = true;
    }

    function unauthorize(address adr) public onlyOwner {
        authorizations[adr] = false;
    }

    function isOwner(address account) public view returns (bool) {
        return account == owner;
    }

    function isAuthorized(address adr) public view returns (bool) {
        return authorizations[adr];
    }

    function renounceOwnership(address payable adr) public onlyOwner {
        owner = adr;
        authorizations[adr] = true;
        emit OwnershipTransferred(adr);
    }

    event OwnershipTransferred(address owner);
}

contract Test is ERC20, Auth {
    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;

    uint256 public _totalSupply;
    uint256 public _maxTxAmount;
    uint256 public _maxWalletToken;

    mapping(address => bool) public isFeeExempt;
    mapping(address => bool) public isTxLimitExempt;
    mapping(address => bool) public isDividendExempt;
    mapping(address => bool) public canAddLiquidityBeforeLaunch;

    // Detailed Fees
    uint256 public liquidityFee;
    uint256 public reflectionFee;
    uint256 public marketingFee;
    uint256 public totalFee;

    uint256 public buyLiquidityFee = 2;
    uint256 public buyReflectionFee = 3;
    uint256 public buyMarketingFee = 1;
    uint256 public buyTotalFee = 6;

    uint256 public sellLiquidityFee = 3;
    uint256 public sellReflectionFee = 6;
    uint256 public sellMarketingFee = 3;
    uint256 public sellTotalFee = 12;


    // Fees receivers
    address public autoLiquidityReceiver;
    address public marketingFeeReceiver;

    IUniswapV2Router02 public router;
    address public pair;

    bool public tradingOpen = false;

    DividendDistributor public distributor;
    uint256 distributorGas = 500000;

    bool public swapEnabled = true;
    bool inSwap;
    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    uint256 public swapThreshold = (_totalSupply / (1000)) * (1); // 0.1%

    event AutoLiquify(uint256 amountETH, uint256 amountTokens);

    constructor() Auth(msg.sender) ERC20("Test", "TEST") {
        _totalSupply = 10 * 10e10 * 10e50; // 9 decimals

        _maxTxAmount = (_totalSupply * 2) / 100; // 2%
        _maxWalletToken = (_totalSupply * 3) / 100; // 3%

        router = IUniswapV2Router02(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506); // sushi router
        distributor = new DividendDistributor(address(router));

        pair = IUniswapV2Factory(router.factory()).createPair(
            router.WETH(),
            address(this)
        );


        isFeeExempt[msg.sender] = true;
        isTxLimitExempt[msg.sender] = true;

        canAddLiquidityBeforeLaunch[msg.sender] = true;

        isDividendExempt[pair] = true;
        isDividendExempt[address(this)] = true;
        isDividendExempt[DEAD] = true;

        autoLiquidityReceiver = 0x8c6Aa7506D6d97E54fb1A1E0F8226d53b65b5cCe;
        marketingFeeReceiver = 0x29C6796f8cc8d7f6d4AD65b64DC34f8DC0d0B0F9;

        _approve(address(this), address(router), type(uint256).max);
        _approve(msg.sender, address(router), _totalSupply);

        _mint(msg.sender, _totalSupply);
    }

    receive() external payable {}

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (inSwap) {
            super._transfer(from, to, amount);
            return;
        }

        // Avoid airdropped from ADD LP before launch
        if (!tradingOpen && to == pair && from == pair) {
            require(canAddLiquidityBeforeLaunch[from]);
        }

        if (!authorizations[from] && !authorizations[to]) {
            require(tradingOpen, "Trading not open yet");
        }

        // max wallet code
        if (
            !authorizations[from] &&
            to != address(this) &&
            to != address(DEAD) &&
            to != pair &&
            to != marketingFeeReceiver &&
            to != autoLiquidityReceiver
        ) {
            uint256 heldTokens = balanceOf(to);
            require(
                (heldTokens + amount) <= _maxWalletToken,
                "Total Holding is currently limited, you can not buy that much."
            );
        }

        // Checks max transaction limit
        checkTxLimit(from, amount);

        if (from == pair) {
            buyFees();
        }

        if (to == pair) {
            sellFees();
        }

        //Exchange tokens
        if (shouldSwapBack()) {
            swapBack();
        }

        uint256 amountReceived = shouldTakeFee(from)
            ? takeFee(to, amount)
            : amount;
        super._transfer(from, to, amountReceived);

        // Dividend tracker
        if (!isDividendExempt[from]) {
            try distributor.setShare(from, balanceOf(from)) {} catch {}
        }

        if (!isDividendExempt[to]) {
            try distributor.setShare(to, balanceOf(to)) {} catch {}
        }

        try distributor.process(distributorGas) {} catch {}
    }

    function enableTrading() external onlyOwner {
        tradingOpen = true;
    }

    function setMaxTx(uint multiplier) external onlyOwner {
        _maxTxAmount = (_totalSupply * multiplier) / 100;
    }

    function setMaxWallet(uint multiplier) external onlyOwner {
        _maxWalletToken = (_totalSupply * multiplier) / 100;
    }

    function checkTxLimit(address from, uint256 amount) internal view {
        require(
            amount <= _maxTxAmount || isTxLimitExempt[from],
            "TX Limit Exceeded"
        );
    }

    // Internal Functions
    function buyFees() internal {
        liquidityFee = buyLiquidityFee;
        reflectionFee = buyReflectionFee;
        marketingFee = buyMarketingFee;
        totalFee = buyTotalFee;
    }

    function sellFees() internal {
        liquidityFee = sellLiquidityFee;
        reflectionFee = sellReflectionFee;
        marketingFee = sellMarketingFee;
        totalFee = sellTotalFee;
    }

    function shouldTakeFee(address from) internal view returns (bool) {
        return !isFeeExempt[from];
    }

    function takeFee(address from, uint256 amount) internal returns (uint256) {
        uint256 feeAmount = (amount / 100) * (totalFee);
        super._transfer(from, address(this), feeAmount);

        return amount - (feeAmount);
    }

    function shouldSwapBack() internal view returns (bool) {
        return
            msg.sender != pair &&
            !inSwap &&
            swapEnabled &&
            balanceOf(address(this)) >= swapThreshold;
    }

    function swapBack() internal swapping {
        uint256 tokensToSell = swapThreshold;

        uint256 amountToLiquify = ((tokensToSell / (totalFee)) *
            (liquidityFee)) / (2);
        uint256 amountToSwap = tokensToSell - (amountToLiquify);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        uint256 balanceBefore = address(this).balance;

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 amountETH = address(this).balance - (balanceBefore);

        uint256 totalETHFee = totalFee - (liquidityFee / (2));

        uint256 amountETHLiquidity = (amountETH * (liquidityFee)) /
            (totalETHFee) /
            (2);
        uint256 amountETHReflection = (amountETH * (reflectionFee)) /
            (totalETHFee);
        uint256 amountETHMarketing = (amountETH * (marketingFee)) /
            (totalETHFee);

        try distributor.deposit{value: amountETHReflection}() {} catch {}
        (bool MarketingSuccess, ) = payable(marketingFeeReceiver).call{
            value: amountETHMarketing,
            gas: 30000
        }("");
        require(MarketingSuccess, "receiver rejected ETH transfer");

        if (amountToLiquify > 0) {
            router.addLiquidityETH{value: amountETHLiquidity}(
                address(this),
                amountToLiquify,
                0,
                0,
                autoLiquidityReceiver,
                block.timestamp
            );
            emit AutoLiquify(amountETHLiquidity, amountToLiquify);
        }
    }

    // Stuck Balances Functions
    function rescueToken(address tokenAddress, uint256 tokens)
        public
        onlyOwner
        returns (bool success)
    {
        return IERC20(tokenAddress).transfer(msg.sender, tokens);
    }

    function clearStuckBalance(uint256 amountPercentage) external authorized {
        uint256 amountETH = address(this).balance;
        payable(marketingFeeReceiver).transfer(
            (amountETH * amountPercentage) / 100
        );
    }

    function setSellFees(
        uint256 _liquidityFee,
        uint256 _reflectionFee,
        uint256 _marketingFee,
        uint256 _devFee
    ) external authorized {
        sellLiquidityFee = _liquidityFee;
        sellReflectionFee = _reflectionFee;
        sellMarketingFee = _marketingFee;
        sellTotalFee =
            _liquidityFee +
            (_reflectionFee) +
            (_marketingFee) +
            (_devFee);
    }

    // External Functions
    function checkSwapThreshold() external view returns (uint256) {
        return swapThreshold;
    }

    function isNotInSwap() external view returns (bool) {
        return !inSwap;
    }

    function setFeeReceivers(
        address _autoLiquidityReceiver,
        address _marketingFeeReceiver
    ) external authorized {
        autoLiquidityReceiver = _autoLiquidityReceiver;
        marketingFeeReceiver = _marketingFeeReceiver;
    }

    function setSwapBackSettings(bool _enabled, uint256 _percentage_base10000)
        external
        authorized
    {
        swapEnabled = _enabled;
        swapThreshold = (_totalSupply / (10000)) * (_percentage_base10000);
    }

    function setCanTransferBeforeLaunch(address holder, bool exempt)
        external
        authorized
    {
        canAddLiquidityBeforeLaunch[holder] = exempt; //Presale Address will be added as Exempt
        isTxLimitExempt[holder] = exempt;
        isFeeExempt[holder] = exempt;
    }

    function setIsDividendExempt(address holder, bool exempt)
        external
        authorized
    {
        require(holder != address(this) && holder != pair);
        isDividendExempt[holder] = exempt;
        if (exempt) {
            distributor.setShare(holder, 0);
        } else {
            distributor.setShare(holder, balanceOf(holder));
        }
    }

    function setIsFeeExempt(address holder, bool exempt) external authorized {
        isFeeExempt[holder] = exempt;
    }

    function setIsTxLimitExempt(address holder, bool exempt)
        external
        authorized
    {
        isTxLimitExempt[holder] = exempt;
    }

    function setDistributionCriteria(
        uint256 _minPeriod,
        uint256 _minDistribution
    ) external authorized {
        distributor.setDistributionCriteria(_minPeriod, _minDistribution);
    }

    function setDistributorSettings(uint256 gas) external authorized {
        require(gas < 900000);
        distributorGas = gas;
    }
}

