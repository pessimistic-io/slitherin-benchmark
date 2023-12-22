// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import {Errors} from "./Errors.sol";
import {DataTypes} from "./DataTypes.sol";
import {PoolSVSLogic} from "./PoolSVSLogic.sol";
import {MaturitySVSLogic} from "./MaturitySVSLogic.sol";
import {LiquiditySVSLogic} from "./LiquiditySVSLogic.sol";
import {MMEBase} from "./MMEBase.sol";
import {IMMESVS} from "./IMMESVS.sol";
import {ILPTokenSVS} from "./ILPTokenSVS.sol";
import {IAddressesRegistry} from "./IAddressesRegistry.sol";
import {IAccessManager} from "./IAccessManager.sol";
import {IAccessNFT} from "./IAccessNFT.sol";
import {IERC20Extended} from "./IERC20Extended.sol";
import {ISVSCollectionConnector} from "./ISVSCollectionConnector.sol";
import {IConnectorRouter} from "./IConnectorRouter.sol";

/**
 * @title MMESVS
 * @author Souq.Finance
 * @notice The Contract of all Pools sharing MMESVS specification for single collection of shares
 * @notice The fees inputted should be in wad
 * @notice The F inputted should be in wad
 * @notice the V updated should have the same decimals of the stablecoin and be in terms of the same stablecoin
 * @notice coefficients are in wad
 * @notice License: https://souq-exchange.s3.amazonaws.com/LICENSE.md
 */

contract MMESVS is Initializable, IMMESVS, MMEBase, ReentrancyGuardUpgradeable, PausableUpgradeable, OwnableUpgradeable {
    using PoolSVSLogic for DataTypes.AMMSubPoolSVS[];

    DataTypes.AMMSubPoolSVS[] public subPools;
    address public immutable factory;

    //Liquidity providers have a time waiting period between deposit and withdraw
    DataTypes.Queued1155Withdrawals public queuedWithdrawals;

    DataTypes.PoolSVSData public poolSVSData;
    uint256[50] _gap;

    constructor(address _factory, address addressRegistry) MMEBase(addressRegistry) {
        require(_factory != address(0), Errors.ADDRESS_IS_ZERO);
        factory = _factory;
    }

    /**
     * @dev Initializer function of the contract
     * @param _poolData the initial pool data
     * @param symbol the symbol of the lp token to be deployed
     * @param name the name of the lp token to be deployed
     */
    function initialize(DataTypes.PoolSVSData memory _poolData, string memory symbol, string memory name) external initializer {
        __Pausable_init();
        __Ownable_init();
        poolData = _poolData;
        poolData.fee.royaltiesBalance = 0;
        poolData.fee.royaltiesBalance = 0;
        poolData.poolLPToken = PoolSVSLogic.deployLPToken(
            address(this),
            addressesRegistry,
            poolData.tokens,
            symbol,
            name,
            IERC20Extended(poolData.stable).decimals()
        );
        yieldReserve = 0;
        PoolSVSLogic.addSubPool(0, 0, 0, subPools);
        poolData.firstActivePool = 1;
    }

    /**
     * @dev modifier for the functions to be called by the timelock contract only
     */
    modifier timelockOnly() {
        if (IAddressesRegistry(addressesRegistry).getAddress("TIMELOCK") != address(0)) {
            require(IAddressesRegistry(addressesRegistry).getAddress("TIMELOCK") == msg.sender, Errors.CALLER_NOT_TIMELOCK);
        }
        _;
    }

    /**
     * @dev modifier for the access token enabled functions
     * @param tokenId the id of the access token
     * @param functionName the name of the function with the modifier
     */
    modifier useAccessNFT(uint256 tokenId, string memory functionName) {
        if (poolData.useAccessToken) {
            require(IAccessNFT(poolData.accessToken).HasAccessNFT(msg.sender, tokenId, functionName), Errors.FUNCTION_REQUIRES_ACCESS_NFT);
        }
        _;
    }

    /**
     * @dev modifier for when the onlyAdminProvisioning is true to restrict liquidity addition to pool admin
     */
    modifier checkAdminProvisioning() {
        if (poolData.liquidityLimit.onlyAdminProvisioning) {
            require(
                IAccessManager(IAddressesRegistry(addressesRegistry).getAccessManager()).isPoolAdmin(msg.sender),
                Errors.ONLY_ADMIN_CAN_ADD_LIQUIDITY
            );
        }
        _;
    }

    /// @inheritdoc IMMESVS
    function pause() external onlyPoolAdmin {
        _pause();
        emit PoolPaused(msg.sender);
        ILPTokenSVS(poolData.poolLPToken).pause();
    }

    /// @inheritdoc IMMESVS
    function unpause() external timelockOnly {
        _unpause();
        emit PoolUnpaused(msg.sender);
        ILPTokenSVS(poolData.poolLPToken).unpause();
    }

    /// @inheritdoc IMMESVS
    function getTVL() external view returns (uint256) {
        (, uint256 tvl, , ) = PoolSVSLogic.calculateLiquidityDetailsIterative(addressesRegistry, poolData, subPools);
        return tvl;
    }

    /// @inheritdoc IMMESVS
    function getLPToken() external view returns (address) {
        return poolData.poolLPToken;
    }

    /// @inheritdoc IMMESVS
    function getLPPrice() external view returns (uint256) {
        (, , , uint256 lpPrice) = PoolSVSLogic.calculateLiquidityDetailsIterative(addressesRegistry, poolData, subPools);
        return lpPrice;
    }

    /// @inheritdoc IMMESVS
    function getPool(uint256 subPoolId) external view returns (DataTypes.AMMSubPoolSVSDetails memory subpool) {
        return PoolSVSLogic.getPool(subPools, subPoolId);
    }

    /// @inheritdoc IMMESVS
    function getSubPoolTotal(uint256 subPoolId) external view returns (uint256) {
        (uint256 v, , , ) = PoolSVSLogic.calculateLiquidityDetailsIterative(addressesRegistry, poolData, subPools);
        return PoolSVSLogic.calculateTotal(subPools, v, subPoolId);
    }

    /// @inheritdoc IMMESVS
    function getQuote(
        uint256[] calldata amounts,
        uint256[] calldata tokenIds,
        bool buy,
        bool useFee
    ) external view returns (DataTypes.Quotation memory quotation) {
        DataTypes.Shares1155Params memory sharesParams = DataTypes.Shares1155Params({amounts: amounts, tokenIds: tokenIds});
        quotation = LiquiditySVSLogic.getQuote(
            DataTypes.QuoteParams({buy: buy, useFee: useFee}),
            sharesParams,
            addressesRegistry,
            poolData,
            subPools
        );
    }

    /// @inheritdoc IMMESVS
    function swapStable(
        uint256[] memory requiredAmounts,
        uint256[] memory tokenIds,
        uint256 maxStable
    ) external nonReentrant useAccessNFT(1, "swapStable") whenNotPaused {
        DataTypes.Shares1155Params memory sharesParams = DataTypes.Shares1155Params({amounts: requiredAmounts, tokenIds: tokenIds});
        LiquiditySVSLogic.swapStable(msg.sender, maxStable, sharesParams, addressesRegistry, poolData, subPools);
    }

    /// @inheritdoc IMMESVS
    function swapShares(
        uint256[] memory amounts,
        uint256[] memory tokenIds,
        uint256 minStable
    ) external nonReentrant useAccessNFT(1, "swapShares") whenNotPaused {
        DataTypes.Shares1155Params memory sharesParams = DataTypes.Shares1155Params({amounts: amounts, tokenIds: tokenIds});
        LiquiditySVSLogic.swapShares(msg.sender, minStable, yieldReserve, sharesParams, addressesRegistry, poolData, subPools);
    }

    /// @inheritdoc IMMESVS
    function depositInitial(
        uint256[] memory tokenIds,
        uint256[] memory amounts,
        uint256 stableIn,
        uint256 subPoolId
    ) external nonReentrant onlyPoolAdmin {
        DataTypes.Shares1155Params memory sharesParams = DataTypes.Shares1155Params({amounts: amounts, tokenIds: tokenIds});
        LiquiditySVSLogic.depositInitial(msg.sender, subPoolId, stableIn, sharesParams, addressesRegistry, poolData, subPools);
    }

    /// @inheritdoc IMMESVS
    function addLiquidityStable(
        uint256 targetLP,
        uint256 maxStable
    ) external nonReentrant useAccessNFT(1, "addLiquidityStable") checkAdminProvisioning whenNotPaused {
        require(poolData.liquidityLimit.addLiqMode != 1, Errors.LIQUIDITY_MODE_RESTRICTED);
        LiquiditySVSLogic.addLiquidityStable(msg.sender, targetLP, maxStable, addressesRegistry, poolData, subPools);
    }

    /// @inheritdoc IMMESVS
    function removeLiquidityStable(uint256 targetLP, uint256 minStable) external nonReentrant whenNotPaused {
        require(poolData.liquidityLimit.removeLiqMode != 1, Errors.LIQUIDITY_MODE_RESTRICTED);
        LiquiditySVSLogic.removeLiquidityStable(
            msg.sender,
            yieldReserve,
            targetLP,
            minStable,
            addressesRegistry,
            poolData,
            subPools,
            queuedWithdrawals
        );
    }

    /// @inheritdoc IMMESVS
    // function processWithdrawals(uint256 limit) external whenNotPaused returns (uint256 transactions) {
    // transactions = LiquiditySVSLogic.processWithdrawals(limit, poolData, queuedWithdrawals);
    //     transactions = 0;
    // }

    /// @inheritdoc IMMESVS
    function getTokenIdAvailable(uint256 tokenId) external view returns (uint256) {
        (uint256 id, , , , ) = PoolSVSLogic.checkSubPool(tokenId, addressesRegistry, poolData, subPools);
        return subPools[id].shares[tokenId].amount;
    }

    /// @inheritdoc IMMESVS
    function getSubPools(uint256[] memory tokenIds) external view returns (uint256[] memory) {
        return PoolSVSLogic.getSubPools(tokenIds, addressesRegistry, poolData, subPools);
    }

    /// @inheritdoc IMMESVS
    function addSubPool(uint256 f, uint256 start, uint256 lockupTime) external onlyPoolAdmin {
        PoolSVSLogic.addSubPool(f, start, lockupTime, subPools);
    }

    function addSubPoolsAuto(uint256 f, uint256 start) external onlyPoolAdmin {
        PoolSVSLogic.addSubPoolsAuto(f, start, addressesRegistry, poolData, subPools);
    }

    /// @inheritdoc IMMESVS
    function changeSubPoolStatus(uint256[] calldata subPoolIds, bool newStatus) external onlyPoolAdmin {
        PoolSVSLogic.changeSubPoolStatus(subPoolIds, newStatus, subPools);
    }

    /// @inheritdoc IMMESVS
    function moveReserve(uint256 moverId, uint256 movedId, uint256 amount) external onlyPoolAdmin {
        LiquiditySVSLogic.moveReserve(moverId, movedId, amount, addressesRegistry, poolData, subPools);
    }

    /// @inheritdoc IMMESVS
    function RescueTokens(address token, uint256 amount, address receiver) external onlyPoolAdmin {
        PoolSVSLogic.RescueTokens(token, amount, receiver, poolData.stable, poolData.poolLPToken);
    }

    /// @inheritdoc IMMESVS
    function WithdrawFees(address to, uint256 amount, DataTypes.FeeType feeType) external {
        LiquiditySVSLogic.withdrawFees(msg.sender, to, amount, feeType, poolData);
    }

    /// @inheritdoc IMMESVS
    function updateMaxMaturityRange(uint256 f, uint256 newMaxMaturityRange) external onlyPoolAdmin {
        MaturitySVSLogic.updateMaxMaturityRange(f, newMaxMaturityRange, addressesRegistry, poolData, subPools);
    }

    /// @inheritdoc IMMESVS
    function getMatureShares() external view returns (DataTypes.VaultSharesReturn[] memory) {
        return MaturitySVSLogic.getMatureShares(poolData, subPools);
    }

    /// @inheritdoc IMMESVS
    function moveMatureShares(uint256 maxTrancheCount) external onlyPoolAdminOrOperations returns (uint256 trancheCount) {
        return MaturitySVSLogic.moveMatureShares(addressesRegistry, poolData, subPools, maxTrancheCount);
    }

    /// @inheritdoc IMMESVS
    function moveMatureSharesList(
        uint256[] memory tranches,
        uint256[] memory amounts
    ) external onlyPoolAdminOrOperations returns (uint256 trancheCount) {
        return MaturitySVSLogic.moveMatureSharesList(addressesRegistry, poolData, subPools, tranches, amounts);
    }

    /// @inheritdoc IMMESVS
    function cleanMatureSubPools() external onlyPoolAdminOrOperations {
        MaturitySVSLogic.cleanMatureSubPools(poolData, subPools);
    }

    /// @inheritdoc IMMESVS
    function redeemMatureShares(uint256 maxTrancheCount) external onlyPoolAdminOrOperations returns (uint256 trancheCount) {
        return MaturitySVSLogic.redeemMatureShares(addressesRegistry, poolData, subPools, maxTrancheCount);
    }

    /// @inheritdoc IMMESVS
    function redistrubteLiquidity() external onlyPoolAdminOrOperations {
        LiquiditySVSLogic.redistrubteLiquidity(addressesRegistry, poolData, subPools);
    }

    // /// @inheritdoc IMMESVS
    // function changeLockupTimes(uint256[] memory lastLockupTimes) external onlyPoolAdmin {
    //     MaturitySVSLogic.changeLockupTimes(addressesRegistry, poolData, subPools, lastLockupTimes);
    // }

    /// @inheritdoc IMMESVS
    function getSubPoolsCount() external view returns (uint256 count) {
        count = subPools.length;
    }

    /// @inheritdoc IMMESVS
    function setPoolData(DataTypes.PoolSVSData calldata newPoolData) external onlyPoolAdmin {
        LiquiditySVSLogic.setPoolData(addressesRegistry, poolData, subPools, newPoolData);
    }
}

