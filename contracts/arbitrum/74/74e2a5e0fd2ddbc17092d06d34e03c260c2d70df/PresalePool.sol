pragma solidity ^0.5.16;

import "./SafeMath.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./IUniswapRouter01.sol";
import "./IUniswapPair.sol";
import "./IWETH.sol";
import "./BasisPoints.sol";
import "./ITierLocker.sol";
import "./IERC20Token.sol";
import "./IPresaleTimer.sol";

contract PresalePool is Ownable, ReentrancyGuard {
    using BasisPoints for uint256;
    using SafeMath for uint256;

    IUniswapRouter01 public mainRouter;
    IUniswapPair public pair;
    IERC20 public rewardToken;
    address payable private WETH;

    IERC20 public depositToken;

    uint256 public maxBuyPerAddressBase;

    uint256 public dexEthBP;
    uint256 public launchpadTierBP;
    address payable[] public ethPools;
    uint256[] public ethPoolBPs;

    uint256 public dexTokenBP;
    uint256 public presaleTokenBP;
    address[] public tokenPools;
    uint256[] public tokenPoolBPs;

    uint256 public presalePrice;
    uint256 public presaleTierPriceBP;

    bool public hasSentToDEX;
    bool public hasIssuedTokens;
    bool public hasSentEth;
    bool public hasSwappedReward;

    uint256 public totalSupply;
    uint256 public totalPresaleTokens;
    uint256 public totalPrivateSaleTokens;
    uint256 public totalTokens;
    uint256 public totalSoldTokens;
    uint256 public totalDepositedEth;
    uint256 public totalEth;
    uint256 public totalReward;
    uint256 public finalEndTime;

    IERC20Token public token;
    IPresaleTimer public timer;
    ITierLocker public tierLock;

    uint256[] public tierCounts = [0, 0, 0, 0, 0];
    uint256[] public tierLockedAmounts;
    address[] public path;
    mapping(address => uint256) public userTierLevel;

    mapping(address => uint256) public depositAccounts;
    mapping(address => uint256) public accountEarnedToken;
    mapping(address => uint256) public accountClaimedToken;
    mapping(address => uint256) public accountClaimedReward;

    uint256 public totalDepositors;

    bool public pauseDeposit;

    modifier whenPresaleActive() {
        require(timer.isPresalePeriod(), "Presale not started yet.");
        _;
    }

    modifier whenPresaleFinished() {
        require(timer.isPresaleFinished(), "Presale not finished yet.");
        _;
    }

    modifier whenLiquidityEnabled() {
        require(
            timer.isLiquidityEnabled(),
            "Liquidity creation not enabled yet."
        );
        _;
    }

    modifier whenDistributionStarted() {
        require(
            timer.isTierDistributionTime(),
            "Tier distribution not started yet."
        );
        _;
    }

    modifier whenAddedLiquidity() {
        require(hasSentToDEX, "Liquidity not added yet.");
        _;
    }

    function initialize(
        uint256 _maxBuyPerAddressBase,
        uint256 _presalePrice,
        uint256 _presaleTierPriceBP,
        address _owner,
        address _timer,
        address _token,
        address _tierLock,
        address _mainRouter,
        address _pair,
        address payable _WETH,
        address _rewardToken
    ) external initializer {
        require(
            IERC20Token(_token).isMinter(address(this)),
            "Presale SC must be minter."
        );
        Ownable.initialize(msg.sender);
        ReentrancyGuard.initialize();

        token = IERC20Token(_token);
        timer = IPresaleTimer(_timer);
        tierLock = ITierLocker(_tierLock);

        maxBuyPerAddressBase = _maxBuyPerAddressBase;

        presalePrice = _presalePrice;
        presaleTierPriceBP = _presaleTierPriceBP;

        mainRouter = IUniswapRouter01(_mainRouter);
        WETH = _WETH;
        rewardToken = IERC20(_rewardToken);
        pair = IUniswapPair(_pair);

        //Due to issue in oz testing suite, the msg.sender might not be owner
        _transferOwnership(_owner);
    }

    // Owner functions --------------------------------
    function setTotalPresaleTokens(
        uint256 _totalPresaleTokens,
        address _depositTokenAddress,
        uint256 _totalSupply
    ) external onlyOwner {
        totalPresaleTokens = _totalPresaleTokens;
        depositToken = IERC20(_depositTokenAddress);
        totalSupply = _totalSupply;
    }

    function setSwapInfo(
        address _pair,
        address _rewardToken,
        address[] calldata _path
    ) external onlyOwner {
        rewardToken = IERC20(_rewardToken);
        pair = IUniswapPair(_pair);
        delete path;
        for (uint256 i = 0; i < _path.length; i++) {
            path.push(_path[i]);
        }
    }

    function setEthPools(
        uint256 _dexEthBP,
        uint256 _launchpadTierBP,
        address payable[] calldata _ethPools,
        uint256[] calldata _ethPoolBPs
    ) external onlyOwner {
        require(
            _ethPools.length == _ethPoolBPs.length,
            "Must have exactly one etherPool addresses for each BP."
        );
        delete ethPools;
        delete ethPoolBPs;
        dexEthBP = _dexEthBP;
        launchpadTierBP = _launchpadTierBP;
        uint256 totalEthPoolsBP = _dexEthBP.add(_launchpadTierBP);
        for (uint256 i = 0; i < _ethPools.length; i++) {
            ethPools.push(_ethPools[i]);
            ethPoolBPs.push(_ethPoolBPs[i]);
            totalEthPoolsBP = totalEthPoolsBP.add(_ethPoolBPs[i]);
        }
        require(
            totalEthPoolsBP == 10000,
            "Must allocate exactly 100% (10000 BP) of ether to pools"
        );
    }

    function setTokenPools(
        uint256 _dexTokenBP,
        uint256 _presaleTokenBP,
        address[] calldata _tokenPools,
        uint256[] calldata _tokenPoolBPs
    ) external onlyOwner {
        require(
            _tokenPools.length == _tokenPoolBPs.length,
            "Must have exactly one tokenPool addresses for each BP."
        );
        delete tokenPools;
        delete tokenPoolBPs;
        dexTokenBP = _dexTokenBP;
        presaleTokenBP = _presaleTokenBP;
        uint256 totalTokenPoolBPs = _dexTokenBP.add(_presaleTokenBP);
        for (uint256 i = 0; i < _tokenPools.length; i++) {
            tokenPools.push(_tokenPools[i]);
            tokenPoolBPs.push(_tokenPoolBPs[i]);
            totalTokenPoolBPs = totalTokenPoolBPs.add(_tokenPoolBPs[i]);
        }
        require(
            totalTokenPoolBPs == 10000,
            "Must allocate exactly 100% (10000 BP) of tokens to pools"
        );
    }

    function setPrivateSaleTokens(
        address[] calldata _tokenHolders,
        uint256[] calldata _tokenAmounts
    ) external onlyOwner {
        require(
            _tokenHolders.length == _tokenAmounts.length,
            "Must have exactly one tokenholder addresses for each token amount."
        );
        for (uint256 i = 0; i < _tokenHolders.length; i++) {
            if (_tokenAmounts[i] == 0) {
                totalPrivateSaleTokens = totalPrivateSaleTokens.sub(
                    accountEarnedToken[_tokenHolders[i]]
                );
                accountEarnedToken[_tokenHolders[i]] = 0;
            } else {
                totalPrivateSaleTokens = totalPrivateSaleTokens.add(
                    _tokenAmounts[i]
                );
            }
            accountEarnedToken[_tokenHolders[i]] = accountEarnedToken[
                _tokenHolders[i]
            ].add(_tokenAmounts[i]);
        }
    }

    function sendToDEX() external whenLiquidityEnabled nonReentrant {
        require(ethPools.length > 0, "Must have set ether pools");
        require(tokenPools.length > 0, "Must have set token pools");
        require(!hasSentToDEX, "Has already sent to DEX.");
        finalEndTime = now + 15;
        hasSentToDEX = true;
        totalTokens = totalSoldTokens.divBP(presaleTokenBP);
        uint256 dexTokens = totalTokens.mulBP(dexTokenBP);
        token.mint(address(this), dexTokens);
        token.approve(address(mainRouter), dexTokens);
        uint256 dexETH = 0;
        if (isETHMode()) {
            totalEth = address(this).balance;
            dexETH = totalEth.mulBP(dexEthBP);
            mainRouter.addLiquidityETH.value(dexETH)(
                address(token),
                dexTokens,
                dexTokens,
                dexETH,
                address(0x000000000000000000000000000000000000dEaD),
                finalEndTime
            );
        } else {
            totalEth = depositToken.balanceOf(address(this));
            dexETH = totalEth.mulBP(dexEthBP);
            depositToken.approve(address(mainRouter), dexETH);
            mainRouter.addLiquidity(
                address(depositToken),
                address(token),
                dexETH,
                dexTokens,
                dexETH,
                dexTokens,
                address(0x000000000000000000000000000000000000dEaD),
                finalEndTime
            );
        }
    }

    function issueTokens() external whenLiquidityEnabled whenAddedLiquidity {
        require(!hasIssuedTokens, "Has already issued tokens.");
        hasIssuedTokens = true;
        for (uint256 i = 0; i < tokenPools.length; ++i) {
            if (tokenPoolBPs[i] > 0) {
                token.mint(tokenPools[i], totalTokens.mulBP(tokenPoolBPs[i]));
            }
        }
        token.mint(address(this), totalSoldTokens.add(totalPrivateSaleTokens));
        uint256 _allMinted = totalTokens.add(totalPrivateSaleTokens);
        if (_allMinted < totalSupply) {
            token.mint(tokenPools[0], totalSupply.sub(_allMinted));
        }
    }

    function sendEth()
        external
        whenLiquidityEnabled
        whenAddedLiquidity
        nonReentrant
    {
        require(!hasSentEth, "Has already sent Eth.");
        hasSentEth = true;
        bool _ok = true;
        for (uint256 i = 0; i < ethPools.length; ++i) {
            if (ethPoolBPs[i] > 0) {
                if (isETHMode()) {
                    ethPools[i].transfer(totalEth.mulBP(ethPoolBPs[i]));
                } else {
                    bool _result = depositToken.transfer(
                        ethPools[i],
                        totalEth.mulBP(ethPoolBPs[i])
                    );
                    if (!_result) _ok = false;
                }
            }
        }
        require(_ok, "Token Transfer failed.");
        totalReward = totalEth.mulBP(launchpadTierBP);
    }

    function setTierLockedAmounts() external onlyOwner {
        delete tierLockedAmounts;
        delete tierCounts;
        uint256[5] memory _tierLockedAmounts = tierLock.getTierLockedAmount();
        uint256[5] memory _tierCounts = tierLock.getTierCounts();
        for (uint256 i = 0; i < _tierLockedAmounts.length; i++) {
            tierLockedAmounts.push(_tierLockedAmounts[i]);
            tierCounts.push(_tierCounts[i]);
        }
    }

    function emergencyEthWithdrawl()
        external
        whenLiquidityEnabled
        whenAddedLiquidity
        nonReentrant
        onlyOwner
    {
        msg.sender.transfer(address(this).balance);
    }

    function emergencyTokenWithdraw(address _tokenAddr)
        external
        whenDistributionStarted
        whenAddedLiquidity
        nonReentrant
        onlyOwner
    {
        IERC20(_tokenAddr).transfer(
            msg.sender,
            IERC20(_tokenAddr).balanceOf(address(this))
        );
    }

    function setDepositPause(bool val) external onlyOwner {
        pauseDeposit = val;
    }

    // user functions
    function deposit(address payable _referrer, uint256 _amount)
        public
        payable
        whenPresaleActive
        nonReentrant
    {
        require(!pauseDeposit, "Deposits are paused.");
        require(
            _referrer == address(0x0),
            "Referrer is not used in this version."
        );
        uint256 depositVal = msg.value;
        if (isETHMode()) {
            require(depositVal == _amount, "Invalid ETH amount");
        } else {
            require(msg.value == 0, "Invalid Token amount");
            depositVal = _amount;
        }
        if (timer.isTierPresalePeriod()) {
            require(
                depositAccounts[msg.sender].add(depositVal) <=
                    maxBuyPerAddressBase.mul(tierLock.getUserTier(msg.sender)),
                "Deposit exceeds max buy per address for addresses."
            );
            require(
                tierLock.getUserTier(msg.sender) > 0,
                "User need to have tier"
            );
        } else {
            require(
                depositAccounts[msg.sender].add(depositVal) <=
                    maxBuyPerAddressBase,
                "Deposit exceeds max buy per address for addresses."
            );
        }

        uint256 tokensToIssue = depositVal.mul(10**18).div(
            calculateRatePerEth()
        );
        require(
            totalSoldTokens.add(tokensToIssue) <= totalPresaleTokens,
            "Presale Done"
        );
        if (!isETHMode()) {
            uint256 allowance = depositToken.allowance(
                msg.sender,
                address(this)
            );
            require(depositVal <= allowance, "Insufficient allowance.");

            bool _ok = depositToken.transferFrom(
                msg.sender,
                address(this),
                depositVal
            );
            require(_ok, "Transfer from failed.");
        }

        depositAccounts[msg.sender] = depositAccounts[msg.sender].add(
            depositVal
        );
        totalDepositedEth = totalDepositedEth.add(depositVal);
        totalSoldTokens = totalSoldTokens.add(tokensToIssue);

        accountEarnedToken[msg.sender] = accountEarnedToken[msg.sender].add(
            tokensToIssue
        );
    }

    function redeem() external whenLiquidityEnabled whenAddedLiquidity {
        uint256 claimable = calculateReedemable(msg.sender);
        require(claimable > 0, "Must have claimable amount.");
        require(accountClaimedToken[msg.sender] == 0, "Already claimed user.");
        accountClaimedToken[msg.sender] = claimable;
        token.transfer(msg.sender, claimable);
    }

    function calculateReedemable(address _account)
        public
        view
        returns (uint256)
    {
        if (!hasSentToDEX) return 0;
        uint256 earnedToken = accountEarnedToken[_account];
        uint256 claimable = earnedToken.sub(accountClaimedToken[_account]);
        return claimable;
    }

    function redeemTier() external whenDistributionStarted {
        require(hasSentEth, "Must have sent Eth before any redeem tiers.");
        uint256 claimable = calculateReedemableTier(msg.sender);
        require(claimable > 0, "Must have claimable amount.");
        require(accountClaimedReward[msg.sender] == 0, "Already claimed user.");
        accountClaimedReward[msg.sender] = claimable; // Eth/usdt unit
        uint256 swappedReward = 0;
        if (isETHMode()) {
            swappedReward = xETH2Reward(claimable, address(pair));
        } else {
            uint256 _allowance = depositToken.allowance(
                address(this),
                address(mainRouter)
            );
            if (_allowance < claimable) {
                depositToken.approve(address(mainRouter), totalReward);
            }
            swappedReward = xTOKEN2Reward(claimable, path);
        }
        rewardToken.transfer(msg.sender, swappedReward);
    }

    function calculateReedemableTier(address _account)
        public
        view
        returns (uint256)
    {
        (
            uint256 _tier,
            uint256 _lockedTimestamp,
            uint256 _lockedAmount
        ) = tierLock.getUserTierInfos(_account);
        if (_tier == 0) return 0;
        if (!timer.isTierClaimable(_lockedTimestamp)) return 0;
        if (_lockedAmount == 0) return 0;
        if (tierLockedAmounts[_tier] <= 0) return 0;
        uint256 _earnedReward = totalReward
            .mulBP(tierLock.getTierBP(_tier))
            .mul(_lockedAmount)
            .div(tierLockedAmounts[_tier]);
        uint256 claimable = _earnedReward.sub(accountClaimedReward[_account]);
        return claimable;
    }

    function calculateRatePerEth() public view returns (uint256) {
        if (timer.isTierPresalePeriod()) return presalePrice;
        return presalePrice.addBP(presaleTierPriceBP);
    }

    function isETHMode() public view returns (bool) {
        return (address(depositToken) == address(0));
    }

    // internal functions
    function xETH2Reward(uint256 _amountETH, address _pair)
        internal
        returns (
            uint256 // _amountReward
        )
    {
        require(isETHMode(), "Please use ERC20 functions.");
        IWETH(WETH).deposit.value(_amountETH)();
        _safeTransfer(address(WETH), _pair, _amountETH);
        uint256 _amountReward = _toERC20(_pair, _amountETH);
        hasSwappedReward = true;
        return _amountReward;
    }

    function xTOKEN2Reward(uint256 _amountToken, address[] memory _path)
        internal
        returns (
            uint256 // _amountReward
        )
    {
        require(!isETHMode(), "Please use ETH functions.");
        require(_amountToken > 0, "Amount invalid");
        require(_path.length > 0, "Swap Path invalid");
        finalEndTime = now + 15;
        hasSwappedReward = true;
        uint256[] memory _amounts = mainRouter.getAmountsOut(
            _amountToken,
            _path
        );
        mainRouter.swapExactTokensForTokens(
            _amountToken,
            0,
            _path,
            address(this),
            finalEndTime
        );
        return _amounts[_path.length - 1];
    }

    function _safeTransfer(
        address _token,
        address _to,
        uint256 _amount
    ) internal {
        IERC20(_token).transfer(_to, _amount);
    }

    // newly added code for ERC20 conversion
    function _toERC20(address _pair, uint256 _amountInWeth)
        internal
        returns (
            uint256 // amountOut
        )
    {
        (uint256 reserve0, uint256 reserve1, ) = IUniswapPair(_pair)
            .getReserves();
        address token0 = IUniswapPair(_pair).token0();
        (uint256 reserveIn, uint256 reserveOut) = token0 == WETH
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
        uint256 amountInWithFee = _amountInWeth.mul(9975);
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(10000).add(amountInWithFee);
        uint256 _amountOut = numerator / denominator;
        (uint256 amount0Out, uint256 amount1Out) = token0 == WETH
            ? (uint256(0), _amountOut)
            : (_amountOut, uint256(0));
        IUniswapPair(_pair).swap(
            amount0Out,
            amount1Out,
            address(this),
            new bytes(0)
        );
        return _amountOut;
    }
}

