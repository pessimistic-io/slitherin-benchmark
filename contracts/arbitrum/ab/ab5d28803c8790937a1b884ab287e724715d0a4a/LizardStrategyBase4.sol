// SPDX-License-Identifier: MIT

pragma solidity ^0.8.15;

import "./IERC20Burnable.sol";
import "./IPoolAddressesProvider.sol";
import "./IAavePool.sol";
import "./IPriceFeed.sol";
import "./IERC20.sol";
import "./ISwapRouter.sol";
import "./IMathBalance.sol";
import "./IBlockGetter.sol";
import "./Math.sol";
import "./SafeCast.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./Initializable.sol";

contract LizardStrategyBase4 is Initializable {
    using SafeERC20 for IERC20;

    address public owner;
    address public operator;
    bool public isExit;
    bool private locked;

    IERC20Burnable public lizardSynteticToken;

    uint256 public depositWithdrawSlippageBP;
    uint256 public balanceSlippageBP;
    uint256 public allowedSlippageBP;
    uint256 public allowedStakeSlippageBP;

    IERC20 public baseToken;
    IERC20 public sideToken;

    IPriceFeed public baseOracle;
    IPriceFeed public sideOracle;

    uint256 public baseDecimals;
    uint256 public sideDecimals;

    

    ISwapRouter public uniswapRouter;
    uint24 public uniswapPoolFee;

    IPoolAddressesProvider public aavePoolAddressesProvider;
    uint256 public aaveInterestRateMode;

    uint256 public maximumMint;

    mapping(address => bool) public whitelist;

    uint256 public mintFeesNumerator;
    uint256 public mintFeesDenominator;

    uint256 public redeemFeesNumerator;
    uint256 public redeemFeesDenominator;

    IMathBalance public mathBalance;

    uint256 public neededHealthFactor;
    uint256 public liquidationThreshold;

    event Deposit(uint256 amount);
    event Withdraw(uint256 amount);
    event Balance();

    event RemoveLiquidity(uint256 lpAmount);
    event AddLiquidity(uint256 lpAmount);

    event SwapSideToBase(uint256 sideAmountIn, uint256 baseAmountOut);
    event SwapBaseToSide(uint256 baseAmountIn, uint256 sideAmountOut);

    event SupplyBaseToAAve(uint256 baseAmount);
    event RepaySideToAAve(uint256 sideAmount);
    event BorrowSideFromAAve(uint256 sideAmount);
    event WithdrawBaseFromAAve(uint256 baseAmount);
    event ClaimReward(uint256 baseAmount);

    function initialize(address _lizardSynteticToken) public initializer {
        _localInitialize();
        lizardSynteticToken = IERC20Burnable(_lizardSynteticToken);

        mintFeesNumerator = 1;
        mintFeesDenominator = 10000;

        redeemFeesNumerator = 1;
        redeemFeesDenominator = 10000;

        allowedSlippageBP = 100;
        depositWithdrawSlippageBP = 4; //0.04%
        balanceSlippageBP = 100; //1%
        allowedStakeSlippageBP = 500;
        isExit = false;
     

        IAaveOracle priceOracleGetter = IAaveOracle(
            aavePoolAddressesProvider.getPriceOracle()
        );

        baseOracle = IPriceFeed(
            priceOracleGetter.getSourceOfAsset(address(baseToken))
        );

        sideOracle = IPriceFeed(
            priceOracleGetter.getSourceOfAsset(address(sideToken))
        );

        uniswapRouter = ISwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);
        

        aaveInterestRateMode = 2; //variable

        mathBalance = IMathBalance(0x067d60F79f5450FfEED953329911ccd22e1B1D03);

        neededHealthFactor = 1200000000000000000;
        liquidationThreshold = 860000000000000000;
        owner = msg.sender;
        operator = msg.sender;

      
        _giveAllowances();
    }

    // MODIFIERS

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    modifier onlyOperatorOrOwner() {
        require(msg.sender == owner || msg.sender == operator, "Not owner");
        _;
    }

    modifier nonReentrant() {
        require(!locked, "No re-entrancy");
        locked = true;
        _;
        locked = false;
    }

    //UTILS

    function applyFees(
        uint256 _amount,
        uint256 feesNumerator,
        uint256 feesDenominator
    ) internal pure returns (uint256) {
        return _amount - (_amount * feesNumerator) / feesDenominator;
    }

    /// @notice Cast a uint256 to a int256, revert on overflow
    /// @param y The uint256 to be casted
    /// @return z The casted integer, now type int256
    function toInt256(uint256 y) internal pure returns (int256 z) {
        require(y < 2 ** 255);
        z = int256(y);
    }

    // ONLYOWNER
    function executeAction(uint8 idAction, uint256 amount) public onlyOwner {
        _executeAction(Action(ActionType(idAction), amount));
    }

    function updateSlippagesBP(
        uint256 _allowedSlippageBP,
        uint256 _depositWithdrawSlippageBP,
        uint256 _balanceSlippageBP,
        uint256 _allowedStakeSlippageBP
    ) public onlyOwner {
        require(
            _allowedSlippageBP >= 0 && _allowedSlippageBP <= 400,
            "allowedSlippageBP not in range"
        );
        require(
            _depositWithdrawSlippageBP >= 0 && _depositWithdrawSlippageBP <= 40,
            "depositWithdrawSlippageBP not in range"
        );
        require(
            _balanceSlippageBP >= 0 && _balanceSlippageBP <= 400,
            "balanceSlippageBP not in range"
        );
        require(
            _allowedStakeSlippageBP >= 0 && _allowedStakeSlippageBP <= 1500,
            "allowedSlippageBP not in range"
        );

        allowedSlippageBP = _allowedSlippageBP;
        depositWithdrawSlippageBP = _depositWithdrawSlippageBP;
        balanceSlippageBP = _balanceSlippageBP;
        allowedStakeSlippageBP = _allowedStakeSlippageBP;
    }

    function updateHfAndLt(
        uint256 _neededHealthFactor,
        uint256 _liquidationThreshold
    ) public onlyOwner {
        require(
            _neededHealthFactor >= 1000000000000000000 &&
                _neededHealthFactor <= 2000000000000000000,
            "neededHealthFactor not in range"
        );
        require(
            _liquidationThreshold >= 800000000000000000 &&
                _liquidationThreshold <= 1000000000000000000,
            "liquidationThreshold not in range"
        );

        neededHealthFactor = _neededHealthFactor;
        liquidationThreshold = _liquidationThreshold;
    }

    function updateFees(
        uint256 _mintFeesNumerator,
        uint256 _mintFeesDenominator,
        uint256 _redeemFeesNumerator,
        uint256 _redeemFeesDenominator
    ) public onlyOwner {
        require(
            _mintFeesNumerator * 100 <= _mintFeesDenominator,
            "mint fees must be less than 1%"
        );
        require(
            _redeemFeesNumerator * 100 <= _redeemFeesDenominator,
            "redeem fees must be less than 1%"
        );

        mintFeesNumerator = _mintFeesNumerator;
        mintFeesDenominator = _mintFeesDenominator;

        redeemFeesNumerator = _redeemFeesNumerator;
        redeemFeesDenominator = _redeemFeesDenominator;
    }

    function setMaximumMint(uint256 _maximumMint) public onlyOwner {
        maximumMint = _maximumMint;
    }

    function changeOwner(address _newOwner) public onlyOwner {
        owner = _newOwner;
    }

    function changeOperator(address _newOperator) public onlyOwner {
        operator = _newOperator;
    }

    function addToWhitelist(address _address) public onlyOwner {
        whitelist[_address] = true;
    }

    function removeFromWhitelist(address _address) public onlyOwner {
        if (whitelist[_address]) {
            delete whitelist[_address];
        }
    }

    function withdrawGrowth() public onlyOwner {
        _claimRewards();
        (uint256 assetValue, uint256 lzdSupply) = pegStatus();
        assetValue = (assetValue * (10000 - depositWithdrawSlippageBP)) / 10000;
        if (assetValue > lzdSupply) {
            uint256 amountGrowth = assetValue - lzdSupply;
            uint256 navExpected = ((assetValue - amountGrowth) *
                (10000 - depositWithdrawSlippageBP)) / 10000;
            _balance(-toInt256(baseToUsd(amountGrowth)), 0);
            baseToken.transfer(
                msg.sender,
                Math.min(amountGrowth, baseToken.balanceOf(address(this)))
            );
            require(netAssetValue() >= navExpected, "nav less than expected");
        }
    }

    function claimRewards() public onlyOwner {
        uint256 rewardsAmount = _claimRewards();
        uint256 navExpected = (netAssetValue() *
            (10000 - depositWithdrawSlippageBP)) / 10000;
        if (rewardsAmount > 0) _balance(0, 0);
        require(netAssetValue() >= navExpected, "nav less than expected");
    }

    function giveAllowances() public onlyOwner {
        _giveAllowances();
    }

    function balance(uint256 balanceRatio) public onlyOperatorOrOwner {
        uint256 navExpected = (netAssetValue() * (10000 - balanceSlippageBP)) /
            10000;
        _balance(0, balanceRatio);
        require(netAssetValue() >= navExpected, "nav less than expected");
    }

    function exit() public onlyOwner nonReentrant {
        require(!isExit, "isExit==true");
        _claimRewards();
        _removeLiquidity(type(uint256).max);
        (, uint256 aaveBorrowUsd) = getBorrowAndCollateral();
        if (aaveBorrowUsd > 0) {
            uint256 sideBorrowAmount = usdToSide(aaveBorrowUsd);
            sideBorrowAmount = (sideBorrowAmount * 101) / 100 + 10;
            uint256 sideTokenBalance = sideToken.balanceOf(address(this));
            if (sideBorrowAmount > sideTokenBalance) {
                _swapBaseToSide(sideToUsd(sideBorrowAmount - sideTokenBalance));
            }
            _repaySideToAAve(type(uint256).max);
        }

        _swapSideToBase(type(uint256).max);
        _withdrawBaseFromAAve(type(uint256).max);
        isExit = true;
    }

    function stopExit() public onlyOwner nonReentrant {
        require(isExit, "isExit==false");
        isExit = false;
        uint256 navExpected = (netAssetValue() * (10000 - balanceSlippageBP)) /
            10000;
        _balance(0, 1e18);
        require(netAssetValue() >= navExpected, "nav less than expected");
    }

    //PUBLIC

    function getCurrentDebtRatio() public view returns (int256) {
        (, uint256 sideBalance) = pairBalances();
        uint256 sideUsd = sideToUsd(
            sideBalance + sideToken.balanceOf(address(this))
        );
        (, uint256 aaveBorrowUsd) = getBorrowAndCollateral();

        return int256(sideUsd == 0 ? 1e18 : ((aaveBorrowUsd * 1e18) / sideUsd));
    }

    function netAssetValue() public view returns (uint256 assetValue) {
        (
            uint256 aaveCollateralUsd,
            uint256 aaveBorrowUsd
        ) = getBorrowAndCollateral();
        (uint256 baseBalance, uint256 sideBalance) = pairBalances();
        assetValue =
            baseToken.balanceOf(address(this)) +
            baseBalance +
            usdToBase(
                aaveCollateralUsd -
                    aaveBorrowUsd +
                    sideToUsd(sideToken.balanceOf(address(this)) + sideBalance)
            );
    }

    function pegStatus()
        public
        view
        returns (uint256 assetValue, uint256 lzdSupply)
    {
        assetValue = netAssetValue();
        lzdSupply = lizardSynteticToken.totalSupply();
    }

    function deposit(uint256 _amountBase) public nonReentrant {
        require(
            tx.origin == msg.sender || whitelist[msg.sender],
            "only no smart contract or whitelist"
        );
        require(_amountBase > 0, "amount must be > 0");

        require(
            lizardSynteticToken.totalSupply() + _amountBase < maximumMint,
            "maximum lizardSyntetic minted"
        );

        uint256 navExpected = ((netAssetValue() + _amountBase) *
            (10000 - depositWithdrawSlippageBP)) / 10000;

        baseToken.safeTransferFrom(msg.sender, address(this), _amountBase);

        lizardSynteticToken.mint(
            msg.sender,
            applyFees(_amountBase, mintFeesNumerator, mintFeesDenominator)
        );

        // _balance(toInt256(baseToUsd(_amountBase)), 0);
        _balance(0, 0);

        require(netAssetValue() >= navExpected, "nav less than expected");
        emit Deposit(_amountBase);
    }

    function withdraw(uint256 _amountBase) public nonReentrant {
        require(
            tx.origin == msg.sender || whitelist[msg.sender],
            "only no smart contract or whitelist"
        );
        require(_amountBase > 0, "amount must be greater than 0");

        (uint256 assetValue, uint256 lzdSupply) = pegStatus();

        uint256 wantedBaseAmount = applyFees(
            _amountBase,
            redeemFeesNumerator,
            redeemFeesDenominator
        );

        if (assetValue < lzdSupply) //not enough  to redeem with 1/1 ratio
        {
            wantedBaseAmount = (wantedBaseAmount * (assetValue)) / lzdSupply;
        }
        require(wantedBaseAmount <= assetValue && wantedBaseAmount > 0);
        uint256 navExpected = ((netAssetValue() - _amountBase) *
            (10000 - depositWithdrawSlippageBP)) / 10000;

        _balance(-(toInt256(baseToUsd(wantedBaseAmount)) * 10001) / 10000, 0);

        uint256 realBaseAmount = Math.min(
            wantedBaseAmount,
            baseToken.balanceOf(address(this))
        );
        lizardSynteticToken.burn(
            msg.sender,
            (_amountBase * realBaseAmount) / wantedBaseAmount
        ); // burn after read totalSupply

        baseToken.safeTransfer(msg.sender, realBaseAmount);

        require(netAssetValue() >= navExpected, "nav less than expected");

        emit Withdraw(_amountBase);
    }

    function baseToUsd(uint256 amount) public view returns (uint256) {
        (
            uint80 roundID,
            int256 price,
            ,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = baseOracle.latestRoundData();
        require(answeredInRound >= roundID, "Old data");
        require(timeStamp > 0, "Round not complete");
        return (amount * uint256(price)) / baseDecimals;
    }

    function usdToBase(uint256 amount) public view returns (uint256) {
        (
            uint80 roundID,
            int256 price,
            ,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = baseOracle.latestRoundData();
        require(answeredInRound >= roundID, "Old data");
        require(timeStamp > 0, "Round not complete");
        return (amount * baseDecimals) / uint256(price);
    }

    function sideToUsd(uint256 amount) public view returns (uint256) {
        (
            uint80 roundID,
            int256 price,
            ,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = sideOracle.latestRoundData();
        require(answeredInRound >= roundID, "Old data");
        require(timeStamp > 0, "Round not complete");
        return (amount * uint256(price)) / sideDecimals;
    }

    function usdToSide(uint256 amount) public view returns (uint256) {
        (
            uint80 roundID,
            int256 price,
            ,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = sideOracle.latestRoundData();
        require(answeredInRound >= roundID, "Old data");
        require(timeStamp > 0, "Round not complete");
        return (amount * sideDecimals) / uint256(price);
    }

    function pairBalances()
        public
        view
        returns (uint256 baseBalance, uint256 sideBalance)
    {
        return _localPairBalances();
    }

    function getBorrowAndCollateral()
        public
        view
        returns (uint256 aaveCollateralUsd, uint256 aaveBorrowUsd)
    {
        IAavePool aavePool = IAavePool(aavePoolAddressesProvider.getPool());
        (aaveCollateralUsd, aaveBorrowUsd, , , , ) = aavePool
            .getUserAccountData(address(this));
    }

    function isSamePrices() public view returns (bool) {
        uint256 poolPrice = _localPairGetAmountOut(
            sideDecimals,
            address(sideToken)
        );
        uint256 oraclePrice = usdToBase(sideToUsd(sideDecimals));
        uint256 deltaPrice;
        if (poolPrice > oraclePrice) {
            deltaPrice = poolPrice - oraclePrice;
        } else {
            deltaPrice = oraclePrice - poolPrice;
        }

        return ((deltaPrice * 10000) <= allowedStakeSlippageBP * oraclePrice);
    }

    function getCurrentHealthFactor()
        public
        view
        returns (uint256 _currentHealthFactor)
    {
        IAavePool aavePool = IAavePool(aavePoolAddressesProvider.getPool());
        (, , , , , _currentHealthFactor) = aavePool.getUserAccountData(
            address(this)
        );
    }

    function k1(bool reBalance) public view returns (int256) {
        uint256 healthFactor;
        if (reBalance) {
            healthFactor = neededHealthFactor;
        } else {
            healthFactor = getCurrentHealthFactor();
            if (healthFactor == type(uint256).max) {
                healthFactor = neededHealthFactor;
            }
        }
        return int256((1e18 * healthFactor) / liquidationThreshold);
    }

    function k2() public view returns (int256) {
        (uint256 baseReserve, uint256 sideReserve) = _localPairGetReserves();
        return int256((baseToUsd(baseReserve) * 1e18) / sideToUsd(sideReserve));
    }

    function k3(uint256 balanceRatio) public view returns (int256) {
        int256 debtRatio = getCurrentDebtRatio();
        return
            debtRatio +
            int256(balanceRatio) -
            (debtRatio * int256(balanceRatio)) /
            1e18;
    }

    // INTERNAL

    function _executeAction(Action memory action) internal {
        if (action.actionType == ActionType.ADD_LIQUIDITY) {
            _addLiquidity(action.amount);
        } else if (action.actionType == ActionType.REMOVE_LIQUIDITY) {
            _removeLiquidity(action.amount);
        } else if (action.actionType == ActionType.SUPPLY_BASE_TOKEN) {
            _supplyToAAve(action.amount);
        } else if (action.actionType == ActionType.WITHDRAW_BASE_TOKEN) {
            _withdrawBaseFromAAve(usdToBase(action.amount));
        } else if (action.actionType == ActionType.BORROW_SIDE_TOKEN) {
            _borrowSideFromAAve(action.amount);
        } else if (action.actionType == ActionType.REPAY_SIDE_TOKEN) {
            _repaySideToAAve(action.amount);
        } else if (action.actionType == ActionType.SWAP_SIDE_TO_BASE) {
            _swapSideToBase(action.amount);
        } else if (action.actionType == ActionType.SWAP_BASE_TO_SIDE) {
            _swapBaseToSide(action.amount);
        }
    }

    function _balance(int256 amountUsd, uint256 balanceRatio) internal {
        if (isExit) return;

        (
            uint256 aaveCollateralUsd,
            uint256 aaveBorrowUsd
        ) = getBorrowAndCollateral();

        (, uint256 sidePoolBalance) = pairBalances();

        Action[] memory actions = IMathBalance(mathBalance).balance(
            BalanceMathInput(
                k1(balanceRatio > 0),
                k2(),
                k3(balanceRatio),
                amountUsd,
                toInt256(aaveCollateralUsd),
                toInt256(aaveBorrowUsd),
                toInt256(sideToUsd(sidePoolBalance)),
                toInt256(baseToUsd(baseToken.balanceOf(address(this)))),
                toInt256(sideToUsd(sideToken.balanceOf(address(this)))),
                toInt256(allowedSlippageBP)
            )
        );
        for (uint j; j < actions.length; j++) {
            _executeAction(actions[j]);
        }
    }

    function _giveAllowances() internal {
        // uniSwapRouter
        sideToken.approve(address(uniswapRouter), type(uint256).max);
        baseToken.approve(address(uniswapRouter), type(uint256).max);

        _localGiveAllowances();
    }

    // ADD & REMOVE LP
    function _addLiquidity(uint256 usdAmountToKeep) internal {
        if (
            baseToken.balanceOf(address(this)) == 0 ||
            sideToken.balanceOf(address(this)) == 0
        ) {
            return;
        }

        if (!isSamePrices()) return;

        uint256 baseBalance = baseToken.balanceOf(address(this));
        uint256 sideBalance = sideToken.balanceOf(address(this));
        if (usdAmountToKeep < type(uint256).max) {
            uint256 baseAmountToKeep = usdToBase(usdAmountToKeep);
            if (baseAmountToKeep > baseBalance) return;
            baseBalance = baseBalance - baseAmountToKeep;
        }

        if (baseToUsd(baseBalance) <= 100 || sideToUsd(sideBalance) <= 100) {
            return;
        }
        emit AddLiquidity(_localAddLiquidity(baseBalance, sideBalance));
        // add liquidity
    }

    function _removeLiquidity(uint256 usdAmountSide) internal {
        if (usdAmountSide == 0) return;
        if (!isSamePrices()) return;

        emit RemoveLiquidity(
            _localRemoveLiquidity(
                usdAmountSide < type(uint256).max
                    ? usdToSide(usdAmountSide)
                    : type(uint256).max
            )
        );
    }

    function _swapSideToBase(uint256 usdAmount) internal {
        if (usdAmount == 0) return;
        uint256 swapSideAmount;
        if (usdAmount == type(uint256).max) {
            swapSideAmount = sideToken.balanceOf(address(this));
        } else {
            swapSideAmount = Math.min(
                usdToSide(usdAmount),
                sideToken.balanceOf(address(this))
            );
        }

        if (swapSideAmount <= 100) {
            return;
        }

        uint256 amountOutMin = usdToBase(
            sideToUsd((swapSideAmount * (10000 - allowedSlippageBP)) / 10000)
        );

        if (amountOutMin <= 100) {
            return;
        }

        uint256 amountOut;
        {
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
                .ExactInputSingleParams({
                    tokenIn: address(sideToken),
                    tokenOut: address(baseToken),
                    fee: uniswapPoolFee,
                    recipient: address(this),
                    amountIn: swapSideAmount,
                    amountOutMinimum: amountOutMin,
                    sqrtPriceLimitX96: 0
                });

            amountOut = uniswapRouter.exactInputSingle(params);
        }

        emit SwapSideToBase(swapSideAmount, amountOut);
    }

    function _swapBaseToSide(uint256 usdAmount) internal {
        if (usdAmount == 0) return;
        uint256 swapBaseAmount;
        if (usdAmount == type(uint256).max) {
            swapBaseAmount = baseToken.balanceOf(address(this));
        } else {
            swapBaseAmount = Math.min(
                usdToBase(usdAmount),
                baseToken.balanceOf(address(this))
            );
        }

        if (swapBaseAmount <= 100) {
            return;
        }

        uint256 amountOutMin = usdToSide(
            baseToUsd((swapBaseAmount * (10000 - allowedSlippageBP)) / 10000)
        );

        if (amountOutMin <= 100) {
            return;
        }

        uint256 amountOut;
        {
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
                .ExactInputSingleParams({
                    tokenIn: address(baseToken),
                    tokenOut: address(sideToken),
                    fee: uniswapPoolFee,
                    recipient: address(this),
                    amountIn: swapBaseAmount,
                    amountOutMinimum: amountOutMin,
                    sqrtPriceLimitX96: 0
                });

            amountOut = uniswapRouter.exactInputSingle(params);
        }

        emit SwapBaseToSide(swapBaseAmount, amountOut);
    }

    function _supplyToAAve(uint256 usdAmount) internal {
        if (usdAmount == 0) return;
        uint256 supplyBaseAmount;
        if (usdAmount == type(uint256).max) {
            supplyBaseAmount = baseToken.balanceOf(address(this));
        } else {
            supplyBaseAmount = Math.min(
                usdToBase(usdAmount),
                baseToken.balanceOf(address(this))
            );
        }
        if (supplyBaseAmount == 0) {
            return;
        }

        IAavePool aavePool = IAavePool(aavePoolAddressesProvider.getPool());
        baseToken.approve(address(aavePool), supplyBaseAmount);
        aavePool.supply(address(baseToken), supplyBaseAmount, address(this), 0);
        emit SupplyBaseToAAve(supplyBaseAmount);
    }

    function _withdrawBaseFromAAve(uint256 baseAmount) internal {
        if (baseAmount == 0) return;
        IAavePool aavePool = IAavePool(aavePoolAddressesProvider.getPool());
        aavePool.withdraw(address(baseToken), baseAmount, address(this));
        emit WithdrawBaseFromAAve(baseAmount);
    }

    function _borrowSideFromAAve(uint256 usdAmount) internal {
        if (usdAmount == 0) return;
        uint256 borrowSideAmount = usdToSide(usdAmount);
        IAavePool aavePool = IAavePool(aavePoolAddressesProvider.getPool());
        aavePool.borrow(
            address(sideToken),
            borrowSideAmount,
            aaveInterestRateMode,
            0,
            address(this)
        );
        emit BorrowSideFromAAve(borrowSideAmount);
    }

    // repay side token to aave
    function _repaySideToAAve(uint256 usdAmount) internal {
        if (usdAmount == 0) return;

        uint256 repaySideAmount;
        if (usdAmount == type(uint256).max) {
            repaySideAmount = sideToken.balanceOf(address(this));
        } else {
            repaySideAmount = Math.min(
                usdToSide(usdAmount),
                sideToken.balanceOf(address(this))
            );
        }

        if (repaySideAmount == 0) {
            return;
        }

        IAavePool aavePool = IAavePool(aavePoolAddressesProvider.getPool());

        sideToken.approve(address(aavePool), repaySideAmount);

        aavePool.repay(
            address(sideToken),
            repaySideAmount,
            aaveInterestRateMode,
            address(this)
        );
        emit RepaySideToAAve(repaySideAmount);
    }

    function _claimRewards() internal returns (uint256) {
        uint256 amount = _localClaimRewards();
        emit ClaimReward(amount);
        return amount;
    }

    function _localClaimRewards() internal virtual returns (uint256) {
        revert("Not implemented");
    }

    function _localGiveAllowances() internal virtual {
        revert("Not implemented");
    }

    function _localRemoveLiquidity(
        uint256 usdAmountSide
    ) internal virtual returns (uint256) {
        revert("Not implemented");
    }

    function _localAddLiquidity(
        uint256 baseAmountMax,
        uint256 sideAmountMax
    ) internal virtual returns (uint256) {
        revert("Not implemented");
    }

    function _localInitialize() internal virtual {
        revert("Not implemented");
    }

    function _localPairBalances()
        internal
        view
        virtual
        returns (uint256 baseBalance, uint256 sideBalance)
    {
        revert("Not implemented");
    }

    function _localPairGetReserves()
        internal
        view
        virtual
        returns (uint256 baseReserve, uint256 sideReserve)
    {
        revert("Not implemented");
    }

    function _localPairGetAmountOut(
        uint256 amount,
        address inToken
    ) internal view virtual returns (uint256) {
        revert("Not implemented");
    }
}

