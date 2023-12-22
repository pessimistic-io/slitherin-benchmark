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

import "./ExternalTokenDependencies.sol";
import "./PolicyCenterEventError.sol";
import "./PolicyCenterDependencies.sol";

import "./OwnableWithoutContextUpgradeable.sol";

import "./IPriceGetter.sol";

import "./DateTime.sol";
import "./StringUtils.sol";
import "./SimpleSafeERC20.sol";

import "./ISwapHelper.sol";

/**
 * @title Policy Center
 *
 * @author Eric Lee (ylikp.ust@gmail.com) & Primata (primata@375labs.org)
 *
 * @notice This is the policy center for degis Protocol Protection
 *         Users can buy policies and get payoff here
 *         Sellers can provide liquidity and choose the pools to cover
 *
 */
contract PolicyCenter is
    PolicyCenterEventError,
    OwnableWithoutContextUpgradeable,
    ExternalTokenDependencies,
    PolicyCenterDependencies
{
    using SimpleSafeERC20 for SimpleIERC20;
    using StringUtils for uint256;

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Variables **************************************** //
    // ---------------------------------------------------------------------------------------- //

    address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    // Pool Id => Priority Pool Address
    // Updated once pools are deployed
    // Protection Pool is pool 0
    mapping(uint256 => address) public priorityPools;

    // Pool Id => Pool Native Token Address
    mapping(uint256 => address) public tokenByPoolId;

    // Protocol token => Oracle type
    // 0: Default as chainlink oracle
    // 1: Dex oracle by traderJoe
    mapping(address => uint256) public oracleType;

    // Protocol token => Exchange router address
    // Some tokens use Joe-V1, some use Joe-LiquidityBook
    mapping(address => address) public exchangeByToken;

    address public swapHelper;

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Constructor ************************************** //
    // ---------------------------------------------------------------------------------------- //

    function initialize(
        address _deg,
        address _veDeg,
        address _protectionPool
    ) public initializer {
        __Ownable_init();
        __ExternalToken__Init(_deg, _veDeg);

        // Peotection pool as pool 0 and with usdc token
        priorityPools[0] = _protectionPool;
        tokenByPoolId[0] = USDC;

        protectionPool = _protectionPool;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************** Modifiers *************************************** //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Whether the pool exists
     */
    modifier poolExists(uint256 _poolId) {
        if (_poolId == 0 || priorityPools[_poolId] == address(0))
            revert PolicyCenter__NonExistentPool();
        _;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ View Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Returns the current LP address for a Pool ID
     *
     *         "Current" means the LP address that is currently being used
     *         Because each priority pool may have several generations of LP tokens
     *         Once reported and paid out, the LP generation will be updated
     *
     * @param _poolId Priority Pool ID
     *
     * @return lpAddress Current generation LP token address
     */
    function currentLPAddress(
        uint256 _poolId
    ) external view returns (address lpAddress) {
        lpAddress = IPriorityPool(priorityPools[_poolId]).currentLPAddress();
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ Set Functions ************************************* //
    // ---------------------------------------------------------------------------------------- //

    function setExchange(address _exchange) external onlyOwner {
        exchange = _exchange;
    }

    function setPriceGetter(address _priceGetter) external onlyOwner {
        priceGetter = _priceGetter;
    }

    function setProtectionPool(address _protectionPool) external onlyOwner {
        protectionPool = _protectionPool;
    }

    function setWeightedFarmingPool(
        address _weightedFarmingPool
    ) external onlyOwner {
        weightedFarmingPool = _weightedFarmingPool;
    }

    function setCoverRightTokenFactory(
        address _coverRightTokenFactory
    ) external onlyOwner {
        coverRightTokenFactory = _coverRightTokenFactory;
    }

    function setPriorityPoolFactory(
        address _priorityPoolFactory
    ) external onlyOwner {
        priorityPoolFactory = _priorityPoolFactory;
    }

    function setPayoutPool(address _payoutPool) external onlyOwner {
        payoutPool = _payoutPool;
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function setDexPriceGetter(address _dexPriceGetter) external onlyOwner {
        dexPriceGetter = _dexPriceGetter;
    }

    function setSwapHelper(address _swapHelper) external onlyOwner {
        swapHelper = _swapHelper;
    }

    function setOracleType(address _token, uint256 _type) external onlyOwner {
        require(_type < 2, "Wrong type");
        oracleType[_token] = _type;
    }

    function setExchangeByToken(
        address _token,
        address _exchange
    ) external onlyOwner {
        exchangeByToken[_token] = _exchange;
    }

    /**
     * @notice Approve the exchange to swap tokens
     *
     * @param _token Address of the approved token
     */
    function approvePoolToken(address _token) external onlyOwner {
        _approvePoolToken(_token);
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ Main Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Buy new cover for a given pool
     *
     *         Select a pool with parameter "poolId"
     *         Cover amount is in usdc and duration is in month
     *         The premium ratio may be dynamic so "maxPayment" is similar to "slippage"
     *
     * @param _poolId        Pool id
     * @param _coverAmount   Amount to cover
     * @param _coverDuration Cover duration in month (1 ~ 3)
     * @param _maxPayment    Maximum payment user can accept
     *
     * @return crToken CR token address
     */
    function buyCover(
        uint256 _poolId,
        uint256 _coverAmount,
        uint256 _coverDuration,
        uint256 _maxPayment
    ) external poolExists(_poolId) returns (address) {
        if (!_withinLength(_coverDuration)) revert PolicyCenter__BadLength();

        _checkCapacity(_poolId, _coverAmount);

        // Premium in USD and duration in second
        (uint256 premium, uint256 timestampDuration) = _getCoverPrice(
            _poolId,
            _coverAmount,
            _coverDuration
        );
        // Check if premium cost is within limits given by user
        if (premium > _maxPayment) revert PolicyCenter__PremiumTooHigh();

        // Mint cover right tokens to buyer
        // CR token has different months and generations
        address crToken = _checkCRToken(_poolId, _coverDuration);
        ICoverRightToken(crToken).mint(_poolId, msg.sender, _coverAmount);

        // Split the premium income and update the pool status
        (
            uint256 premiumToPriorityPool,
            ,
            uint256 premiumToTreasury
        ) = _splitPremium(_poolId, premium);

        IProtectionPool(protectionPool).updateWhenBuy();
        IPriorityPool(priorityPools[_poolId]).updateWhenBuy(
            _coverAmount,
            premiumToPriorityPool,
            _coverDuration,
            timestampDuration
        );
        ITreasury(treasury).premiumIncome(_poolId, premiumToTreasury);

        emit CoverBought(
            msg.sender,
            _poolId,
            _coverDuration,
            _coverAmount,
            premium
        );

        return crToken;
    }

    /**
     * @notice Provide liquidity to Protection Pool
     *
     * @param _amount Amount of liquidity (usdc) to provide
     */
    function provideLiquidity(uint256 _amount) external {
        if (_amount == 0) revert PolicyCenter__ZeroAmount();

        // Mint PRO-LP tokens and transfer usdc
        IProtectionPool(protectionPool).providedLiquidity(_amount, msg.sender);
        SimpleIERC20(USDC).transferFrom(msg.sender, protectionPool, _amount);

        emit LiquidityProvided(msg.sender, _amount);
    }

    /**
     * @notice Stake Protection Pool LP (PRO-LP) into priority pools
     *         And automatically stake the PRI-LP tokens into weighted farming pool
     *         With this function, no need for approval of PRI-LP tokens
     *
     *         If you want to hold the PRI-LP tokens for other usage
     *         Call "stakeLiquidityWithoutFarming"
     *
     * @param _poolId Pool id
     * @param _amount Amount of PRO-LP tokens to stake
     */
    function stakeLiquidity(
        uint256 _poolId,
        uint256 _amount
    ) public poolExists(_poolId) {
        if (_amount == 0) revert PolicyCenter__ZeroAmount();

        address pool = priorityPools[_poolId];

        // Update status and mint Prority Pool LP tokens
        // Directly mint pri-lp tokens to policy center
        // And send the PRI-LP tokens to weighted farming pool
        // No need for approval
        address lpToken = IPriorityPool(pool).stakedLiquidity(
            _amount,
            address(this)
        );
        SimpleIERC20(protectionPool).transferFrom(msg.sender, pool, _amount);
        IProtectionPool(protectionPool).updateStakedSupply(true, _amount);

        IWeightedFarmingPool(weightedFarmingPool).depositFromPolicyCenter(
            _poolId,
            lpToken,
            _amount,
            msg.sender
        );
        SimpleIERC20(lpToken).transfer(weightedFarmingPool, _amount);

        emit LiquidityStaked(msg.sender, _poolId, _amount);
    }

    /**
     * @notice Stake liquidity to priority pool without depositing into farming
     *
     * @param _poolId Pool id
     * @param _amount Amount of PRO-LP amount
     */
    function stakeLiquidityWithoutFarming(
        uint256 _poolId,
        uint256 _amount
    ) public poolExists(_poolId) {
        if (_amount == 0) revert PolicyCenter__ZeroAmount();

        address pool = priorityPools[_poolId];

        // Mint PRI-LP tokens to the user directly
        IPriorityPool(pool).stakedLiquidity(_amount, msg.sender);
        SimpleIERC20(protectionPool).transferFrom(msg.sender, pool, _amount);

        IProtectionPool(protectionPool).updateStakedSupply(true, _amount);

        emit LiquidityStakedWithoutFarming(msg.sender, _poolId, _amount);
    }

    /**
     * @notice Unstake Protection Pool LP from priority pools
     *         There may be different generations of priority lp tokens
     *
     *         This function will first remove the PRI-LP token from farming pool
     *         Ensure that your PRI-LP tokens are inside the farming pool
     *         If the PRI-LP tokens are in your own wallet, use "unstakeLiquidityWithoutFarming"
     *
     * @param _poolId     Pool id
     * @param _priorityLP Priority lp token address to withdraw
     * @param _amount     Amount of LP(priority lp) tokens to withdraw
     */
    function unstakeLiquidity(
        uint256 _poolId,
        address _priorityLP,
        uint256 _amount
    ) public poolExists(_poolId) {
        if (_amount == 0) revert PolicyCenter__ZeroAmount();

        // First remove the PRI-LP token from weighted farming pool
        IWeightedFarmingPool(weightedFarmingPool).withdrawFromPolicyCenter(
            _poolId,
            _priorityLP,
            _amount,
            msg.sender
        );

        // Burn PRI-LP tokens and give back PRO-LP tokens
        IPriorityPool(priorityPools[_poolId]).unstakedLiquidity(
            _priorityLP,
            _amount,
            msg.sender
        );

        IProtectionPool(protectionPool).updateStakedSupply(false, _amount);

        emit LiquidityUnstaked(msg.sender, _poolId, _priorityLP, _amount);
    }

    /**
     * @notice Unstake liquidity without removing PRI-LP from farming
     *
     * @param _poolId     Pool id
     * @param _priorityLP PRI-LP token address
     * @param _amount     PRI-LP token amount to remove
     */
    function unstakeLiquidityWithoutFarming(
        uint256 _poolId,
        address _priorityLP,
        uint256 _amount
    ) external poolExists(_poolId) {
        if (_amount == 0) revert PolicyCenter__ZeroAmount();

        IPriorityPool(priorityPools[_poolId]).unstakedLiquidity(
            _priorityLP,
            _amount,
            msg.sender
        );

        IProtectionPool(protectionPool).updateStakedSupply(false, _amount);

        emit LiquidityUnstakedWithoutFarming(
            msg.sender,
            _poolId,
            _priorityLP,
            _amount
        );
    }

    /**
     * @notice Remove liquidity from protection pool
     *
     * @param _amount Amount of liquidity to provide
     */
    function removeLiquidity(uint256 _amount) external {
        if (_amount == 0) revert PolicyCenter__ZeroAmount();

        IProtectionPool(protectionPool).removedLiquidity(_amount, msg.sender);

        emit LiquidityRemoved(msg.sender, _amount);
    }

    /**
     * @notice Claim payout
     *         Need to use a specific crToken address as parameter
     *
     * @param _poolId     Pool id
     * @param _crToken    Cover right token address
     * @param _generation Generation of the priority pool
     */
    function claimPayout(
        uint256 _poolId,
        address _crToken,
        uint256 _generation
    ) public poolExists(_poolId) {
        (string memory poolName, , , , ) = IPriorityPoolFactory(
            priorityPoolFactory
        ).pools(_poolId);

        // Claim payout from payout pool
        // Get the actual claimed amount and new generation cr token to be minted
        (uint256 claimed, uint256 newGenerationCRAmount) = IPayoutPool(
            payoutPool
        ).claim(msg.sender, _crToken, _poolId, _generation);

        emit PayoutClaimed(msg.sender, claimed);

        // Check if the new generation crToken has been deployed
        // If so, get the address
        // If not, deploy the new generation cr token
        if (newGenerationCRAmount > 0) {
            uint256 expiry = ICoverRightToken(_crToken).expiry();

            address newCRToken = _checkNewCRToken(
                _poolId,
                poolName,
                expiry,
                ++_generation
            );

            ICoverRightToken(newCRToken).mint(
                _poolId,
                msg.sender,
                newGenerationCRAmount
            );
        }
    }

    /**
     * @notice Store new pool information
     *
     * @param _pool   Address of the priority pool
     * @param _token  Address of the priority pool's native token
     * @param _poolId Pool id
     */
    function storePoolInformation(
        address _pool,
        address _token,
        uint256 _poolId
    ) external {
        if (msg.sender != priorityPoolFactory)
            revert PolicyCenter__OnlyPriorityPoolFactory();

        // Should never change the protection pool information
        assert(_poolId > 0);

        tokenByPoolId[_poolId] = _token;
        priorityPools[_poolId] = _pool;

        _approvePoolToken(_token);
    }

    // ---------------------------------------------------------------------------------------- //
    // *********************************** Internal Functions ********************************* //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Swap tokens to USDC
     *
     * @param _fromToken Token address to swap from
     * @param _amount    Amount of token to swap from
     *
     * @return received Actual usdc amount received
     */
    function _swapTokens(
        address _fromToken,
        uint256 _amount
    ) internal returns (uint256 received) {
        SimpleIERC20(_fromToken).transfer(swapHelper, _amount);
        received = ISwapHelper(swapHelper).swap(_fromToken, _amount);

        emit PremiumSwapped(_fromToken, _amount, received);
    }

    /**
     * @notice Check the cover length
     *
     * @param _length Length to check (in month)
     *
     * @return withinLength Whether the cover is within the length
     */
    function _withinLength(uint256 _length) internal pure returns (bool) {
        return _length > 0 && _length <= MAX_COVER_LENGTH;
    }

    /**
     * @notice Check cover right tokens
     *         If the crToken does not exist, it will be deployed here
     *
     * @param _poolId        Pool id
     * @param _coverDuration Cover length in month
     *
     * @return crToken Cover right token address
     */
    function _checkCRToken(
        uint256 _poolId,
        uint256 _coverDuration
    ) internal returns (address crToken) {
        // Get the expiry timestamp
        (uint256 expiry, uint256 year, uint256 month) = DateTimeLibrary
            ._getExpiry(block.timestamp, _coverDuration);

        (
            string memory poolName,
            address poolAddress,
            ,
            ,

        ) = IPriorityPoolFactory(priorityPoolFactory).pools(_poolId);

        uint256 generation = IPriorityPool(poolAddress).generation();

        crToken = _getCRTokenAddress(_poolId, expiry, generation);
        if (crToken == address(0)) {
            // CR-JOE-2022-1-G1
            string memory tokenName = string.concat(
                "CR-",
                poolName,
                "-",
                year._toString(),
                "-",
                month._toString(),
                "-G",
                generation._toString()
            );

            crToken = ICoverRightTokenFactory(coverRightTokenFactory)
                .deployCRToken(
                    poolName,
                    _poolId,
                    tokenName,
                    expiry,
                    generation
                );
        }
    }

    /**
     * @notice Check whether need to deploy new cr token
     *
     * @param _poolId        Pool id
     * @param _poolName      Pool name
     * @param _expiry        Expiry timestamp of the cr token
     * @param _newGeneration New generation of the cr token
     *
     * @return newCRToken New cover right token address
     */
    function _checkNewCRToken(
        uint256 _poolId,
        string memory _poolName,
        uint256 _expiry,
        uint256 _newGeneration
    ) internal returns (address newCRToken) {
        (uint256 year, uint256 month, ) = DateTimeLibrary.timestampToDate(
            _expiry
        );

        // Check the cr token exist
        newCRToken = _getCRTokenAddress(_poolId, _expiry, _newGeneration);

        // If cr token not exists, deploy it
        if (newCRToken == address(0)) {
            // CR-JOE-2022-1-G1
            string memory tokenName = string.concat(
                "CR-",
                _poolName,
                "-",
                year._toString(),
                "-",
                month._toString(),
                "-G",
                _newGeneration._toString()
            );

            newCRToken = ICoverRightTokenFactory(coverRightTokenFactory)
                .deployCRToken(
                    _poolName,
                    _poolId,
                    tokenName,
                    _expiry,
                    _newGeneration
                );
        }
    }

    /**
     * @notice Get cover right token address
     *         The address is determined by poolId and expiry (last second of each month)
     *         If token not exist, it will return zero address
     *
     * @param _poolId     Pool id
     * @param _expiry     Expiry timestamp
     * @param _generation Generation of the priority pool
     *
     * @return crToken Cover right token address
     */
    function _getCRTokenAddress(
        uint256 _poolId,
        uint256 _expiry,
        uint256 _generation
    ) internal view returns (address) {
        bytes32 salt = keccak256(
            abi.encodePacked(_poolId, _expiry, _generation)
        );

        return
            ICoverRightTokenFactory(coverRightTokenFactory).saltToAddress(salt);
    }

    /**
     * @notice Get native token amount to pay
     *
     * @param _premium Premium in USD
     * @param _token   Native token address
     *
     * @return premiumInNativeToken Premium calculated in native token
     */
    function _getNativeTokenAmount(
        uint256 _premium,
        address _token
    ) internal returns (uint256 premiumInNativeToken) {
        // Price in 18 decimals
        uint256 price;
        if (oracleType[_token] == 0) {
            // By default use chainlink
            price = IPriceGetter(priceGetter).getLatestPrice(_token);
        } else if (oracleType[_token] == 1) {
            // If no chainlink oracle, use dex price getter
            price = IPriceGetter(dexPriceGetter).getLatestPrice(_token);
        } else revert("Wrong oracle type");

        // @audit Fix decimal for native tokens
        // Check the real decimal diff
        uint256 decimalDiff = IERC20Decimals(_token).decimals() - 6;
        premiumInNativeToken = (_premium * 1e18 * (10 ** decimalDiff)) / price;

        // Pay native tokens
        SimpleIERC20(_token).safeTransferFrom(
            msg.sender,
            address(this),
            premiumInNativeToken
        );
    }

    /**
     * @notice Split premium for a pool
     *         To priority pool is paid in native token
     *         To protection pool and treasury is paid in usdc
     *
     * @param _poolId       Pool id
     * @param _premiumInUSD Premium in USD
     *
     * @return toPriority   Premium to priority pool
     * @return toProtection Premium to protection pool
     * @return toTreasury   Premium to treasury
     */
    function _splitPremium(
        uint256 _poolId,
        uint256 _premiumInUSD
    )
        internal
        returns (uint256 toPriority, uint256 toProtection, uint256 toTreasury)
    {
        if (_premiumInUSD == 0) revert PolicyCenter__ZeroPremium();

        address nativeToken = tokenByPoolId[_poolId];

        // Premium in project native token (paid in internal function)
        uint256 premiumInNativeToken = _getNativeTokenAmount(
            _premiumInUSD,
            nativeToken
        );

        // Native tokens to Priority pool
        toPriority = (premiumInNativeToken * PREMIUM_TO_PRIORITY) / 10000;

        // Swap native tokens to usdc
        // Except for amount to priority pool, remaining is distributed in usdc
        uint256 amountToSwap = premiumInNativeToken - toPriority;
        // USDC amount received
        uint256 amountReceived = _swapTokens(nativeToken, amountToSwap);

        // USDC to Protection Pool
        toProtection =
            (amountReceived * PREMIUM_TO_PROTECTION) /
            (PREMIUM_TO_PROTECTION + PREMIUM_TO_TREASURY);
        // USDC to Treasury
        toTreasury = amountReceived - toProtection;

        emit PremiumSplitted(toPriority, toProtection, toTreasury);

        // @audit Add real transfer
        // Transfer tokens to different pools
        SimpleIERC20(nativeToken).transfer(weightedFarmingPool, toPriority);
        SimpleIERC20(USDC).transfer(protectionPool, toProtection);
        SimpleIERC20(USDC).transfer(treasury, toTreasury);
    }

    /**
     * @notice Approve a pool token for the exchange
     *
     * @param _token Token address
     */
    function _approvePoolToken(address _token) internal {
        address router = exchangeByToken[_token];
        if (router == address(0)) revert PolicyCenter__NoExchange();
        // approve exchange to swap policy center tokens for deg
        SimpleIERC20(_token).approve(router, type(uint256).max);
    }

    /**
     * @notice Get cover price from insurance pool
     *
     * @param _poolId        Pool id
     * @param _coverAmount   Cover amount (usdc)
     * @param _coverDuration Cover length in months (1,2,3)
     */
    function _getCoverPrice(
        uint256 _poolId,
        uint256 _coverAmount,
        uint256 _coverDuration
    ) internal view returns (uint256 price, uint256 timestampDuration) {
        (price, timestampDuration) = IPriorityPool(priorityPools[_poolId])
            .coverPrice(_coverAmount, _coverDuration);
    }

    /**
     * @notice Check priority pool capacity
     *
     * @param _poolId      Pool id
     * @param _coverAmount Amount (usdc) to cover
     */
    function _checkCapacity(
        uint256 _poolId,
        uint256 _coverAmount
    ) internal view {
        IPriorityPool pool = IPriorityPool(priorityPools[_poolId]);
        uint256 maxCapacityAmount = (SimpleIERC20(USDC).balanceOf(
            address(protectionPool)
        ) * pool.maxCapacity()) / 10000;

        if (maxCapacityAmount < _coverAmount + pool.activeCovered())
            revert PolicyCenter__InsufficientCapacity();
    }
}

