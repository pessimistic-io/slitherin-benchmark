// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.8.19;

import { IERC20 } from "./ERC20_IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { AccessControl } from "./AccessControl.sol";
import { Pausable } from "./Pausable.sol";

import { ICErc20, ICToken } from "./ICErc20.sol";
import { IComptroller } from "./IComptroller.sol";
import { Aggregator } from "./Aggregator.sol";
import { Access } from "./Access.sol";

/**
 * @dev This strategy will deposit and leverage a token on compoundV2(fork) to maximize yield by farming reward tokens
 */
contract CapstackLoopingStrategyComp is Aggregator {
    using SafeERC20 for IERC20;

    /**
     * {PERCENT_DIVISOR} - 10000.
     * {COMPOUND_MANTISSA} - The unit used by the Compound protocol
     * {LTV_SAFETY_ZONE} - We will only go up to 98% of max allowed LTV for {targetLTV}
     */
    uint256 public constant PERCENT_DIVISOR = 10_000;
    uint256 public constant COMPOUND_MANTISSA = 1e18;
    uint256 public constant LTV_SAFETY_ZONE = 0.98 * 1e18;

    /**
     * @dev Third Party Contracts:
     * {want} - The vault token the strategy is maximizing
     * {cWant} - The Share of the want token market
     * {comptroller} - Contract to enter markets and to claim reward tokens
     * {rewards} - reward token array, Used to swap to want
     */
    address public want;
    ICErc20 public cWant;
    address public comptroller;
    address[] public rewards;

    /**
     * @dev Strategy variables
     * {targetLTV} - The target loan to value for the strategy where 1 ether = 100%
     * {allowedLTVDrift} - How much the strategy can deviate from the target ltv where 0.01 ether = 1%
     * {balanceOfPool} - The total balance deposited into Pool (supplied - borrowed)
     * {borrowDepth} - The maximum amount of loops used to leverage and deleverage
     * {minWantToLeverage} - The minimum amount of want to leverage in a loop
     * {ltvScaleOfSafeCollateralFactor} - Scale value of ltv for deleveraging check(function: shouldDeleverage). 1 PERCENT_DIVISOR == 100%
     * {principalScaleOfSafeLiquidity} - Scale value of principal ( the principal: balanceOf() ) for deleveraging check( liquidity > principal * principalScaleOfSafeLiquidity / PERCENT_DIVISOR). 1 PERCENT_DIVISOR == 100%
     * {principalScaleOfSafeSupply} - Scale value of principal ( the principal: balanceOf() ) for deleveraging check( totalSupply > principal * principalScaleOfSafeSupply / PERCENT_DIVISOR). 1 PERCENT_DIVISOR == 100%     */
    uint256 public targetLTV;
    uint256 public allowedLTVDrift = 0.01 * 1e18;
    uint256 public balanceOfPool;
    uint256 public borrowDepth = 12;
    uint256 public minWantToLeverage = 100;
    uint256 public maxBorrowDepth = 15;
    uint256 public ltvScaleOfSafeCollateralFactor = PERCENT_DIVISOR;
    uint256 public principalScaleOfSafeLiquidity = 2 * 10_000;
    uint256 public principalScaleOfSafeSupply = 5 * 10_000;

    event Deposit(address indexed user, uint256 amount);
    event Withdrawal(address indexed user, uint256 amount);
    event Harvest(
        address indexed caller,
        uint256 wantAmount,
        uint256 supply,
        uint256 borrow,
        uint256 newSupply,
        uint256 newBorrow,
        uint256 timestamp
    );
    event Claim(address indexed caller, uint256 rewardAmount);
    event SwapToken(address indexed caller, address indexed token, uint256 amount);
    event CurrentLtvChanged(address indexed caller, uint256 oldLtv, uint256 currentLtv);
    event TargetLtvChanged(address indexed caller, uint256 newLtv);
    event DriftChanged(address indexed caller, uint256 newDrift);
    event BorrowDepthChanged(address indexed caller, uint256 newBorrowDepth);
    event MinWantChanged(address indexed caller, uint256 newMinWant);
    event RewardChanged(address indexed caller, address[] newRewards);
    event LtvScaleOfSafeCollateralFactorChanged(address indexed caller, uint256 newScale);
    event PrincipalScaleOfSafeLiquidityChanged(address indexed caller, uint256 newScale);
    event PrincipalScaleOfSafeSupplyChanged(address indexed caller, uint256 newScale);
    event BorrowRateOffsetChanged(address indexed caller, int256 newOffset);

    /**
     * @dev Initializes the strategy. Sets parameters, saves routes, and gives allowances.
     */
    constructor(
        address _admin,
        address[] memory _guardians,
        address[] memory _keepers,
        address[] memory _rewards,
        address _cWant,
        uint256 _targetLTV
    ) Access(_admin) {
        uint256 length = _guardians.length;
        for (uint256 i = 0; i < length; ++i) {
            _grantRole(GUARDIAN_ROLE, _guardians[i]);
            _grantRole(KEEPER_ROLE, _guardians[i]);
        }
        length = _keepers.length;
        for (uint256 i = 0; i < length; ++i) {
            _grantRole(KEEPER_ROLE, _keepers[i]);
        }

        cWant = ICErc20(_cWant);
        comptroller = cWant.comptroller();
        want = cWant.underlying();
        targetLTV = _targetLTV;
        rewards = _rewards;
        // Enter markets and Approve token
        address[] memory markets = new address[](1);
        markets[0] = _cWant;
        IComptroller(comptroller).enterMarkets(markets);
        length = _rewards.length;
        for (uint256 i = 0; i < length; ++i) {
            _approveToken(_rewards[i], oneInchRouter, type(uint256).max);
        }
        IERC20(want).safeIncreaseAllowance(address(cWant), type(uint256).max);
    }

    /**
     * @dev Helper modifier for functions that need to update the internal balance at the end of their execution.
     */
    modifier doUpdateBalance() {
        _;
        updateBalance();
    }

    /**
     * @dev A helper function to call deposit() with all the sender's funds.
     */
    function depositAll() external {
        deposit(IERC20(want).balanceOf(msg.sender));
    }

    function deposit(uint256 _amount) public onlyRole(GUARDIAN_ROLE) whenNotPaused {
        require(_amount != 0, "please provide amount");
        IERC20(want).safeTransferFrom(msg.sender, address(this), _amount);
        _deposit();
        emit Deposit(msg.sender, _amount);
    }

    /**
     * @dev Withdraws all funds and sents them back to the admin.
     */
    function withdrawAll() external onlyRole(ADMIN_ROLE) doUpdateBalance {
        updateBalance();
        uint256 cWantBalance = balanceOfcWant();
        if (cWantBalance > 1 && balanceOfPool > minWantToLeverage) {
            _deleverage(type(uint256).max);
            _withdrawUnderlying(balanceOfPool);
        }
        uint256 length = rewards.length;
        for (uint256 i = 0; i < length; ++i) {
            address _reward = rewards[0];
            uint256 bal = IERC20(_reward).balanceOf(address(this));
            IERC20(_reward).safeTransfer(msg.sender, bal);
        }

        uint256 wantBalance = balanceOfWant();
        if (wantBalance == 0) {
            return;
        }
        IERC20(want).safeTransfer(msg.sender, wantBalance);
        emit Withdrawal(msg.sender, wantBalance);
    }

    /**
     * @dev Withdraws funds and sents them back to the admin.
     * It withdraws {want} from Pool
     */
    function withdraw(uint256 _withdrawAmount) external onlyRole(ADMIN_ROLE) {
        require(balanceOf() > 0, "no want assets");
        uint256 wantBalance = balanceOfWant();
        if (_withdrawAmount <= wantBalance) {
            IERC20(want).safeTransfer(msg.sender, _withdrawAmount);
            emit Withdrawal(msg.sender, _withdrawAmount);
            return;
        }
        uint256 finalWithdrawAmount = _withdrawFromPool(_withdrawAmount);
        emit Withdrawal(msg.sender, finalWithdrawAmount);
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     * @notice Assumes the deposit will take care of the TVL rebalancing.
     * 1. Call claim() function at first
     * 2. Swaps rewards for {want}
     * 3. Deposits.
     */
    function harvest(
        OneInchData[] calldata _data
    ) external onlyRole(KEEPER_ROLE) whenNotPaused returns (uint256 wantAmount) {
        (uint256 oldSupply, uint256 oldBorrow) = _getSupplyAndBorrow();
        uint256 initWantBal = balanceOfWant();
        uint256 length = _data.length;
        for (uint256 i = 0; i < length; ++i) {
            OneInchData calldata swapData = _data[i];
            uint256 tokenBal = IERC20(swapData.token).balanceOf(address(this));
            if (tokenBal > 0) {
                _1inchSwap(swapData.data);
                emit SwapToken(msg.sender, swapData.token, tokenBal);
            }
        }
        uint256 newWantBal = balanceOfWant();
        wantAmount = newWantBal - initWantBal;

        _deposit();
        (uint256 newSupply, uint256 newBorrow) = _getSupplyAndBorrow();
        emit Harvest(msg.sender, wantAmount, oldSupply, oldBorrow, newSupply, newBorrow, block.timestamp);
    }

    /**
     * @dev Claim rewards without swapping
     */
    function claim() external onlyRole(KEEPER_ROLE) returns (uint256 rewardWantAmount) {
        rewardWantAmount = _claimRewards();
        emit Claim(msg.sender, rewardWantAmount);
    }

    /**
     * @dev Levers the strategy up to the targetLTV
     */
    function leverMax() external onlyRole(GUARDIAN_ROLE) doUpdateBalance {
        _leverMax();
    }

    /**
     * @dev For a given withdraw amount, delever to zero
     */
    function leverDownToZero() external {
        leverDown(type(uint256).max);
        targetLTV = 0;
        emit TargetLtvChanged(msg.sender, 0);
    }

    /**
     * @dev For a given withdraw amount, delever to a borrow level
     */
    function leverDown(uint256 _withdrawAmount) public onlyRole(GUARDIAN_ROLE) doUpdateBalance {
        _deleverage(_withdrawAmount);
        uint256 newLtv = _calculateLTV();
        targetLTV = newLtv;
        emit TargetLtvChanged(msg.sender, newLtv);
    }

    /**
     * @dev Withdraw ERC20 token to admin
     */
    function withdrawTokens(IERC20 token) external onlyRole(ADMIN_ROLE) {
        uint256 balance = token.balanceOf(address(this));
        token.transfer(msg.sender, balance);
    }

    /**
     * @dev Emergency function to deleverage in case regular deleveraging breaks
     */
    function manualDeleverage(uint256 amount) external onlyRole(GUARDIAN_ROLE) doUpdateBalance {
        _redeem(amount);
        _repay(amount);
    }

    /**
     * @dev Emergency function to deleverage in case regular deleveraging breaks
     */
    function manualReleaseWant(uint256 amount) external onlyRole(ADMIN_ROLE) doUpdateBalance {
        _redeem(amount);
    }

    /**
     * @dev Withdraws all funds leaving rewards behind.
     *      Guardian and roles with higher privilege can panic.
     */
    function panic() external onlyRole(GUARDIAN_ROLE) doUpdateBalance {
        _deleverage(type(uint256).max);
        _withdrawUnderlying(balanceOfPool);
        _pause();
    }

    /**
     * @dev Pauses the strat. Deposits become disabled but users can still
     *      withdraw. Guardian and roles with higher privilege can pause.
     */
    function pause() external override onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpauses the strat. Opens up deposits again and invokes deposit().
     *      Admin and roles with higher privilege can unpause.
     */
    function unpause() external override onlyRole(ADMIN_ROLE) {
        _unpause();
        _deposit();
    }

    /**
     * @dev Sets a new LTV for leveraging.
     * Should be in units of 1e18
     */
    function setTargetLtv(uint256 _ltv) external onlyRole(GUARDIAN_ROLE) {
        uint256 collateralFactorMantissa = _getCollateralFactor();
        require(collateralFactorMantissa > _ltv + allowedLTVDrift, "targetLtv is too high");
        require(_ltv <= (collateralFactorMantissa * LTV_SAFETY_ZONE) / COMPOUND_MANTISSA, "targetLtv is too high");
        targetLTV = _ltv;
        emit TargetLtvChanged(msg.sender, _ltv);
    }

    /**
     * @dev Sets a new allowed LTV drift
     * Should be in units of 1e18
     */
    function setAllowedLtvDrift(uint256 _drift) external onlyRole(GUARDIAN_ROLE) {
        uint256 collateralFactorMantissa = _getCollateralFactor();
        require(collateralFactorMantissa > targetLTV + _drift, "drift is too large");
        allowedLTVDrift = _drift;
        emit DriftChanged(msg.sender, _drift);
    }

    /**
     * @dev Sets a new borrow depth (how many loops for leveraging+deleveraging)
     */
    function setBorrowDepth(uint8 _borrowDepth) external onlyRole(GUARDIAN_ROLE) {
        require(_borrowDepth <= maxBorrowDepth, "borrowDepth is too large");
        borrowDepth = _borrowDepth;
        emit BorrowDepthChanged(msg.sender, _borrowDepth);
    }

    /**
     * @dev Sets the minimum want to leverage/deleverage (loop) for
     */
    function setMinWantToLeverage(uint256 _minWantToLeverage) external onlyRole(GUARDIAN_ROLE) {
        minWantToLeverage = _minWantToLeverage;
        emit MinWantChanged(msg.sender, _minWantToLeverage);
    }

    /**
     * @dev Sets the ltvScaleOfSafeCollateralFactor for to check whether the scaled ltv is less than collateral factor.
     * 1 PERCENT_DIVISOR == 100%
     */
    function setLtvScaleOfSafeCollateralFactor(uint256 _value) external onlyRole(GUARDIAN_ROLE) {
        ltvScaleOfSafeCollateralFactor = _value;
        emit LtvScaleOfSafeCollateralFactorChanged(msg.sender, _value);
    }

    /**
     * @dev Sets the principalScaleOfSafeSupply for to check whether the pool totalSupply is sufficient.
     * 1 PERCENT_DIVISOR == 100%
     */
    function setPrincipalScaleOfSafeSupply(uint256 _value) external onlyRole(GUARDIAN_ROLE) {
        principalScaleOfSafeSupply = _value;
        emit PrincipalScaleOfSafeLiquidityChanged(msg.sender, _value);
    }

    /**
     * @dev Sets the principalScaleOfSafeLiquidity for to check whether the liquidity is sufficient.
     * 1 PERCENT_DIVISOR == 100%
     */
    function setPrincipalScaleOfSafeLiquidity(uint256 _value) external onlyRole(GUARDIAN_ROLE) {
        principalScaleOfSafeLiquidity = _value;
        emit PrincipalScaleOfSafeLiquidityChanged(msg.sender, _value);
    }

    function setRewards(address[] calldata _rewards) external onlyRole(GUARDIAN_ROLE) {
        delete rewards;
        rewards = _rewards;
        emit RewardChanged(msg.sender, _rewards);
    }

    /**
     * @dev Check deleveraging condtions, if deleveraging is not required then return 0.
     * return 1: ltv * ltvScaleOfSafeCollateralFactor >= collateral factor
     * return 2: ltv > targetLTV + allowedLTVDrift
     * return 3: liquidity < balanceOf() * principalScaleOfSafeLiquidity ( liquidity: cWant.getCash() - cWant.totalReserves() )
     * return 4: supply < balanceOf() * principalScaleOfSafeSupply ( supply: (cWant.totalSupply() * _getExchangeRateStored()) / COMPOUND_MANTISSA )
     *
     */
    function shouldDeleverage() external view virtual returns (uint256 resultCode) {
        uint256 collateralFactorMantissa = _getCollateralFactor();
        uint256 _ltv = calculateLTV();
        //result code 1: check ltv with collateral factor
        resultCode = (_ltv * ltvScaleOfSafeCollateralFactor) / PERCENT_DIVISOR >= collateralFactorMantissa ? 1 : 0;
        //result code 2: check ltv with target ltv
        if (resultCode == 0) {
            resultCode = _shouldDeleverage(_ltv) ? 2 : 0;
        }

        uint256 liquidity = cWant.getCash() - cWant.totalReserves();
        //result code 3: check liquidity of the principals
        uint256 principals = balanceOf();
        if (resultCode == 0) {
            resultCode = liquidity < (principals * principalScaleOfSafeLiquidity) / PERCENT_DIVISOR ? 3 : 0;
        }
        //result code 4: checks on sufficient supply
        if (resultCode == 0) {
            uint256 totalSupply = (cWant.totalSupply() * _getExchangeRateStored()) / COMPOUND_MANTISSA;
            resultCode = totalSupply < (principals * principalScaleOfSafeSupply) / PERCENT_DIVISOR ? 4 : 0;
        }
    }

    /**
     * @dev Updates the balance. This is the state changing version so it sets
     * balanceOfPool to the latest value.
     */
    function updateBalance() public {
        // balanceOfUnderlying and borrowBalanceCurrent are write functions
        uint256 supplyBalance = cWant.balanceOfUnderlying(address(this));
        uint256 borrowBalance = cWant.borrowBalanceCurrent(address(this));
        balanceOfPool = supplyBalance - borrowBalance;
    }

    /**
     * @dev Calculates the LTV using existing exchange rate,
     * depends on the cWant being updated to be accurate.
     * Does not update in order provide a view function for LTV.
     */
    function calculateLTV() public view returns (uint256 ltv) {
        (, uint256 cWantBalance, uint256 borrowed, uint256 exchangeRate) = cWant.getAccountSnapshot(address(this));

        uint256 supplied = (cWantBalance * exchangeRate) / COMPOUND_MANTISSA;

        if (supplied == 0 || borrowed == 0) {
            return 0;
        }

        ltv = (COMPOUND_MANTISSA * borrowed) / supplied;
    }

    /**
     * @dev Calculates the total amount of {want} held by the strategy
     * which is the balance of want + the total amount supplied to pool.
     */
    function balanceOf() public view returns (uint256) {
        return balanceOfWant() + balanceOfPool;
    }

    /**
     * @dev Calculates the balance of want held directly by the strategy
     */
    function balanceOfWant() public view returns (uint256) {
        return IERC20(want).balanceOf(address(this));
    }

    /**
     * @dev Calculates the balance of want held directly by the strategy
     */
    function balanceOfcWant() public view returns (uint256) {
        return cWant.balanceOf(address(this));
    }

    /**
     * @dev Returns the current position in Pool. Does not accrue interest
     * so might not be accurate, but the cWant is usually updated.
     */
    function getCurrentPosition() public view returns (uint256 supplied, uint256 borrowed) {
        (, uint256 cWantBalance, uint256 borrowBalance, uint256 exchangeRate) = cWant.getAccountSnapshot(address(this));
        borrowed = borrowBalance;

        supplied = (cWantBalance * exchangeRate) / COMPOUND_MANTISSA;
    }

    function getRewards() public view returns (address[] memory) {
        return rewards;
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone supplied in the strategy's vault contract.
     * It supplies want to farm rewrd
     */
    function _deposit() internal doUpdateBalance {
        uint256 wantBalance = balanceOfWant();
        if (wantBalance > 0) {
            _supply(wantBalance);
        }
        uint256 _ltv = _calculateLTV();

        if (_shouldLeverage(_ltv)) {
            _leverMax();
        } else if (_shouldDeleverage(_ltv)) {
            _deleverage(0);
        }
    }

    /**
     * @dev Withdraws funds and sents them back to the user.
     * It withdraws {want} from Pool
     */
    function _withdrawFromPool(uint256 _withdrawAmount) internal doUpdateBalance returns (uint256 finalWithdrawAmount) {
        (uint256 supplied, uint256 borrowed) = _getSupplyAndBorrow();
        uint256 _ltv = _calculateLTVAfterWithdraw(_withdrawAmount, supplied, borrowed);
        uint256 realSupply = supplied - borrowed;
        if (_withdrawAmount > realSupply) {
            _withdrawAmount = realSupply;
        }
        if (_shouldLeverage(_ltv)) {
            // Strategy is underleveraged so can withdraw underlying directly
            finalWithdrawAmount = _withdrawUnderlyingToUser(_withdrawAmount);
            _leverMax();
        } else if (_shouldDeleverage(_ltv)) {
            _deleverage(_withdrawAmount);
            // Strategy has deleveraged to the point where it can withdraw underlying
            finalWithdrawAmount = _withdrawUnderlyingToUser(_withdrawAmount);
        } else {
            // LTV is in the acceptable range so the underlying can be withdrawn directly
            finalWithdrawAmount = _withdrawUnderlyingToUser(_withdrawAmount);
        }
    }

    /**
     * @dev Withdraws want to the user by redeeming the underlying
     */
    function _withdrawUnderlyingToUser(uint256 _withdrawAmount) internal returns (uint256 finalWithdrawAmount) {
        uint256 initWithdrawAmount = _withdrawAmount;
        _withdrawUnderlying(_withdrawAmount);
        uint256 bal = balanceOfWant();
        finalWithdrawAmount = bal < initWithdrawAmount ? bal : initWithdrawAmount;
        IERC20(want).safeTransfer(msg.sender, finalWithdrawAmount);
    }

    /**
     * @dev Levers the strategy up to the targetLTV
     */
    function _leverMax() internal {
        (uint256 supplied, uint256 borrowed) = _getSupplyAndBorrow();
        uint oldLtv = _calculateLTV();
        uint256 realSupply = supplied - borrowed;
        uint256 newBorrow = _getMaxBorrowFromSupplied(realSupply, targetLTV);
        uint256 totalAmountToBorrow = newBorrow - borrowed;

        for (uint8 i = 0; totalAmountToBorrow > minWantToLeverage && i < borrowDepth; i++) {
            totalAmountToBorrow = totalAmountToBorrow - _leverUpStep(totalAmountToBorrow);
        }
        uint256 currentLtv = _calculateLTV();
        emit CurrentLtvChanged(msg.sender, oldLtv, currentLtv);
    }

    /**
     * @dev Does one step of leveraging
     */
    function _leverUpStep(uint256 _withdrawAmount) internal returns (uint256) {
        (uint256 supplied, uint256 borrowed) = _getSupplyAndBorrow();
        uint256 collateralFactorMantissa = _getCollateralFactor();
        uint256 canBorrow = (supplied * collateralFactorMantissa) / COMPOUND_MANTISSA;

        canBorrow -= borrowed;

        if (canBorrow < _withdrawAmount) {
            _withdrawAmount = canBorrow;
        }
        uint minWant = minWantToLeverage;
        if (_withdrawAmount > minWant) {
            // borrow available amount
            _withdrawAmount -= minWant;
            _borrow(_withdrawAmount);

            // deposit available want as collateral
            uint256 wantBalance = balanceOfWant();
            // IERC20(want).safeIncreaseAllowance(address(cWant), wantBalance);
            _supply(wantBalance);
        }

        return _withdrawAmount;
    }

    /**
     * @dev Returns if the strategy should leverage with the given ltv level
     */
    function _shouldLeverage(uint256 _ltv) internal view returns (bool) {
        if (targetLTV >= allowedLTVDrift && _ltv < targetLTV - allowedLTVDrift) {
            return true;
        }
        return false;
    }

    /**
     * @dev Returns if the strategy should deleverage with the given ltv level
     */
    function _shouldDeleverage(uint256 _ltv) internal view returns (bool) {
        if (_ltv > targetLTV + allowedLTVDrift) {
            return true;
        }
        return false;
    }

    /**
     * @dev This is the state changing calculation of LTV that is more accurate
     * to be used internally.
     */
    function _calculateLTV() internal returns (uint256 ltv) {
        (uint256 supplied, uint256 borrowed) = _getSupplyAndBorrow();
        if (supplied == 0 || borrowed == 0) {
            return 0;
        }
        ltv = (COMPOUND_MANTISSA * borrowed) / supplied;
    }

    /**
     * @dev Withdraws want to the strat by redeeming the underlying
     */
    function _withdrawUnderlying(uint256 _withdrawAmount) internal {
        (uint256 supplied, uint256 borrowed) = _getSupplyAndBorrow();
        uint256 realSupplied = supplied - borrowed;

        if (realSupplied == 0) {
            return;
        }

        if (_withdrawAmount > realSupplied) {
            _withdrawAmount = realSupplied;
        }

        uint256 tempColla = targetLTV + allowedLTVDrift;
        if (tempColla == 0) {
            tempColla = 1e15; // 0.001 * 1e18. lower we have issues
        }

        uint256 reservedAmount = 0;
        reservedAmount = (borrowed * COMPOUND_MANTISSA) / tempColla;
        if (supplied >= reservedAmount) {
            uint256 redeemable = supplied - reservedAmount;
            uint256 balance = balanceOfcWant();
            if (balance > 1) {
                if (redeemable < _withdrawAmount) {
                    _withdrawAmount = redeemable;
                }
            }
        }
        _redeem(_withdrawAmount);
    }

    /**
     * @dev For a given withdraw amount, figures out the new borrow with the current supply
     * that will maintain the target LTV
     */
    function _getDesiredBorrow(uint256 _withdrawAmount) internal returns (uint256 position) {
        //we want to use statechanging for safety
        (uint256 supplied, uint256 borrowed) = _getSupplyAndBorrow();

        //When we unwind we end up with the difference between borrow and supply
        uint256 unwoundSupplied = supplied - borrowed;

        //we want to see how close to collateral target we are.
        //So we take our unwound supplied and add or remove the _withdrawAmount we are are adding/removing.
        //This gives us our desired future undwoundDeposit (desired supply)

        uint256 desiredSupply = 0;
        if (_withdrawAmount > unwoundSupplied) {
            _withdrawAmount = unwoundSupplied;
        }
        desiredSupply = unwoundSupplied - _withdrawAmount;

        //(ds *c)/(1-c)
        uint256 num = desiredSupply * targetLTV;
        uint256 den = COMPOUND_MANTISSA - targetLTV;

        uint256 desiredBorrow = num / den;
        if (desiredBorrow > 1e5) {
            //stop us going right up to the wire
            desiredBorrow = desiredBorrow - 1e5;
        }

        position = borrowed - desiredBorrow;
    }

    /**
     * @dev For a given withdraw amount, delever to a borrow level
     * that will maintain the target LTV
     */
    function _deleverage(uint256 _withdrawAmount) internal {
        uint256 oldLtv = _calculateLTV();

        uint256 totalRepayAmount = _getDesiredBorrow(_withdrawAmount);

        //If there is no deficit we dont need to adjust position
        //if the position change is tiny do nothing
        if (totalRepayAmount > minWantToLeverage) {
            for (uint256 i = 0; totalRepayAmount > minWantToLeverage && i < borrowDepth; i++) {
                totalRepayAmount = totalRepayAmount - _leverDownStep(totalRepayAmount);
            }
        }
        uint256 currentLtv = _calculateLTV();
        emit CurrentLtvChanged(msg.sender, oldLtv, currentLtv);
    }

    /**
     * @dev Deleverages one step
     */
    function _leverDownStep(uint256 maxDeleverage) internal returns (uint256 deleveragedAmount) {
        (uint256 supplied, uint256 borrowed) = _getSupplyAndBorrow();
        uint256 collateralFactorMantissa = _getCollateralFactor();

        deleveragedAmount = _calcMaxAllowedDeleverageAmount(supplied, borrowed, collateralFactorMantissa);

        if (deleveragedAmount >= borrowed) {
            deleveragedAmount = borrowed;
        }
        if (deleveragedAmount >= maxDeleverage) {
            deleveragedAmount = maxDeleverage;
        }
        uint256 exchangeRateStored = _getExchangeRateStored();
        //redeemTokens = redeemAmountIn * 1e18 / exchangeRate. must be more than 0
        //a rounding error means we need another small addition
        uint minWant = minWantToLeverage;
        if (deleveragedAmount * COMPOUND_MANTISSA >= exchangeRateStored && deleveragedAmount > minWant) {
            deleveragedAmount -= minWant; // Amount can be slightly off for tokens with less decimals (USDC), so redeem a bit less
            _redeem(deleveragedAmount);
            //our borrow has been increased by no more than maxDeleverage
            _repay(deleveragedAmount);
        }
    }

    /**
     * @dev Gets the maximum amount allowed to be borrowed for a given collateral factor and amount supplied
     */
    function _getMaxBorrowFromSupplied(uint256 wantSupplied, uint256 collateralFactor) internal pure returns (uint256) {
        return ((wantSupplied * collateralFactor) / (COMPOUND_MANTISSA - collateralFactor));
    }

    /**
     * @dev Calculates what the LTV will be after withdrawing
     */
    function _calculateLTVAfterWithdraw(
        uint256 _withdrawAmount,
        uint256 supplied,
        uint256 borrowed
    ) internal pure returns (uint256 ltv) {
        uint256 realSupplied = supplied - borrowed;
        if (realSupplied <= _withdrawAmount) {
            return type(uint256).max;
        }
        supplied = supplied - _withdrawAmount;
        ltv = (COMPOUND_MANTISSA * borrowed) / supplied;
    }

    function _calcMaxAllowedDeleverageAmount(
        uint256 supplied,
        uint256 borrowed,
        uint256 collateralFactorMantissa
    ) internal pure returns (uint256) {
        uint256 minAllowedSupply = 0;
        //collat ration should never be 0. if it is something is very wrong... but just incase
        if (collateralFactorMantissa != 0) {
            minAllowedSupply = (borrowed * COMPOUND_MANTISSA) / collateralFactorMantissa;
        }

        return supplied - minAllowedSupply;
    }

    /************************ Override Functions ****************************/

    /**
     * @dev supply want to cWant market.
     */
    function _supply(uint256 amount) internal virtual returns (uint256 err) {
        err = cWant.mint(amount);
        require(err == 0, "Supply failed");
    }

    /**
     * @dev borrow want from cWant market.
     */
    function _borrow(uint256 amount) internal virtual returns (uint256 err) {
        err = cWant.borrow(amount);
        require(err == 0, "Borrow failed");
    }

    /**
     * @dev repay debt to cWant market.
     */
    function _repay(uint256 amount) internal virtual returns (uint256 err) {
        err = cWant.repayBorrow(amount);
        require(err == 0, "Repay failed");
    }

    /**
     * @dev Burn cWant and redeem underlying.
     */
    function _redeem(uint256 amount) internal virtual returns (uint256 err) {
        err = cWant.redeemUnderlying(amount);
        require(err == 0, "Redeem failed");
    }

    /**
     * @dev Returns the accurate current position.
     */
    function _getSupplyAndBorrow() internal virtual returns (uint256 supplied, uint256 borrowed) {
        // balanceOfUnderlying is a write function
        supplied = cWant.balanceOfUnderlying(address(this));
        borrowed = cWant.borrowBalanceStored(address(this));
    }

    /**
     * @dev Returns the collateralFactorMantissa of want.
     */
    function _getCollateralFactor() internal view virtual returns (uint256 collateralFactorMantissa) {
        (, collateralFactorMantissa, ) = IComptroller(comptroller).markets(address(cWant));
    }

    /**
     * @dev Returns the exchangeRateStored of cWant.
     */
    function _getExchangeRateStored() internal view virtual returns (uint256 exchangeRateStoredMantissa) {
        return cWant.exchangeRateStored();
    }

    /**
     * @dev Core harvest function.
     * Get rewards from markets entered
     */
    function _claimRewards() internal virtual returns (uint256 rewardAmount) {
        address reward = rewards[0];
        uint256 initBal = IERC20(reward).balanceOf(address(this));
        ICToken[] memory tokens = new ICToken[](1);
        tokens[0] = cWant;
        IComptroller(comptroller).claimComp(address(this), tokens);
        uint256 newBal = IERC20(reward).balanceOf(address(this));
        rewardAmount = newBal - initBal;
    }
}

