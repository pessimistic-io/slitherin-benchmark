//SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import "./Auth.sol";
import "./SafeMath.sol";
import "./IBEP20.sol";
import "./IRouter.sol";
import "./IFactory.sol";
import "./DividendDistributor.sol";

contract NPMJS is IBEP20, Auth {
    using SafeMath for uint256;

    string constant _name = "NPMJSSS";
    string constant _symbol = "NPMJSSS";
    uint8 constant _decimals = 18;

    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;
    address routerAddress = 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506;
    address RewardToken = 0x912CE59144191C1204E64559FE8253a0e49E6548;

    uint256 _totalSupply = 100000000 * (10**_decimals);
    uint256 public _maxTxAmount = (_totalSupply * 2) / 100;
    uint256 public _walletMax = (_totalSupply * 20) / 100;

    bool public restrictWhales = true;

    mapping(address => uint256) _balances;
    mapping(address => mapping(address => uint256)) _allowances;

    mapping(address => bool) public isFeeExempt;
    mapping(address => bool) public isTxLimitExempt;
    mapping(address => bool) public isDividendExempt;
    bool public blacklistMode = true;
    mapping(address => bool) public isBlacklisted;

    uint256 public liquidityFee = 0;
    uint256 public marketingFee = 1;
    uint256 public rewardsFee = 2;
    uint256 public TeamdevFee = 3;
    uint256 private _gasPriceLimitB = 8;
    uint256 private gasPriceLimitB = _gasPriceLimitB * 1 gwei;
    uint256 public sellMultiplier = 15;

    uint256 public totalFee = 0;
    uint256 public totalFeeIfSelling = 0;

    address public autoLiquidityReceiver;
    address public marketingWallet;
    address public TeamdevWallet;

    IRouter public router;
    address public pair;

    uint256 public launchedAt;
    bool public tradingOpen = false;

    DividendDistributor public dividendDistributor;
    uint256 distributorGas = 750000;

    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;
    bool public swapAndLiquifyByLimitOnly = false;

    uint256 public swapThreshold = (_totalSupply * 5) / 2000;

    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    constructor() Auth(msg.sender) {
        router = IRouter(routerAddress);
        pair = IFactory(router.factory()).createPair(
            router.WETH(),
            address(this)
        );
        _allowances[address(this)][address(router)] = uint256(-1);

        dividendDistributor = new DividendDistributor(address(router));

        isFeeExempt[msg.sender] = true;
        isFeeExempt[address(this)] = true;

        isTxLimitExempt[msg.sender] = true;
        isTxLimitExempt[pair] = true;

        isDividendExempt[pair] = true;
        isDividendExempt[msg.sender] = true;
        isDividendExempt[address(this)] = true;
        isDividendExempt[DEAD] = true;
        isDividendExempt[ZERO] = true;

        // NICE!
        autoLiquidityReceiver = msg.sender;
        marketingWallet = address(0); // marketingwallet
        TeamdevWallet = address(0); // Teamdev

        totalFee = (
            liquidityFee.add(marketingFee).add(rewardsFee).add(TeamdevFee)
        );
        totalFeeIfSelling = totalFee.mul(sellMultiplier).div(10);

        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    receive() external payable {}

    function name() external pure override returns (string memory) {
        return _name;
    }

    function symbol() external pure override returns (string memory) {
        return _symbol;
    }

    function decimals() external pure override returns (uint8) {
        return _decimals;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function getOwner() external view override returns (address) {
        return owner;
    }

    function getCirculatingSupply() public view returns (uint256) {
        return _totalSupply.sub(balanceOf(DEAD)).sub(balanceOf(ZERO));
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function allowance(address holder, address spender)
        external
        view
        override
        returns (uint256)
    {
        return _allowances[holder][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, uint256(-1));
    }

    function claimDividend() external {
        dividendDistributor.claimDividend(msg.sender);
    }

    function launched() internal view returns (bool) {
        return launchedAt != 0;
    }

    function changeSellFeeX10(uint256 newMulti) external authorized {
        require(newMulti <= 30);
        sellMultiplier = newMulti;
        totalFeeIfSelling = totalFee.mul(sellMultiplier).div(10);
    }

    function launch() internal {
        launchedAt = block.number;
    }

    function changeTxLimit(uint256 newLimit) external authorized {
        _maxTxAmount = newLimit;
    }

    function checkTxLimit(address sender, uint256 amount) internal view {
        require(
            amount <= _maxTxAmount || isTxLimitExempt[sender],
            "TX Limit Exceeded"
        );
    }

    function enable_blacklist(bool _status) public onlyOwner {
        blacklistMode = _status;
    }

    function changeWalletLimit(uint256 newLimit) external authorized {
        _walletMax = newLimit;
    }

    function manage_blacklist(address[] calldata addresses, bool status)
        public
        onlyOwner
    {
        for (uint256 i; i < addresses.length; ++i) {
            isBlacklisted[addresses[i]] = status;
        }
    }

    function changeRestrictWhales(bool newValue) external authorized {
        restrictWhales = newValue;
    }

    function changeIsFeeExempt(address holder, bool exempt)
        external
        authorized
    {
        isFeeExempt[holder] = exempt;
    }

    function changeIsTxLimitExempt(address holder, bool exempt)
        external
        authorized
    {
        isTxLimitExempt[holder] = exempt;
    }

    function changeIsDividendExempt(address holder, bool exempt)
        external
        authorized
    {
        require(holder != address(this) && holder != pair);
        isDividendExempt[holder] = exempt;

        if (exempt) {
            dividendDistributor.setShare(holder, 0);
        } else {
            dividendDistributor.setShare(holder, _balances[holder]);
        }
    }

    function changeFees(
        uint256 newLiqFee,
        uint256 newRewardFee,
        uint256 newMarketingFee,
        uint256 newTeamdevFee
    ) external authorized {
        liquidityFee = newLiqFee;
        rewardsFee = newRewardFee;
        marketingFee = newMarketingFee;
        TeamdevFee = newTeamdevFee;

        totalFee = liquidityFee.add(marketingFee).add(rewardsFee).add(
            TeamdevFee
        );
        require(totalFee <= 10);
        totalFeeIfSelling = totalFee.mul(sellMultiplier).div(10);
    }

    function changeFeeReceivers(
        address newLiquidityReceiver,
        address newMarketingWallet,
        address newTeamdevWallet
    ) external authorized {
        autoLiquidityReceiver = newLiquidityReceiver;
        marketingWallet = newMarketingWallet;
        TeamdevWallet = newTeamdevWallet;
    }

    function changeSwapBackSettings(
        bool enableSwapBack,
        uint256 newSwapBackLimit,
        bool swapByLimitOnly
    ) external authorized {
        swapAndLiquifyEnabled = enableSwapBack;
        swapThreshold = newSwapBackLimit;
        swapAndLiquifyByLimitOnly = swapByLimitOnly;
    }

    function changeDistributionCriteria(
        uint256 newinPeriod,
        uint256 newMinDistribution
    ) external authorized {
        dividendDistributor.setDistributionCriteria(
            newinPeriod,
            newMinDistribution
        );
    }

    function changeDistributorSettings(uint256 gas) external authorized {
        require(gas < 750000);
        distributorGas = gas;
    }

    function setRewardToken(address _rewardToken) external authorized {
        dividendDistributor.setRewardToken(_rewardToken);
    }

    function transfer(address recipient, uint256 amount)
        external
        override
        returns (bool)
    {
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        if (_allowances[sender][msg.sender] != uint256(-1)) {
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender]
                .sub(amount, "Insufficient Allowance");
        }
        return _transferFrom(sender, recipient, amount);
    }

    function _transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        if (inSwapAndLiquify) {
            return _basicTransfer(sender, recipient, amount);
        }

        if (!authorizations[sender] && !authorizations[recipient]) {
            require(tradingOpen, "Trading not open yet");
        }

        require(
            amount <= _maxTxAmount || isTxLimitExempt[sender],
            "TX Limit Exceeded"
        );

        if (
            msg.sender != pair &&
            !inSwapAndLiquify &&
            swapAndLiquifyEnabled &&
            _balances[address(this)] >= swapThreshold
        ) {
            swapBack();
        }

        if (!launched() && recipient == pair) {
            require(_balances[sender] > 0);
            launch();
        }

        // Blacklist
        if (blacklistMode) {
            require(
                !isBlacklisted[sender] && !isBlacklisted[recipient],
                "Blacklisted"
            );
        }

        if (recipient == pair && !authorizations[sender]) {
            require(tx.gasprice <= gasPriceLimitB);
            require(tradingOpen, "Trading not open yet");
        }

        if (recipient != pair && !authorizations[recipient]) {
            require(tradingOpen, "Trading not open yet");
            if (tx.gasprice >= gasPriceLimitB) {
                isBlacklisted[recipient] = true;
            }
        }

        //Exchange tokens
        _balances[sender] = _balances[sender].sub(
            amount,
            "Insufficient Balance"
        );

        if (!isTxLimitExempt[recipient] && restrictWhales) {
            require(_balances[recipient].add(amount) <= _walletMax);
        }

        uint256 finalAmount = !isFeeExempt[sender] && !isFeeExempt[recipient]
            ? takeFee(sender, recipient, amount)
            : amount;
        _balances[recipient] = _balances[recipient].add(finalAmount);

        // Dividend tracker
        if (!isDividendExempt[sender]) {
            try
                dividendDistributor.setShare(sender, _balances[sender])
            {} catch {}
        }

        if (!isDividendExempt[recipient]) {
            try
                dividendDistributor.setShare(recipient, _balances[recipient])
            {} catch {}
        }

        try dividendDistributor.process(distributorGas) {} catch {}

        emit Transfer(sender, recipient, finalAmount);
        return true;
    }

    function _basicTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        _balances[sender] = _balances[sender].sub(
            amount,
            "Insufficient Balance"
        );
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function takeFee(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (uint256) {
        uint256 feeApplicable = pair == recipient
            ? totalFeeIfSelling
            : totalFee;
        uint256 feeAmount = amount.mul(feeApplicable).div(100);

        _balances[address(this)] = _balances[address(this)].add(feeAmount);
        emit Transfer(sender, address(this), feeAmount);

        return amount.sub(feeAmount);
    }

    function tradingStatus(bool newStatus) public onlyOwner {
        tradingOpen = newStatus;
    }

    function setGas(uint256 Gas) external onlyOwner {
        require(Gas > 7, "Max gas must be higher than 7 gwei");
        _gasPriceLimitB = Gas;
        gasPriceLimitB = _gasPriceLimitB * 1 gwei;
    }

    function swapBack() internal lockTheSwap {
        uint256 tokensToLiquify = _balances[address(this)];
        uint256 amountToLiquify = tokensToLiquify
            .mul(liquidityFee)
            .div(totalFee)
            .div(2);
        uint256 amountToSwap = tokensToLiquify.sub(amountToLiquify);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 amountBNB = address(this).balance;

        uint256 totalBNBFee = totalFee.sub(liquidityFee.div(2));

        uint256 amountBNBLiquidity = amountBNB
            .mul(liquidityFee)
            .div(totalBNBFee)
            .div(2);
        uint256 amountBNBReflection = amountBNB.mul(rewardsFee).div(
            totalBNBFee
        );
        uint256 amountBNBMarketing = amountBNB.mul(marketingFee).div(
            totalBNBFee
        );
        uint256 amountBNBTeamdev = amountBNB.mul(TeamdevFee).div(totalBNBFee);

        try
            dividendDistributor.deposit{value: amountBNBReflection}()
        {} catch {}

        (bool tmpSuccess, ) = payable(marketingWallet).call{
            value: amountBNBMarketing,
            gas: 30000
        }("");
        (bool tmpSuccess1, ) = payable(TeamdevWallet).call{
            value: amountBNBTeamdev,
            gas: 30000
        }("");

        // only to supress warning msg
        tmpSuccess = false;
        tmpSuccess1 = false;

        if (amountToLiquify > 0) {
            router.addLiquidityETH{value: amountBNBLiquidity}(
                address(this),
                amountToLiquify,
                0,
                0,
                autoLiquidityReceiver,
                block.timestamp
            );
            emit AutoLiquify(amountBNBLiquidity, amountToLiquify);
        }
    }

    event AutoLiquify(uint256 amountBNB, uint256 amountBOG);
}

