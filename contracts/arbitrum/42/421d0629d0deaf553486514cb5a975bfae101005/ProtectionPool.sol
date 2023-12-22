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

import "./ERC20Upgradeable.sol";

import "./ProtectionPoolDependencies.sol";
import "./ProtectionPoolEventError.sol";
import "./ExternalTokenDependencies.sol";

import "./OwnableWithoutContextUpgradeable.sol";
import "./PausableWithoutContextUpgradeable.sol";
import "./FlashLoanPool.sol";

import "./DateTime.sol";

/**
 * @title Protection Pool
 *
 * @author Eric Lee (ylikp.ust@gmail.com) & Primata (primata@375labs.org)
 *
 * @notice This is the protection pool contract for Degis Protocol Protection
 *
 *         Users can provide liquidity to protection pool and get PRO-LP token
 *
 *         If the priority pool is unable to fulfil the cover amount,
 *         Protection Pool will be able to provide the remaining part
 */

contract ProtectionPool is
    ProtectionPoolEventError,
    ERC20Upgradeable,
    FlashLoanPool,
    OwnableWithoutContextUpgradeable,
    PausableWithoutContextUpgradeable,
    ExternalTokenDependencies,
    ProtectionPoolDependencies
{
    using DateTimeLibrary for uint256;

    address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Variables **************************************** //
    // ---------------------------------------------------------------------------------------- //

    // Pool start time
    uint256 public startTime;

    // Last pool reward distribution
    uint256 public lastRewardTimestamp;

    // PRO_LP token price
    uint256 public price;

    // Total amount staked
    uint256 public stakedSupply;

    // Year => Month => Speed
    mapping(uint256 => mapping(uint256 => uint256)) public rewardSpeed;

    // ---------------------------------------------------------------------------------------- //
    // ************************************* Constructor ************************************** //
    // ---------------------------------------------------------------------------------------- //

    function initialize(
        address _deg,
        address _veDeg
    ) public initializer {
        __ERC20_init("ProtectionPool", "PRO-LP");
        __FlashLoan__Init(USDC);
        __Ownable_init();
        __Pausable_init();
        __ExternalToken__Init(_deg, _veDeg);

        // Register time that pool was deployed
        startTime = block.timestamp;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************** Modifiers *************************************** //
    // ---------------------------------------------------------------------------------------- //

    modifier onlyPolicyCenter() {
        if (msg.sender != policyCenter)
            revert ProtectionPool__OnlyPolicyCenter();
        _;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ View Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Get total active cover amount of all pools
     *         Only calculate those "already dynamic" pools
     *
     * @return activeCovered Covered amount
     */
    function getTotalActiveCovered()
        public
        view
        returns (uint256 activeCovered)
    {
        IPriorityPoolFactory factory = IPriorityPoolFactory(
            priorityPoolFactory
        );

        uint256 poolAmount = factory.poolCounter();

        for (uint256 i; i < poolAmount; ) {
            (, address poolAddress, , , ) = factory.pools(i + 1);

            if (factory.dynamic(poolAddress)) {
                activeCovered += IPriorityPool(poolAddress).activeCovered();
            }

            unchecked {
                ++i;
            }
        }
    }

    function getTotalCovered() public view returns (uint256 totalCovered) {
        IPriorityPoolFactory factory = IPriorityPoolFactory(
            priorityPoolFactory
        );

        uint256 poolAmount = factory.poolCounter();

        for (uint256 i; i < poolAmount; ) {
            (, address poolAddress, , , ) = factory.pools(i + 1);

            totalCovered += IPriorityPool(poolAddress).activeCovered();

            unchecked {
                ++i;
            }
        }
    }

    // @audit change decimal
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ Set Functions ************************************* //
    // ---------------------------------------------------------------------------------------- //

    function setIncidentReport(address _incidentReport) external onlyOwner {
        incidentReport = _incidentReport;
    }

    function setPolicyCenter(address _policyCenter) external onlyOwner {
        policyCenter = _policyCenter;
    }

    function setPriorityPoolFactory(address _priorityPoolFactory)
        external
        onlyOwner
    {
        priorityPoolFactory = _priorityPoolFactory;
    }

    // ---------------------------------------------------------------------------------------- //
    // ************************************ Main Functions ************************************ //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Update index cut when claim happened
     */
    function updateIndexCut() public {
        IPriorityPoolFactory factory = IPriorityPoolFactory(
            priorityPoolFactory
        );

        uint256 poolAmount = factory.poolCounter();

        uint256 currentReserved = SimpleIERC20(USDC).balanceOf(address(this));

        uint256 indexToCut;
        uint256 minRequirement;

        for (uint256 i; i < poolAmount; ) {
            (, address poolAddress, , , ) = factory.pools(i + 1);

            minRequirement = IPriorityPool(poolAddress).minAssetRequirement();

            if (minRequirement > currentReserved) {
                indexToCut = (currentReserved * 10000) / minRequirement;
                IPriorityPool(poolAddress).setCoverIndex(indexToCut);
            }

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Updates and retrieves latest price to provide liquidity to Protection Pool
     */
    function getLatestPrice() external returns (uint256) {
        _updatePrice();
        return price;
    }

    /**
     * @notice Finish providing liquidity
     *         Only callable through policyCenter
     *
     * @param _amount   Liquidity amount (usdc)
     * @param _provider Provider address
     */
    function providedLiquidity(uint256 _amount, address _provider)
        external
        onlyPolicyCenter
    {
        _updatePrice();

        // Mint PRO_LP tokens to the user
        uint256 amountToMint = (_amount * SCALE) / price;
        _mint(_provider, amountToMint);
        emit LiquidityProvided(_amount, amountToMint, _provider);
    }

    /**
     * @notice Finish removing liquidity
     *         Only callable through 
     *         1) policyCenter (by user removing liquidity)
     *         2) 
     *         
     *
     * @param _amount   Liquidity to remove (LP token amount)
     * @param _provider Provider address
     */
    function removedLiquidity(uint256 _amount, address _provider)
        external
        whenNotPaused
        returns (uint256 usdcToTransfer)
    {
        if (
            msg.sender != policyCenter &&
            !IPriorityPoolFactory(priorityPoolFactory).poolRegistered(
                msg.sender
            )
        ) revert ProtectionPool__OnlyPriorityPoolOrPolicyCenter();

        if (_amount > totalSupply())
            revert ProtectionPool__ExceededTotalSupply();

        _updatePrice();

        // Burn PRO_LP tokens to the user
        usdcToTransfer = (_amount * price) / SCALE;

        if (msg.sender == policyCenter) {
            checkEnoughLiquidity(usdcToTransfer);
        }

        // @audit Change path
        // If sent from policyCenter => this is a user action
        // If sent from priority pool => this is a payout action
        address realPayer = msg.sender == policyCenter ? _provider : msg.sender;

        _burn(realPayer, _amount);
        SimpleIERC20(USDC).transfer(_provider, usdcToTransfer);

        emit LiquidityRemoved(_amount, usdcToTransfer, _provider);
    }

    function checkEnoughLiquidity(uint256 _amountToRemove) public view {
        // Minimum usdc requirement
        uint256 minRequirement = minAssetRequirement();

        uint256 currentReserved = SimpleIERC20(USDC).balanceOf(address(this));

        if (currentReserved < minRequirement + _amountToRemove)
            revert ProtectionPool__NotEnoughLiquidity();
    }

    function minAssetRequirement()
        public
        view
        returns (uint256 minRequirement)
    {
        IPriorityPoolFactory factory = IPriorityPoolFactory(
            priorityPoolFactory
        );

        uint256 poolAmount = factory.poolCounter();
        uint256 minRequirementForPool;

        for (uint256 i; i < poolAmount; ) {
            (, address poolAddress, , , ) = factory.pools(i + 1);

            minRequirementForPool = IPriorityPool(poolAddress)
                .minAssetRequirement();

            minRequirement = minRequirementForPool > minRequirement
                ? minRequirementForPool
                : minRequirement;

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Removes liquidity when a claim is made
     *
     * @param _amount Amount of liquidity to remove
     * @param _to     Address to transfer the liquidity to
     */
    function removedLiquidityWhenClaimed(uint256 _amount, address _to)
        external
    {
        if (
            !IPriorityPoolFactory(priorityPoolFactory).poolRegistered(
                msg.sender
            )
        ) revert ProtectionPool__OnlyPriorityPool();

        if (_amount > SimpleIERC20(USDC).balanceOf(address(this)))
            revert ProtectionPool__NotEnoughBalance();

        SimpleIERC20(USDC).transfer(_to, _amount);

        _updatePrice();

        emit LiquidityRemovedWhenClaimed(msg.sender, _amount);
    }

    /**
     * @notice Update when new cover is bought
     */
    function updateWhenBuy() external onlyPolicyCenter {
        _updatePrice();
    }

    /**
     * @notice Set paused state of the protection pool
     *         Only callable by owner, incidentReport, or priorityPoolFactory
     *
     * @param _paused True for pause, false for unpause
     */
    function pauseProtectionPool(bool _paused) external {
        if (
            (msg.sender != owner()) &&
            (msg.sender != incidentReport) &&
            (msg.sender != priorityPoolFactory)
        ) revert ProtectionPool__NotAllowedToPause();
        _pause(_paused);
    }

    function updateStakedSupply(bool _isStake, uint256 _amount)
        external
        onlyPolicyCenter
    {
        if (_isStake) {
            stakedSupply += _amount;
        } else stakedSupply -= _amount;
    }

    // ---------------------------------------------------------------------------------------- //
    // *********************************** Internal Functions ********************************* //
    // ---------------------------------------------------------------------------------------- //

    /**
     * @notice Update the price of PRO_LP token
     */
    function _updatePrice() internal {
        if (totalSupply() == 0) {
            price = SCALE;
            return;
        }
        price =
            ((SimpleIERC20(USDC).balanceOf(address(this))) * SCALE) /
            totalSupply();

        emit PriceUpdated(price);
    }
}

