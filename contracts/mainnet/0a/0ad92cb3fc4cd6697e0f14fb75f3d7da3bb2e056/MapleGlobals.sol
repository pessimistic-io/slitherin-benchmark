// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.7;

import { NonTransparentProxied } from "./NonTransparentProxied.sol";

import { IMapleGlobals } from "./IMapleGlobals.sol";

import { IChainlinkAggregatorV3Like, IPoolManagerLike } from "./Interfaces.sol";

/*

    ███╗   ███╗ █████╗ ██████╗ ██╗     ███████╗     ██████╗ ██╗      ██████╗ ██████╗  █████╗ ██╗     ███████╗
    ████╗ ████║██╔══██╗██╔══██╗██║     ██╔════╝    ██╔════╝ ██║     ██╔═══██╗██╔══██╗██╔══██╗██║     ██╔════╝
    ██╔████╔██║███████║██████╔╝██║     █████╗      ██║  ███╗██║     ██║   ██║██████╔╝███████║██║     ███████╗
    ██║╚██╔╝██║██╔══██║██╔═══╝ ██║     ██╔══╝      ██║   ██║██║     ██║   ██║██╔══██╗██╔══██║██║     ╚════██║
    ██║ ╚═╝ ██║██║  ██║██║     ███████╗███████╗    ╚██████╔╝███████╗╚██████╔╝██████╔╝██║  ██║███████╗███████║
    ╚═╝     ╚═╝╚═╝  ╚═╝╚═╝     ╚══════╝╚══════╝     ╚═════╝ ╚══════╝ ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝╚══════╝

*/

contract MapleGlobals is IMapleGlobals, NonTransparentProxied {

    /******************************************************************************************************************************/
    /*** Structs                                                                                                                ***/
    /******************************************************************************************************************************/

    struct PoolDelegate {
        address ownedPoolManager;
        bool    isPoolDelegate;
    }

    struct ScheduledCall {
        uint256 timestamp;
        bytes32 dataHash;
    }

    struct TimelockParameters {
        uint128 delay;
        uint128 duration;
    }

    /******************************************************************************************************************************/
    /*** Storage                                                                                                                ***/
    /******************************************************************************************************************************/

    uint256 public constant HUNDRED_PERCENT = 100_0000;

    address public override mapleTreasury;
    address public override migrationAdmin;
    address public override pendingGovernor;
    address public override securityAdmin;

    bool public override protocolPaused;

    TimelockParameters public override defaultTimelockParameters;

    mapping(address => address) public override oracleFor;

    mapping(address => bool) public override isBorrower;
    mapping(address => bool) public override isCollateralAsset;
    mapping(address => bool) public override isPoolAsset;
    mapping(address => bool) public override isPoolDeployer;

    mapping(address => uint256) public override manualOverridePrice;
    mapping(address => uint256) public override maxCoverLiquidationPercent;
    mapping(address => uint256) public override minCoverAmount;
    mapping(address => uint256) public override bootstrapMint;
    mapping(address => uint256) public override platformManagementFeeRate;
    mapping(address => uint256) public override platformOriginationFeeRate;
    mapping(address => uint256) public override platformServiceFeeRate;

    mapping(address => mapping(bytes32 => TimelockParameters)) public override timelockParametersOf;

    mapping(bytes32 => mapping(address => bool)) public override isFactory;

    // Timestamp and call data hash for a caller, on a contract, for a function id.
    mapping(address => mapping(address => mapping(bytes32 => ScheduledCall))) public override scheduledCalls;

    mapping(address => PoolDelegate) public override poolDelegates;

    /******************************************************************************************************************************/
    /*** Modifiers                                                                                                              ***/
    /******************************************************************************************************************************/

    modifier isGovernor {
        require(msg.sender == admin(), "MG:NOT_GOVERNOR");
        _;
    }

    /******************************************************************************************************************************/
    /*** Governor Transfer Functions                                                                                            ***/
    /******************************************************************************************************************************/

    function acceptGovernor() external {
        require(msg.sender == pendingGovernor, "MG:NOT_PENDING_GOVERNOR");
        emit GovernorshipAccepted(admin(), msg.sender);
        _setAddress(ADMIN_SLOT, msg.sender);
        pendingGovernor = address(0);
    }

    function setPendingGovernor(address pendingGovernor_) external isGovernor {
        emit PendingGovernorSet(pendingGovernor = pendingGovernor_);
    }

    /******************************************************************************************************************************/
    /*** Global Setters                                                                                                         ***/
    /******************************************************************************************************************************/

    // NOTE: `minCoverAmount` is not enforced at activation time.
    function activatePoolManager(address poolManager_) external override isGovernor {
        address delegate_ = IPoolManagerLike(poolManager_).poolDelegate();
        require(poolDelegates[delegate_].ownedPoolManager == address(0), "MG:APM:ALREADY_OWNS");

        emit PoolManagerActivated(poolManager_, delegate_);
        poolDelegates[delegate_].ownedPoolManager = poolManager_;
        IPoolManagerLike(poolManager_).setActive(true);
    }

    function setMapleTreasury(address mapleTreasury_) external override isGovernor {
        require(mapleTreasury_ != address(0), "MG:SMT:ZERO_ADDRESS");
        emit MapleTreasurySet(mapleTreasury, mapleTreasury_);
        mapleTreasury = mapleTreasury_;
    }

    function setMigrationAdmin(address migrationAdmin_) external override isGovernor {
        emit MigrationAdminSet(migrationAdmin, migrationAdmin_);
        migrationAdmin = migrationAdmin_;
    }

    function setBootstrapMint(address asset_, uint256 amount_) external override isGovernor {
        emit BootstrapMintSet(asset_, bootstrapMint[asset_] = amount_);
    }

    function setPriceOracle(address asset_, address oracle_) external override isGovernor {
        require(oracle_ != address(0) && asset_ != address(0), "MG:SPO:ZERO_ADDRESS");
        oracleFor[asset_] = oracle_;
        emit PriceOracleSet(asset_, oracle_);
    }

    function setSecurityAdmin(address securityAdmin_) external override isGovernor {
        require(securityAdmin_ != address(0), "MG:SSA:ZERO_ADDRESS");
        emit SecurityAdminSet(securityAdmin, securityAdmin_);
        securityAdmin = securityAdmin_;
    }

    function setDefaultTimelockParameters(uint128 defaultTimelockDelay_, uint128 defaultTimelockDuration_) external override isGovernor {
        emit DefaultTimelockParametersSet(defaultTimelockParameters.delay, defaultTimelockDelay_, defaultTimelockParameters.duration, defaultTimelockDuration_);
        defaultTimelockParameters = TimelockParameters(defaultTimelockDelay_, defaultTimelockDuration_);
    }

    /******************************************************************************************************************************/
    /*** Boolean Setters                                                                                                        ***/
    /******************************************************************************************************************************/

    function setProtocolPause(bool protocolPaused_) external override {
        require(msg.sender == securityAdmin, "MG:SPP:NOT_SECURITY_ADMIN");
        protocolPaused = protocolPaused_;
        emit ProtocolPauseSet(msg.sender, protocolPaused_);
    }

    /******************************************************************************************************************************/
    /*** Allowlist Setters                                                                                                      ***/
    /******************************************************************************************************************************/

    function setValidBorrower(address borrower_, bool isValid_) external override isGovernor {
        isBorrower[borrower_] = isValid_;
        emit ValidBorrowerSet(borrower_, isValid_);
    }

    function setValidCollateralAsset(address collateralAsset_, bool isValid_) external override isGovernor {
        isCollateralAsset[collateralAsset_] = isValid_;
        emit ValidCollateralAssetSet(collateralAsset_, isValid_);
    }

    function setValidFactory(bytes32 factoryKey_, address factory_, bool isValid_) external override isGovernor {
        isFactory[factoryKey_][factory_] = isValid_;
        emit ValidFactorySet(factoryKey_, factory_, isValid_);
    }

    function setValidPoolAsset(address poolAsset_, bool isValid_) external override isGovernor {
        isPoolAsset[poolAsset_] = isValid_;
        emit ValidPoolAssetSet(poolAsset_, isValid_);
    }

    function setValidPoolDelegate(address account_, bool isValid_) external override isGovernor {
        require(account_ != address(0),                                             "MG:SVPD:ZERO_ADDRESS");
        require(isValid_ || poolDelegates[account_].ownedPoolManager == address(0), "MG:SVPD:OWNS_POOL_MANAGER");  // Cannot remove pool delegates that own a pool manager.
        poolDelegates[account_].isPoolDelegate = isValid_;
        emit ValidPoolDelegateSet(account_, isValid_);
    }

    function setValidPoolDeployer(address poolDeployer_, bool isValid_) external override isGovernor {
        isPoolDeployer[poolDeployer_] = isValid_;
        emit ValidPoolDeployerSet(poolDeployer_, isValid_);
    }

    /******************************************************************************************************************************/
    /*** Price Setters                                                                                                          ***/
    /******************************************************************************************************************************/

    function setManualOverridePrice(address asset_, uint256 price_) external override isGovernor {
        manualOverridePrice[asset_] = price_;
        emit ManualOverridePriceSet(asset_, price_);
    }

    /******************************************************************************************************************************/
    /*** Cover Setters                                                                                                          ***/
    /******************************************************************************************************************************/

    function setMinCoverAmount(address poolManager_, uint256 minCoverAmount_) external override isGovernor {
        minCoverAmount[poolManager_] = minCoverAmount_;
        emit MinCoverAmountSet(poolManager_, minCoverAmount_);
    }

    function setMaxCoverLiquidationPercent(address poolManager_, uint256 maxCoverLiquidationPercent_) external override isGovernor {
        require(maxCoverLiquidationPercent_ <= HUNDRED_PERCENT, "MG:SMCLP:GT_100");
        maxCoverLiquidationPercent[poolManager_] = maxCoverLiquidationPercent_;
        emit MaxCoverLiquidationPercentSet(poolManager_, maxCoverLiquidationPercent_);
    }

    /******************************************************************************************************************************/
    /*** Fee Setters                                                                                                            ***/
    /******************************************************************************************************************************/

    function setPlatformManagementFeeRate(address poolManager_, uint256 platformManagementFeeRate_) external override isGovernor {
        require(platformManagementFeeRate_ <= HUNDRED_PERCENT, "MG:SPMFR:RATE_GT_100");
        platformManagementFeeRate[poolManager_] = platformManagementFeeRate_;
        emit PlatformManagementFeeRateSet(poolManager_, platformManagementFeeRate_);
    }

    function setPlatformOriginationFeeRate(address poolManager_, uint256 platformOriginationFeeRate_) external override isGovernor {
        require(platformOriginationFeeRate_ <= HUNDRED_PERCENT, "MG:SPOFR:RATE_GT_100");
        platformOriginationFeeRate[poolManager_] = platformOriginationFeeRate_;
        emit PlatformOriginationFeeRateSet(poolManager_, platformOriginationFeeRate_);
    }

    function setPlatformServiceFeeRate(address poolManager_, uint256 platformServiceFeeRate_) external override isGovernor {
        require(platformServiceFeeRate_ <= HUNDRED_PERCENT, "MG:SPSFR:RATE_GT_100");
        platformServiceFeeRate[poolManager_] = platformServiceFeeRate_;
        emit PlatformServiceFeeRateSet(poolManager_, platformServiceFeeRate_);
    }

    /******************************************************************************************************************************/
    /*** Contract Control Functions                                                                                             ***/
    /******************************************************************************************************************************/

    function setTimelockWindow(address contract_, bytes32 functionId_, uint128 delay_, uint128 duration_) public override isGovernor {
        timelockParametersOf[contract_][functionId_] = TimelockParameters(delay_, duration_);
        emit TimelockWindowSet(contract_, functionId_, delay_, duration_);
    }

    function setTimelockWindows(address contract_, bytes32[] calldata functionIds_, uint128[] calldata delays_, uint128[] calldata durations_) public override isGovernor {
        for (uint256 i_; i_ < functionIds_.length;) {
            _setTimelockWindow(contract_, functionIds_[i_], delays_[i_], durations_[i_]);
            unchecked { ++i_; }
        }
    }

    function transferOwnedPoolManager(address fromPoolDelegate_, address toPoolDelegate_) external override {
        PoolDelegate storage fromDelegate_ = poolDelegates[fromPoolDelegate_];
        PoolDelegate storage toDelegate_   = poolDelegates[toPoolDelegate_];

        require(fromDelegate_.ownedPoolManager == msg.sender, "MG:TOPM:NOT_AUTHORIZED");
        require(toDelegate_.isPoolDelegate,                   "MG:TOPM:NOT_POOL_DELEGATE");
        require(toDelegate_.ownedPoolManager == address(0),   "MG:TOPM:ALREADY_OWNS");

        fromDelegate_.ownedPoolManager = address(0);
        toDelegate_.ownedPoolManager   = msg.sender;

        emit PoolManagerOwnershipTransferred(fromPoolDelegate_, toPoolDelegate_, msg.sender);
    }

    /******************************************************************************************************************************/
    /*** Schedule Functions                                                                                                     ***/
    /******************************************************************************************************************************/

    function scheduleCall(address contract_, bytes32 functionId_, bytes calldata callData_) external override {
        bytes32 dataHash_ = keccak256(abi.encode(callData_));
        scheduledCalls[msg.sender][contract_][functionId_] = ScheduledCall(block.timestamp, dataHash_);
        emit CallScheduled(msg.sender, contract_, functionId_, dataHash_, block.timestamp);
    }

    function unscheduleCall(address caller_, bytes32 functionId_, bytes calldata callData_) external override {
        delete scheduledCalls[caller_][msg.sender][functionId_];
        emit CallUnscheduled(caller_, msg.sender, functionId_, keccak256(abi.encode(callData_)), block.timestamp);
    }

    function unscheduleCall(address caller_, address contract_, bytes32 functionId_, bytes calldata callData_) external override isGovernor {
        delete scheduledCalls[caller_][contract_][functionId_];
        emit CallUnscheduled(caller_, contract_, functionId_, keccak256(abi.encode(callData_)), block.timestamp);
    }

    function isValidScheduledCall(address caller_, address contract_, bytes32 functionId_, bytes calldata callData_) public override view returns (bool isValid_) {
        ScheduledCall      storage scheduledCall_      = scheduledCalls[caller_][contract_][functionId_];
        TimelockParameters storage timelockParameters_ = timelockParametersOf[contract_][functionId_];

        uint256 timestamp = scheduledCall_.timestamp;
        uint128 delay     = timelockParameters_.delay;
        uint128 duration  = timelockParameters_.duration;

        if (duration == uint128(0)) {
            delay    = defaultTimelockParameters.delay;
            duration = defaultTimelockParameters.duration;
        }

        isValid_ =
            (block.timestamp >= timestamp + delay) &&
            (block.timestamp <= timestamp + delay + duration) &&
            (keccak256(abi.encode(callData_)) == scheduledCall_.dataHash);
    }

    /******************************************************************************************************************************/
    /*** View Functions                                                                                                         ***/
    /******************************************************************************************************************************/

    function getLatestPrice(address asset_) external override view returns (uint256 latestPrice_) {
        // If governor has overridden price because of oracle outage, return overridden price.
        if (manualOverridePrice[asset_] != 0) return manualOverridePrice[asset_];

        address oracle_ = oracleFor[asset_];

        require(oracle_ != address(0), "MG:GLP:ZERO_ORACLE");

        ( uint80 roundId_, int256 price_, , uint256 updatedAt_, uint80 answeredInRound_ ) = IChainlinkAggregatorV3Like(oracle_).latestRoundData();

        require(updatedAt_ != 0,              "MG:GLP:ROUND_NOT_COMPLETE");
        require(answeredInRound_ >= roundId_, "MG:GLP:STALE_DATA");
        require(price_ > int256(0),           "MG:GLP:ZERO_PRICE");

        latestPrice_ = uint256(price_);
    }

    function governor() external view override returns (address governor_) {
        governor_ = admin();
    }

    function isPoolDelegate(address account_) external view override returns (bool isPoolDelegate_) {
        isPoolDelegate_ = poolDelegates[account_].isPoolDelegate;
    }

    function ownedPoolManager(address account_) external view override returns (address poolManager_) {
        poolManager_ = poolDelegates[account_].ownedPoolManager;
    }

    /******************************************************************************************************************************/
    /*** Helper Functions                                                                                                       ***/
    /******************************************************************************************************************************/

    function _setAddress(bytes32 slot_, address value_) private {
        assembly {
            sstore(slot_, value_)
        }
    }

    function _setTimelockWindow(address contract_, bytes32 functionId_, uint128 delay_, uint128 duration_) internal {
        timelockParametersOf[contract_][functionId_] = TimelockParameters(delay_, duration_);
        emit TimelockWindowSet(contract_, functionId_, delay_, duration_);
    }

}

