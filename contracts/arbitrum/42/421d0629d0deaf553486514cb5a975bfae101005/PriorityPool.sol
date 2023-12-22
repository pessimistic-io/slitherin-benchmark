// SPDX-License-Identifier: GPL-3.0-or-later

/*
 //======================================================================\\
 //======================================================================\\
  *******         **********     ***********     *****     ***********
  *      *        *              *                 *       *
  *        *      *              *                 *       *
  *         *     *              *                 *       *
  *         *     *              *                 *       *
  *         *     **********     *       *****     *       ***********
  *         *     *              *         *       *                 *
  *         *     *              *         *       *                 *
  *        *      *              *         *       *                 *
  *      *        *              *         *       *                 *
  *******         **********     ***********     *****     ***********
 \\======================================================================//
 \\======================================================================//
*/

pragma solidity ^0.8.13;

import "./PausableWithoutContext.sol";

import "./PriorityPoolDependencies.sol";
import "./PriorityPoolEventError.sol";
import "./PriorityPoolToken.sol";

import "./DateTime.sol";
import "./StringUtils.sol";

/**
 * @title Priority Pool (for single project)
 *
 * @author Eric Lee (ylikp.ust@gmail.com) & Primata (primata@375labs.org)
 *
 * @notice Priority pool is used for protecting a specific project
 *         Each priority pool has a maxCapacity (0 ~ 10,000 <=> 0 ~ 100%) that it can cover
 *         (that ratio represents the part of total assets in Protection Pool)
 *
 *         When liquidity providers join a priority pool,
 *         they need to transfer their RP_LP token to this priority pool.
 *
 *         After that, they can share the 45% percent native token reward of this pool.
 *         At the same time, that also means these liquidity will be first liquidated,
 *         when there is an incident happened for this project.
 *
 *         This reward is distributed in another contract (WeightedFarmingPool)
 *         By default, policy center will help user to deposit into farming pool when staking liquidity
 *
 *         For liquidation process, the pool will first redeem USDC from protectionPool with the staked RP_LP tokens.
 *         - If that is enough, no more redeeming.
 *         - If still need some liquidity to cover, it will directly transfer part of the protectionPool assets to users.
 *
 *         Most of the functions need to be called through Policy Center:
 *             1) When buying new covers: updateWhenBuy
 *             2) When staking liquidity: stakedLiquidity
 *             3) When unstaking liquidity: unstakedLiquidity
 *
 */
contract PriorityPool is
    PriorityPoolEventError,
    PausableWithoutContext,
    PriorityPoolDependencies
{
    using StringUtils for uint256;
    using DateTimeLibrary for uint256;

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Constants **************************************** //
    // ---------------------------------------------------------------------------------------- //

    // Mininum cover amount 10U
    // Avoid accuracy issues
    uint256 internal constant MIN_COVER_AMOUNT = 10e6;

    // Max time length in month
    uint256 internal constant MAX_LENGTH = 3;

    // Min time length in month
    uint256 internal constant MIN_LENGTH = 1;

    address internal immutable owner;

    // Base premium ratio (max 10000) (260 means 2.6% annually)
    uint256 public immutable basePremiumRatio;

    // Pool id set when deployed
    uint256 public immutable poolId;

    // Timestamp of pool creation
    uint256 public immutable startTime;

    // Address of insured token (used for premium payment)
    address public immutable insuredToken;

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Variables **************************************** //
    // ---------------------------------------------------------------------------------------- //

    // Pool name
    string public poolName;

    // Current generation of this priority pool (start from 1)
    // Every time there is a report and liquidation, generation += 1
    uint256 public generation;

    // Max capacity of cover amount to be bought (ratio of total liquidity)
    // 10000 = 100%
    uint256 public maxCapacity;

    // Index for cover amount
    uint256 public coverIndex;

    // Has already passed the base premium ratio period
    bool public passedBasePeriod;

    // Year => Month => Amount of cover ends in that month
    mapping(uint256 => mapping(uint256 => uint256)) public coverInMonth;

    // Generation => lp token address
    mapping(uint256 => address) public lpTokenAddress;

    // Address => Whether is LP address
    mapping(address => bool) public isLPToken;

    // PRI-LP address => Price of lp tokens
    // PRI-LP token amount * Price Index = PRO-LP token amount
    mapping(address => uint256) public priceIndex;

    mapping(uint256 => mapping(uint256 => uint256)) public payoutInMonth;

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Constructor ************************************** //
    // ---------------------------------------------------------------------------------------- //

    constructor(
        uint256 _poolId,
        string memory _name,
        address _protocolToken,
        uint256 _maxCapacity,
        uint256 _baseRatio,
        address _owner,
        address _priorityPoolFactory,
        address _weightedFarmingPool,
        address _protectionPool,
        address _policyCenter,
        address _payoutPool
    ) {
        owner = _owner;

        poolId = _poolId;
        poolName = _name;

        insuredToken = _protocolToken;
        maxCapacity = _maxCapacity;
        startTime = block.timestamp;

        basePremiumRatio = _baseRatio;

        // Generation 1, price starts from 1 (SCALE)
        priceIndex[_deployNewGenerationLP(_weightedFarmingPool)] = SCALE;

        coverIndex = 10000;

        priorityPoolFactory = _priorityPoolFactory;

        weightedFarmingPool = _weightedFarmingPool;
        protectionPool = _protectionPool;
        policyCenter = _policyCenter;
        payoutPool = _payoutPool;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************** Modifiers *************************************** //
    // ---------------------------------------------------------------------------------------- //

    modifier onlyExecutor() {
        if (msg.sender != IPriorityPoolFactory(priorityPoolFactory).executor())
            revert PriorityPool__OnlyExecutor();
        _;
    }

    modifier onlyPolicyCenter() {
        if (msg.sender != policyCenter) revert PriorityPool__OnlyPolicyCenter();
        _;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ View Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Get the current generation PRI-LP token address
     *
     * @return lpAddress Current pri-lp address
     */
    function currentLPAddress() public view returns (address) {
        return lpTokenAddress[generation];
    }

    /**
     * @notice Cost to buy a cover for a given period of time and amount of tokens
     *
     * @param _amount        Amount being covered (usdc)
     * @param _coverDuration Cover length in month
     *
     * @return price  Cover price in usdc
     * @return length Real length in timestamp
     */
    function coverPrice(uint256 _amount, uint256 _coverDuration)
        external
        view
        returns (uint256 price, uint256 length)
    {
        _checkAmount(_amount);

        // Dynamic premium ratio (annually)
        uint256 dynamicRatio = dynamicPremiumRatio(_amount);

        (uint256 endTimestamp, , ) = DateTimeLibrary._getExpiry(
            block.timestamp,
            _coverDuration
        );

        // Length in second
        length = endTimestamp - block.timestamp;

        // Price depends on the real timestamp length
        price = (dynamicRatio * _amount * length) / (SECONDS_PER_YEAR * 10000);
    }

    /**
     * @notice Get current active cover amount
     *         Active cover amount = sum of the nearest 3 months' covers
     *
     * @return covered Total active cover amount
     */
    function activeCovered() public view returns (uint256 covered) {
        (uint256 currentYear, uint256 currentMonth, ) = block
            .timestamp
            .timestampToDate();

        // Only count the latest 3 months
        for (uint256 i; i < 3; ) {
            covered += (coverInMonth[currentYear][currentMonth] -
                payoutInMonth[currentYear][currentMonth]);

            unchecked {
                if (++currentMonth > 12) {
                    ++currentYear;
                    currentMonth = 1;
                }

                ++i;
            }
        }

        covered = (covered * coverIndex) / 10000;
    }

    /**
     * @notice Current minimum asset requirement for Protection Pool
     *         Min requirement * capacity ratio = active covered
     *
     *         Total assets in protection pool should be larger than any of the "minAssetRequirement"
     *         Or the cover index would be cut
     */
    function minAssetRequirement() external view returns (uint256) {
        return (activeCovered() * 10000) / maxCapacity;
    }

    /**
     * @notice Get the dynamic premium ratio (annually)
     *         Depends on the covers sold and liquidity amount in all dynamic priority pools
     *         For the first 7 days, use the base premium ratio
     *
     * @param _coverAmount New cover amount (usdc) being bought
     *
     * @return ratio The dynamic ratio
     */
    function dynamicPremiumRatio(uint256 _coverAmount)
        public
        view
        returns (uint256 ratio)
    {
        // Time passed since this pool started
        uint256 fromStart = block.timestamp - startTime;

        uint256 totalActiveCovered = IProtectionPool(protectionPool)
            .getTotalActiveCovered();

        uint256 stakedProSupply = IProtectionPool(protectionPool)
            .stakedSupply();

        // First 7 days use base ratio
        // Then use dynamic ratio
        // TODO: test use 5 hours
        if (fromStart > DYNAMIC_TIME) {
            // Total dynamic pools
            uint256 numofDynamicPools = IPriorityPoolFactory(
                priorityPoolFactory
            ).dynamicPoolCounter();

            if (
                numofDynamicPools > 0 &&
                totalActiveCovered > 0 &&
                stakedProSupply > 0
            ) {
                // Covered ratio = Covered amount of this pool / Total covered amount
                uint256 coveredRatio = ((activeCovered() + _coverAmount) *
                    SCALE) / (totalActiveCovered + _coverAmount);

                address lp = currentLPAddress();

                //                         PRO-LP token in this pool
                // LP Token ratio =  -------------------------------------------
                //                    PRO-LP token staked in all priority pools
                //
                uint256 tokenRatio = (SimpleERC20(lp).totalSupply() * SCALE) /
                    stakedProSupply;

                // Dynamic premium ratio
                // ( N = total dynamic pools ≤ total pools )
                //
                //                      Covered          1
                //                   --------------- + -----
                //                    TotalCovered       N
                // dynamic ratio =  -------------------------- * base ratio
                //                      LP Amount         1
                //                  ----------------- + -----
                //                   Total LP Amount      N
                //
                ratio =
                    (basePremiumRatio *
                        (coveredRatio * numofDynamicPools + SCALE)) /
                    ((tokenRatio * numofDynamicPools) + SCALE);
            } else ratio = basePremiumRatio;
        } else {
            ratio = basePremiumRatio;
        }
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ Set Functions ************************************* //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Set the max capacity of this priority pool manually
     *         Only owner set this function on a monthly / quaterly base
     *         (For those unpopular pools to decrease, and those popular ones to increase)
     *
     * @param _maxCapacity New max capacity of this pool
     */
    function setMaxCapacity(uint256 _maxCapacity) external {
        require(msg.sender == owner, "Only owner");

        maxCapacity = _maxCapacity;

        bool isUp = _maxCapacity > maxCapacity;

        uint256 diff;
        if (isUp) {
            diff = _maxCapacity - maxCapacity;
        } else {
            diff = maxCapacity - _maxCapacity;
        }

        // Store the max capacity change
        IPriorityPoolFactory(priorityPoolFactory).updateMaxCapacity(isUp, diff);
    }

    /**
     * @notice Set the cover index of this priority pool
     *
     *         Only called from protection pool
     *
     *         When a payout happened in another priority pool,
     *         and this priority pool's minAssetRequirement is less than proteciton pool's asset,
     *         the cover index of this pool will be cut by a ratio
     *
     * @param _newIndex New cover index
     */
    function setCoverIndex(uint256 _newIndex) external {
        require(msg.sender == protectionPool, "Only protection pool");

        emit CoverIndexChanged(coverIndex, _newIndex);
        coverIndex = _newIndex;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ Main Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Provide liquidity to priority pool
     *         Only callable through policyCenter
     *         Can not provide new liquidity when paused
     *
     * @param _amount   Amount of liquidity (PRO-LP token) to provide
     * @param _provider Liquidity provider adress
     */
    function stakedLiquidity(uint256 _amount, address _provider)
        external
        whenNotPaused
        onlyPolicyCenter
        returns (address)
    {
        // Check whether this priority pool should be dynamic
        // If so, update it
        _updateDynamic();

        // Mint current generation lp tokens to the provider
        // PRI-LP amount always 1:1 to PRO-LP
        _mintLP(_provider, _amount);
        emit StakedLiquidity(_amount, _provider);

        return currentLPAddress();
    }

    /**
     * @notice Remove liquidity from priority pool
     *         Only callable through policyCenter
     *
     * @param _lpToken  Address of PRI-LP token
     * @param _amount   Amount of liquidity (PRI-LP) to remove
     * @param _provider Provider address
     */
    function unstakedLiquidity(
        address _lpToken,
        uint256 _amount,
        address _provider
    ) external whenNotPaused onlyPolicyCenter {
        if (!isLPToken[_lpToken]) revert PriorityPool__WrongLPToken();

        // Check whether this priority pool should be dynamic
        // If so, update it
        _updateDynamic();

        // Burn PRI-LP tokens and transfer PRO-LP tokens back
        _burnLP(_lpToken, _provider, _amount);
        emit UnstakedLiquidity(_amount, _provider);
    }

    /**
     * @notice Update the record when new policy is bought
     *         Only called from policy center
     *
     * @param _amount          Cover amount (usdc)
     * @param _premium         Premium for priority pool (in protocol token)
     * @param _length          Cover length (in month)
     * @param _timestampLength Cover length (in second)
     */
    function updateWhenBuy(
        uint256 _amount,
        uint256 _premium,
        uint256 _length,
        uint256 _timestampLength
    ) external whenNotPaused onlyPolicyCenter {
        // Check cover length
        _checkLength(_length);

        // Check cover amount
        _checkAmount(_amount);

        _updateDynamic();

        // Record cover amount in each month
        _updateCoverInfo(_amount, _length);

        // Update the weighted farming pool speed for this priority pool
        uint256 newSpeed = (_premium * SCALE) / _timestampLength;
        _updateWeightedFarmingSpeed(_length, newSpeed);
    }

    function _checkLength(uint256 _length) internal pure {
        if (_length > MAX_LENGTH || _length < MIN_LENGTH)
            revert PriorityPool__WrongCoverLength();
    }

    /**
     * @notice Pause this pool
     *
     * @param _paused True to pause, false to unpause
     */
    function pausePriorityPool(bool _paused) external {
        if ((msg.sender != owner) && (msg.sender != priorityPoolFactory))
            revert PriorityPool__NotOwnerOrFactory();

        _pause(_paused);
    }

    /**
     * @notice Liquidate pool
     *         Only callable by executor
     *         Only after the report has passed the voting
     *
     * @param _amount Payout amount to be moved out
     */
    function liquidatePool(uint256 _amount) external onlyExecutor {
        uint256 payout = _amount > activeCovered() ? activeCovered() : _amount;

        uint256 payoutRatio = _retrievePayout(payout);

        _updateCurrentLPWeight();

        _updateCoveredWhenLiquidated(payoutRatio);

        // Generation ++
        // Deploy the new generation lp token
        // Those who stake liquidity into this priority pool will be given the new lp token
        _deployNewGenerationLP(weightedFarmingPool);

        // Update other pools' cover indexes
        IProtectionPool(protectionPool).updateIndexCut();

        emit Liquidation(_amount, generation);
    }

    function _updateCoveredWhenLiquidated(uint256 _payoutRatio) internal {
        (uint256 currentYear, uint256 currentMonth, ) = block
            .timestamp
            .timestampToDate();

        // Only count the latest 3 months
        for (uint256 i; i < 3; ) {
            payoutInMonth[currentYear][currentMonth] =
                (coverInMonth[currentYear][currentMonth] * _payoutRatio) /
                SCALE;

            unchecked {
                if (++currentMonth > 12) {
                    ++currentYear;
                    currentMonth = 1;
                }

                ++i;
            }
        }
    }

    function updateWhenClaimed(uint256 _expiry, uint256 _amount) external {
        require(msg.sender == payoutPool, "Only payout pool");

        (uint256 currentYear, uint256 currentMonth, ) = _expiry
            .timestampToDate();

        coverInMonth[currentYear][currentMonth] -= _amount;
        payoutInMonth[currentYear][currentMonth] -= _amount;
    }

    // ---------------------------------------------------------------------------------------- //
    // *********************************** Internal Functions ********************************* //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Check & update dynamic status of this pool
     *         Record this pool as "already dynamic" in factory
     *
     *         Every time there is a new interaction, will do this check
     */
    function _updateDynamic() internal {
        // Put the cheaper check in the first place
        if (!passedBasePeriod && (block.timestamp - startTime > DYNAMIC_TIME)) {
            IPriorityPoolFactory(priorityPoolFactory).updateDynamicPool(poolId);
            passedBasePeriod = true;
        }
    }

    function _checkAmount(uint256 _amount) internal pure {
        if (_amount < MIN_COVER_AMOUNT)
            revert PriorityPool__UnderMinCoverAmount();
    }

    /**
     * @notice Deploy a new generation lp token
     *         Generation starts from 1
     *
     * @return newLPAddress The deployed lp token address
     */
    function _deployNewGenerationLP(address _weightedFarmingPool)
        internal
        returns (address newLPAddress)
    {
        uint256 currentGeneration = ++generation;

        // PRI-LP-2-JOE-G1: First generation of JOE priority pool with pool id 2
        string memory _name = string.concat(
            "PRI-LP-",
            poolId._toString(),
            "-",
            poolName,
            "-G",
            currentGeneration._toString()
        );

        newLPAddress = address(new PriorityPoolToken(_name));
        lpTokenAddress[currentGeneration] = newLPAddress;

        IWeightedFarmingPool(_weightedFarmingPool).addToken(
            poolId,
            newLPAddress,
            SCALE
        );

        priceIndex[newLPAddress] = SCALE;

        isLPToken[newLPAddress] = true;

        emit NewGenerationLPTokenDeployed(
            poolName,
            poolId,
            currentGeneration,
            _name,
            newLPAddress
        );
    }

    /**
     * @notice Mint current generation lp tokens
     *
     * @param _user   User address
     * @param _amount PRI-LP token amount
     */
    function _mintLP(address _user, uint256 _amount) internal {
        // Get current generation lp token address and mint tokens
        address lp = currentLPAddress();
        PriorityPoolToken(lp).mint(_user, _amount);
    }

    /**
     * @notice Burn lp tokens
     *         Need specific generation lp token address as parameter
     *
     * @param _lpToken PRI-LP token adderss
     * @param _user    User address
     * @param _amount  PRI-LP token amount to burn
     */
    function _burnLP(
        address _lpToken,
        address _user,
        uint256 _amount
    ) internal {
        // Transfer PRO-LP token to user
        uint256 proLPAmount = (priceIndex[_lpToken] * _amount) / SCALE;
        SimpleERC20(protectionPool).transfer(_user, proLPAmount);

        // Burn PRI-LP token
        PriorityPoolToken(_lpToken).burn(_user, _amount);
    }

    /**
     * @notice Update cover record info when new covers come in
     *         Record the total cover amount in each month
     *
     * @param _amount Cover amount
     * @param _length Cover length in month
     */
    function _updateCoverInfo(uint256 _amount, uint256 _length) internal {
        (uint256 currentYear, uint256 currentMonth, uint256 currentDay) = block
            .timestamp
            .timestampToDate();

        uint256 monthsToAdd = _length - 1;

        if (currentDay >= 25) {
            monthsToAdd++;
        }

        uint256 endYear = currentYear;
        uint256 endMonth;

        // Check if the cover will end in the same year
        if (currentMonth + monthsToAdd > 12) {
            endMonth = currentMonth + monthsToAdd - 12;
            ++endYear;
        } else {
            endMonth = currentMonth + monthsToAdd;
        }

        coverInMonth[endYear][endMonth] += _amount;
    }

    /**
     * @notice Update the farming speed in WeightedFarmingPool
     *
     * @param _length   Length in month
     * @param _newSpeed Speed to be added (SCALED)
     */
    function _updateWeightedFarmingSpeed(uint256 _length, uint256 _newSpeed)
        internal
    {
        uint256[] memory _years = new uint256[](_length);
        uint256[] memory _months = new uint256[](_length);

        (uint256 currentYear, uint256 currentMonth, ) = block
            .timestamp
            .timestampToDate();

        for (uint256 i; i < _length; ) {
            _years[i] = currentYear;
            _months[i] = currentMonth;

            unchecked {
                if (++currentMonth > 12) {
                    ++currentYear;
                    currentMonth = 1;
                }
                ++i;
            }
        }

        IWeightedFarmingPool(weightedFarmingPool).updateRewardSpeed(
            poolId,
            _newSpeed,
            _years,
            _months
        );
    }

    /**
     * @notice Retrieve assets from Protection Pool for payout
     *
     * @param _amount Amount of usdc to retrieve
     */
    function _retrievePayout(uint256 _amount)
        internal
        returns (uint256 payoutRatio)
    {
        // Current PRO-LP amount
        uint256 currentLPAmount = SimpleERC20(protectionPool).balanceOf(
            address(this)
        );

        IProtectionPool proPool = IProtectionPool(protectionPool);

        uint256 proLPPrice = proPool.getLatestPrice();

        // Need how many PRO-LP tokens to cover the _amount
        uint256 neededLPAmount = (_amount * SCALE) / proLPPrice;

        // If current PRO-LP inside priority pool is enough
        // Remove part of the liquidity from Protection Pool
        if (neededLPAmount < currentLPAmount) {
            proPool.removedLiquidity(neededLPAmount, payoutPool);

            priceIndex[currentLPAddress()] =
                ((currentLPAmount - neededLPAmount) * SCALE) /
                currentLPAmount;
        } else {
            uint256 usdcGot = proPool.removedLiquidity(
                currentLPAmount,
                payoutPool
            );

            uint256 remainingPayout = _amount - usdcGot;

            proPool.removedLiquidityWhenClaimed(remainingPayout, payoutPool);

            priceIndex[currentLPAddress()] = 0;
        }

        // Set a ratio used when claiming with crTokens
        // E.g. ratio is 1e11
        //      You can only use 10% (1e11 / SCALE) of your crTokens for claiming
        activeCovered() > 0
            ? payoutRatio = (_amount * SCALE) / activeCovered()
            : payoutRatio = 0;

        IPayoutPool(payoutPool).newPayout(
            poolId,
            generation,
            _amount,
            payoutRatio,
            coverIndex,
            address(this)
        );
    }

    function _updateCurrentLPWeight() internal {
        address lp = currentLPAddress();

        // Update the farming pool with the new price index
        IWeightedFarmingPool(weightedFarmingPool).updateWeight(
            poolId,
            lp,
            priceIndex[lp]
        );
    }
}

