//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./UniswapV2Interfaces.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./IWETH.sol";

interface IDividendDistributor {
    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external;
    function setShare(address shareholder, uint256 amount) external;
    function deposit() external payable;
    function process(uint256 gas) external;
}

contract DividendDistributor is IDividendDistributor {
    using SafeMath for uint256;

    address _token;

    struct Share {
        uint256 amount;
        uint256 totalExcluded;
        uint256 totalRealised;
    }

    IUniswapV2Router02 router;
    IWETH WETH;
    IERC20 RewardToken;

    address[] shareholders;
    mapping (address => uint256) shareholderIndexes;
    mapping (address => uint256) shareholderClaims;
    mapping (address => Share) public shares;

    uint256 public totalShares;
    uint256 public totalDividends;
    uint256 public totalDistributed;
    uint256 public dividendsPerShare;
    uint256 public dividendsPerShareAccuracyFactor = 10 ** 36;

    uint256 public minPeriod = 60 minutes;
    uint256 public minDistribution = 1 * (10 ** 6);

    uint256 currentIndex;

    bool initialized;
    modifier initialization() {
        require(!initialized);
        _;
        initialized = true;
    }

    modifier onlyToken() {
        require(msg.sender == _token); _;
    }

    constructor (address _router) {
        router = IUniswapV2Router02(_router);
        _token = msg.sender;
        WETH = IWETH(router.WETH());
        RewardToken = WETH;
    }

    function setDistributionCriteria(uint256 newMinPeriod, uint256 newMinDistribution) external override onlyToken {
        minPeriod = newMinPeriod;
        minDistribution = newMinDistribution;
    }

    function setShare(address shareholder, uint256 amount) external override onlyToken {

        if(shares[shareholder].amount > 0){
            distributeDividend(shareholder);
        }

        if(amount > 0 && shares[shareholder].amount == 0){
            addShareholder(shareholder);
        }else if(amount == 0 && shares[shareholder].amount > 0){
            removeShareholder(shareholder);
        }

        totalShares = totalShares.sub(shares[shareholder].amount).add(amount);
        shares[shareholder].amount = amount;
        shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
    }

    function deposit() external payable override onlyToken {

        uint256 balanceBefore = RewardToken.balanceOf(address(this));

        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(RewardToken);

        if(path[0] == path[1])
        {
            WETH.deposit{value: msg.value}();
        }
        else
        {
            router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: msg.value}(
                0,
                path,
                address(this),
                block.timestamp
            );
        }

        uint256 amount = RewardToken.balanceOf(address(this)).sub(balanceBefore);
        totalDividends = totalDividends.add(amount);
        dividendsPerShare = dividendsPerShare.add(dividendsPerShareAccuracyFactor.mul(amount).div(totalShares));
    }

    function process(uint256 gas) external override onlyToken {
        uint256 shareholderCount = shareholders.length;

        if(shareholderCount == 0) { return; }

        uint256 iterations = 0;
        uint256 gasUsed = 0;
        uint256 gasLeft = gasleft();

        while(gasUsed < gas && iterations < shareholderCount) {

            if(currentIndex >= shareholderCount){ currentIndex = 0; }

            if(shouldDistribute(shareholders[currentIndex])){
                distributeDividend(shareholders[currentIndex]);
            }

            gasUsed = gasUsed.add(gasLeft.sub(gasleft()));
            gasLeft = gasleft();
            currentIndex++;
            iterations++;
        }
    }

    function shouldDistribute(address shareholder) internal view returns (bool) {
        return shareholderClaims[shareholder] + minPeriod < block.timestamp
        && getUnpaidEarnings(shareholder) > minDistribution;
    }

    function distributeDividend(address shareholder) internal {
        if(shares[shareholder].amount == 0){ return; }

        uint256 amount = getUnpaidEarnings(shareholder);
        if(amount > 0){
            totalDistributed = totalDistributed.add(amount);
            RewardToken.transfer(shareholder, amount);
            shareholderClaims[shareholder] = block.timestamp;
            shares[shareholder].totalRealised = shares[shareholder].totalRealised.add(amount);
            shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
        }

    }

    function claimDividend(address shareholder) external onlyToken{
        distributeDividend(shareholder);
    }

//    function rescueDividends(address to) external onlyToken {
//        RewardToken.transfer(to, RewardToken.balanceOf(address(this)));
//    }

    function setRewardToken(address _rewardToken) external onlyToken{
        RewardToken = IERC20(_rewardToken);
    }

    function getUnpaidEarnings(address shareholder) public view returns (uint256) {
        if(shares[shareholder].amount == 0){ return 0; }

        uint256 shareholderTotalDividends = getCumulativeDividends(shares[shareholder].amount);
        uint256 shareholderTotalExcluded = shares[shareholder].totalExcluded;

        if(shareholderTotalDividends <= shareholderTotalExcluded){ return 0; }

        return shareholderTotalDividends.sub(shareholderTotalExcluded);
    }

    function getCumulativeDividends(uint256 share) internal view returns (uint256) {
        return share.mul(dividendsPerShare).div(dividendsPerShareAccuracyFactor);
    }

    function addShareholder(address shareholder) internal {
        shareholderIndexes[shareholder] = shareholders.length;
        shareholders.push(shareholder);
    }

    function removeShareholder(address shareholder) internal {
        shareholders[shareholderIndexes[shareholder]] = shareholders[shareholders.length-1];
        shareholderIndexes[shareholders[shareholders.length-1]] = shareholderIndexes[shareholder];
        shareholders.pop();
    }

}

abstract contract Auth {
    address internal owner;
    mapping (address => bool) internal authorizations;

    constructor(address _owner) {
        owner = _owner;
        authorizations[_owner] = true;
    }

    /**
     * Function modifier to require caller to be contract owner
     */
    modifier onlyOwner() {
        require(isOwner(msg.sender), "!OWNER"); _;
    }

    /**
     * Function modifier to require caller to be authorized
     */
    modifier authorized() {
        require(isAuthorized(msg.sender), "!AUTHORIZED"); _;
    }

    /**
     * Authorize address. Owner only
     */
    function authorize(address adr) public onlyOwner {
        authorizations[adr] = true;
    }

    /**
     * Remove address' authorization. Owner only
     */
    function unauthorize(address adr) public onlyOwner {
        authorizations[adr] = false;
    }

    /**
     * Check if address is owner
     */
    function isOwner(address account) public view returns (bool) {
        return account == owner;
    }

    /**
     * Return address' authorization status
     */
    function isAuthorized(address adr) public view returns (bool) {
        return authorizations[adr];
    }

    /**
     * Transfer ownership to new address. Caller must be owner.
     */
    function transferOwnership(address payable adr, bool authorizePreviousOwner) public onlyOwner {
        authorizations[owner] = authorizePreviousOwner;
        owner = adr;
        authorizations[adr] = true;
        emit OwnershipTransferred(adr);
    }

    /**
     * Transfer ownership to the zero address without authorizing it. Caller must be owner.
     */
    function renounceOwnership(address payable adr) public onlyOwner {
        authorizations[owner] = false;
        owner = address(0);
        //No need to authorize the zero address.
        emit OwnershipTransferred(adr);
    }

    event OwnershipTransferred(address owner);
}

contract SaintInu is IERC20, Auth {
    using SafeMath for uint256;

    string constant _name = "Saint Inu";
    string constant _symbol = "SAINT";
    uint8 constant _decimals = 18;

    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address constant ZERO = 0x0000000000000000000000000000000000000000;

    uint256 _totalSupply = 1200000000000 * (10 ** _decimals);
    uint256 public _maxTxAmount = _totalSupply;
    uint256 public _walletMax = _totalSupply;

    bool public restrictWhales = true;

    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowances;

    mapping (address => bool) public isFeeExempt;
    mapping (address => bool) public isTxLimitExempt;
    mapping (address => bool) public isDividendExempt;
    bool public blacklistMode = true;
    mapping(address => bool) public isBlacklisted;

    uint256 public liquidityFee = 0;
    uint256 public marketingFee = 0;
    uint256 public rewardsFee = 200;
    uint256 public devFee = 200;
    uint256 public buyMultiplier = 10000;
    uint256 public sellMultiplier = 10000;

    uint256 public totalFeeIfBuying = 0;
    uint256 public totalFeeIfSelling = 0;

    address public autoLiquidityReceiver;
    address public marketingWallet;
    address public devWallet;

    IUniswapV2Router02 public router;
    address public pair;
    IWETH WETH;

    uint256 public launchedAt;
    bool public tradingOpen = false;

    DividendDistributor public dividendDistributor;
    uint256 distributorGas = 750000;

    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;
    bool public alwaysLiquify = false;
    bool public swapAndLiquifyByLimitOnly = false;

    uint256 public swapThreshold = _totalSupply * 5 / 2000;

    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    constructor (address routerAddress, address _marketingWallet, address _devWallet, address _liquidityReceiver) Auth(msg.sender) {

        router = IUniswapV2Router02(routerAddress);
        WETH = IWETH(router.WETH());
        pair = IUniswapV2Factory(router.factory()).createPair(address(WETH), address(this));
        _allowances[address(this)][address(router)] = type(uint256).max;

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
        autoLiquidityReceiver = _liquidityReceiver;
        marketingWallet = _marketingWallet;
        devWallet = _devWallet;

        uint256 totalFee = liquidityFee.add(marketingFee).add(rewardsFee).add(devFee);
        totalFeeIfBuying = totalFee.mul(buyMultiplier).div(10000);
        totalFeeIfSelling = totalFee.mul(sellMultiplier).div(10000);

        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    receive() external payable { }

    function name() external pure returns (string memory) { return _name; }
    function symbol() external pure returns (string memory) { return _symbol; }
    function decimals() external pure returns (uint8) { return _decimals; }
    function totalSupply() external view override returns (uint256) { return _totalSupply.sub(balanceOf(DEAD)).sub(balanceOf(ZERO)); }
    function getOwner() external view returns (address) { return owner; }

    function getInitialSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function burn(uint256 amount) external
    {
        transfer(ZERO, amount);
    }

    function burnToDEAD(uint256 amount) external
    {
        transfer(DEAD, amount);
    }

    function burnFrom(address sender, uint256 amount) external
    {
        transferFrom(sender, ZERO, amount);
    }

    function burnFromToDEAD(address sender, uint256 amount) external
    {
        transferFrom(sender, DEAD, amount);
    }

    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, type(uint256).max);
    }

    function claimDividend() external {
        dividendDistributor.claimDividend(msg.sender);
    }

    function launched() internal view returns (bool) {
        return launchedAt != 0;
    }

    function changeBuyAndSellMultiplier(uint256 newBuyMulti, uint256 newSellMulti) external authorized{
        buyMultiplier = newBuyMulti;
        sellMultiplier = newSellMulti;
        uint256 totalFee = liquidityFee.add(marketingFee).add(rewardsFee).add(devFee);
        require(totalFee <= 1000);
        totalFeeIfBuying = totalFee.mul(buyMultiplier).div(10000);
        require(totalFeeIfBuying <= 1000);
        totalFeeIfSelling = totalFee.mul(sellMultiplier).div(10000);
        require(totalFeeIfSelling <= 1000);
    }

    function launch() internal {
        launchedAt = block.number;
    }

    function changeTxLimit(uint256 newLimit) external authorized {
        _maxTxAmount = newLimit;
    }

    function checkTxLimit(address sender, uint256 amount) internal view {
        require(amount <= _maxTxAmount || isTxLimitExempt[sender], "TX Limit Exceeded");
    }

    function enable_blacklist(bool _status) public onlyOwner {
        blacklistMode = _status;
    }

    function changeWalletLimit(uint256 newLimit) external authorized {
        _walletMax  = newLimit;
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

    function changeIsFeeExempt(address holder, bool exempt) external authorized {
        isFeeExempt[holder] = exempt;
    }

    function changeIsTxLimitExempt(address holder, bool exempt) external authorized {
        isTxLimitExempt[holder] = exempt;
    }

    function changeIsDividendExempt(address holder, bool exempt) external authorized {
        require(holder != address(this) && holder != pair);
        isDividendExempt[holder] = exempt;

        if(exempt){
            dividendDistributor.setShare(holder, 0);
        }else{
            dividendDistributor.setShare(holder, _balances[holder]);
        }
    }

    function changeFees(uint256 newLiqFee, uint256 newRewardFee, uint256 newMarketingFee, uint256 newDevFee) external authorized {
        liquidityFee = newLiqFee;
        rewardsFee = newRewardFee;
        marketingFee = newMarketingFee;
        devFee = newDevFee;

        uint256 totalFee = liquidityFee.add(marketingFee).add(rewardsFee).add(devFee);
        require(totalFee <= 1000);
        totalFeeIfBuying = totalFee.mul(buyMultiplier).div(10000);
        require(totalFeeIfBuying <= 1000);
        totalFeeIfSelling = totalFee.mul(sellMultiplier).div(10000);
        require(totalFeeIfSelling <= 1000);
    }

    function changeFeeReceivers(address newLiquidityReceiver, address newMarketingWallet, address newDevWallet) external authorized {
        autoLiquidityReceiver = newLiquidityReceiver;
        marketingWallet = newMarketingWallet;
        devWallet = newDevWallet;
    }

    function changeSwapBackSettings(bool enableSwapBack, uint256 newSwapBackLimit, bool swapByLimitOnly, bool enableAlwaysLiquify) external authorized {
        swapAndLiquifyEnabled  = enableSwapBack;
        swapThreshold = newSwapBackLimit;
        swapAndLiquifyByLimitOnly = swapByLimitOnly;
        alwaysLiquify = enableAlwaysLiquify;
    }

    function changeDistributionCriteria(uint256 newinPeriod, uint256 newMinDistribution) external authorized {
        dividendDistributor.setDistributionCriteria(newinPeriod, newMinDistribution);
    }

    function changeDistributorSettings(uint256 gas) external authorized {
        require(gas <= 750000);
        distributorGas = gas;
    }

    function setRewardToken(address _rewardToken) external authorized {
        dividendDistributor.setRewardToken(_rewardToken);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        return _transfer(msg.sender, recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {

        if(_allowances[sender][msg.sender] != type(uint256).max){
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender].sub(amount, "Insufficient Allowance");
        }
        return _transfer(sender, recipient, amount);
    }

    function _transfer(address sender, address recipient, uint256 amount) internal returns (bool) {

        if(inSwapAndLiquify){ return _basicTransfer(sender, recipient, amount); }

        if(!authorizations[sender] && !authorizations[recipient]){
            require(tradingOpen, "Trading not open yet");
        }

        require(amount <= _maxTxAmount || isTxLimitExempt[sender], "TX Limit Exceeded");

        if((msg.sender != pair || alwaysLiquify) && !inSwapAndLiquify && swapAndLiquifyEnabled && _balances[address(this)] >= swapThreshold){
            swapBack();
        }

        if(!launched() && recipient == pair) {
            require(_balances[sender] > 0);
            launch();
        }

        // Blacklist
        if (blacklistMode) {
            require(
                !isBlacklisted[sender] && !isBlacklisted[recipient],
                "Blacklisted");
        }

        if(recipient == pair && !authorizations[sender]) {
            require(tradingOpen, "Trading not open yet");
        }

        if(recipient != pair && !authorizations[recipient]) {
            require(tradingOpen, "Trading not open yet");
        }

        //Exchange tokens
        _balances[sender] = _balances[sender].sub(amount, "Insufficient Balance");

        if(!isTxLimitExempt[recipient] && restrictWhales)
        {
            require(_balances[recipient].add(amount) <= _walletMax);
        }

        uint256 finalAmount = !isFeeExempt[sender] && !isFeeExempt[recipient] ? takeFee(sender, recipient, amount) : amount;
        _balances[recipient] = _balances[recipient].add(finalAmount);

        // Dividend tracker
        if(!isDividendExempt[sender]) {
            try dividendDistributor.setShare(sender, _balances[sender]) {} catch {}
        }

        if(!isDividendExempt[recipient]) {
            try dividendDistributor.setShare(recipient, _balances[recipient]) {} catch {}
        }

        try dividendDistributor.process(distributorGas) {} catch {}

        emit Transfer(sender, recipient, finalAmount);
        return true;
    }

    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        _balances[sender] = _balances[sender].sub(amount, "Insufficient Balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }

    //Add liquidity (exempt from tax, uses inSwapAndLiquify)
    function feelessAddLiquidity(
        uint amountSAINTDesired,
        uint amountWETHDesired,
        uint amountSAINTMin,
        uint amountWETHMin,
        address to,
        uint deadline
    ) external lockTheSwap returns (uint amountSAINT, uint amountWETH, uint liquidity)
    {
        _basicTransfer(msg.sender, address(this), amountSAINTDesired);
        approve(address(router), amountSAINTDesired);
        WETH.transferFrom(msg.sender, address(this), amountWETHDesired);
        WETH.approve(address(router), amountWETHDesired);
        (amountSAINT, amountWETH, liquidity) = router.addLiquidity(address(this),
            address(WETH), amountSAINTDesired, amountWETHDesired,
            amountSAINTMin, amountWETHMin,
            to,
            deadline
        );
        //Get rid of dust approval + send back dust.
        if (amountSAINTDesired > amountSAINT)
        {
            approve(address(router), 0);
            _basicTransfer(address(this), msg.sender, amountSAINTDesired - amountSAINT);
        }
        if (amountWETHDesired > amountWETH)
        {
            WETH.approve(address(router), 0);
            WETH.transfer(msg.sender, amountWETHDesired - amountWETH);
        }
    }

    //Remove liquidity (exempt from tax, uses inSwapAndLiquify)
    function feelessRemoveLiquidity(
        uint liquidity,
        uint amountSAINTMin,
        uint amountWETHMin,
        address to,
        uint deadline
    ) external lockTheSwap returns (uint amountSAINT, uint amountWETH)
    {
        IERC20(pair).transferFrom(msg.sender, address(this), liquidity);
        IERC20(pair).approve(address(router), liquidity);
        (amountSAINT, amountWETH) = router.removeLiquidity(address(this),
            address(WETH), liquidity,
            amountSAINTMin, amountWETHMin,
            to,
            deadline
        );
    }

    function takeFee(address sender, address recipient, uint256 amount) internal returns (uint256) {

        uint256 feeApplicable = 0;
        if(pair == recipient) feeApplicable = totalFeeIfSelling;
        if(pair == sender) feeApplicable = totalFeeIfBuying;
        if(feeApplicable == 0) return amount; //Early out.
        uint256 feeAmount = amount.mul(feeApplicable).div(10000);

        _balances[address(this)] = _balances[address(this)].add(feeAmount);
        emit Transfer(sender, address(this), feeAmount);

        return amount.sub(feeAmount);
    }

    function openTrading() public onlyOwner {
        tradingOpen = true;
    }

    function swapBack() internal lockTheSwap {

        uint256 tokensToLiquify = _balances[address(this)];
        uint256 totalFee = liquidityFee.add(marketingFee).add(rewardsFee).add(devFee);
        uint256 amountToLiquify = tokensToLiquify.mul(liquidityFee).div(totalFee).div(2);
        uint256 amountToSwap = tokensToLiquify.sub(amountToLiquify);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = address(WETH);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 amountETH = address(this).balance;

        uint256 totalETHFee = totalFee.sub(liquidityFee.div(2));

        uint256 amountETHLiquidity = amountETH.mul(liquidityFee).div(totalETHFee).div(2);
        uint256 amountETHReflection = amountETH.mul(rewardsFee).div(totalETHFee);
        uint256 amountETHMarketing = amountETH.mul(marketingFee).div(totalETHFee);
        uint256 amountETHDev = amountETH.mul(devFee).div(totalETHFee);

        try dividendDistributor.deposit{value: amountETHReflection}() {} catch {}

        (bool tmpSuccess,) = payable(marketingWallet).call{value: amountETHMarketing, gas: 30000}("");
        (bool tmpSuccess1,) = payable(devWallet).call{value: amountETHDev, gas: 30000}("");

        // only to supress warning msg
        tmpSuccess = false;
        tmpSuccess1 = false;

        if(amountToLiquify > 0){
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

    event AutoLiquify(uint256 amountETH, uint256 amountSAINT);

}

