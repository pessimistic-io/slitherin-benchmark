// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from "./IERC20.sol";
import {AccessControl} from "./AccessControl.sol";
import {ILPVault} from "./ILPVault.sol";
import {SsovAdapter} from "./SsovAdapter.sol";
import {IUniswapV2Pair} from "./IUniswapV2Pair.sol";
import {I1inchAggregationRouterV4} from "./I1inchAggregationRouterV4.sol";
import {ISsovV3} from "./ISsovV3.sol";
import {LPStrategyLib} from "./LPStrategyLib.sol";
import {OneInchZapLib} from "./OneInchZapLib.sol";
import {ZapLib} from "./ZapLib.sol";

abstract contract JonesLPStrategy is AccessControl {
    using SsovAdapter for ISsovV3;
    using OneInchZapLib for I1inchAggregationRouterV4;

    // Represents 100%
    // We are going to store the value that we have on the LP lib
    // to make the bot logic easier
    uint256 public immutable basePercentage;
    // Roles

    // Role used to execute the strategy
    bytes32 public constant KEEPER = bytes32("KEEPER");
    // Role used to configure the strategy
    // and execute manual functions
    bytes32 public constant MANAGER = bytes32("MANAGER");
    // Role used to manage keepers and managers
    bytes32 public constant GOVERNOR = bytes32("GOVERNOR");

    // Struct used to configure the strategy limits and timeframes
    struct StageConfigInput {
        // The % limits of how much collateral can be used to buy primary options
        uint256[] limitsForPrimary;
        // The % limits of how much collateral can be used to buy secondary options
        uint256[] limitsForSecondary;
        // The max % of tokens that can be swapped
        uint256 limitForSwaps;
        // The duration of the stage in seconds. Relative to `initialTime`
        uint256 duration;
    }

    // Struct used to keep track of stages executions
    struct Stage {
        // The % limits of how much collateral can be used to buy primary options
        uint256[] limitsForPrimary;
        // The % of collateral used to buy primary options
        uint256[] usedForPrimary;
        // The % limits of how much collateral can be used to buy secondary options
        uint256[] limitsForSecondary;
        // The % of collateral used to buy secondary options
        uint256[] usedForSecondary;
        // The max % of tokens that can be swapped
        uint256 limitForSwaps;
        // The % of tokens used for swaps
        uint256 usedForSwaps;
        // The duration of the stage in seconds. Relative to `initialTime`
        uint256 duration;
    }

    // To prevent Stack too deep error
    struct StageExecutionInputs {
        // The index of the stage that should be executed
        uint256 expectedStageIndex;
        // The % of primary that can be used to buy options. Each entry represents a strike sorted
        // by "closest-to-itm"
        uint256[] useForPrimary;
        // The % of secondary that can be used to buy options. Each entry represents a strike sorted
        // by "closest-to-itm"
        uint256[] useForSecondary;
        // The expected order of primary strikes sorted by "closest-to-itm"
        uint256[] primaryStrikesOrder;
        // The expected order of secondary strikes sorted by "closest-to-itm"
        uint256[] secondaryStrikesOrder;
        // Whether to include or exclude strikes that are ITM at the moment of execution
        bool ignoreITM;
    }

    // When the strategy starts
    uint256 public initialTime;
    // The initial LP balance borrowed from the vault
    uint256 public initialBalanceSnapshot;
    // Holds a snapshot of the initial collateral that can be used by the primary token
    uint256 public primaryBalanceSnapshot;
    // Holds a snapshot of the initial collateral that can be used by the secondary token
    uint256 public secondaryBalanceSnapshot;

    // The vault that holds LP tokens
    address public vault;

    // The LP token borrowed from the vault
    IERC20 public depositToken;

    // The primary token on the LP
    IERC20 public primary;
    // The secondary token on the LP (will be swapped for primary)
    IERC20 public secondary;

    // The 4 stages
    Stage[4] public stages;

    // The primary Ssov (related to primary token)
    ISsovV3 public primarySsov;
    // The primary Ssov (related to secondary token)
    ISsovV3 public secondarySsov;

    // The primary Ssov epoch
    uint256 public primarySsovEpoch;
    // When the primary Ssov epoch expires
    uint256 public primarySsovEpochExpiry;
    // The secondary Ssov epoch
    uint256 public secondarySsovEpoch;
    // When the secondary Ssov epoch expires
    uint256 public secondarySsovEpochExpiry;

    // One inch router
    I1inchAggregationRouterV4 public oneInch;

    // Pair key  => `true` if the token can be swapped
    mapping(bytes32 => bool) public allowedToSwap;

    // Token address => `true` if the token can be zapped
    mapping(address => bool) public allowedToZap;

    // The name of the strategy
    bytes32 public name;

    bytes32 private _lastPrimarySsovCursor;
    bytes32 private _lastSecondarySsovCursor;

    /**
     * @param _name The name of the strategy
     * @param _oneInch The 1Inch contract address
     * @param _primarySsov The Ssov related to the primary token
     * @param _secondarySsov The Ssov related to the secondary token
     * @param _primaryToken The primary token on the LP pair
     * @param _secondaryToken The secondary token on the LP pair
     * @param _governor The owner of the contract
     * @param _manager The address allowed to configure the strat and run manual functions
     * @param _keeper The address of the bot that will run the strategy
     */
    constructor(
        bytes32 _name,
        I1inchAggregationRouterV4 _oneInch,
        ISsovV3 _primarySsov,
        ISsovV3 _secondarySsov,
        IERC20 _primaryToken,
        IERC20 _secondaryToken,
        address _governor,
        address _manager,
        address _keeper
    ) {
        _isValidAddress(address(_oneInch));
        _isValidAddress(address(_primarySsov));
        _isValidAddress(address(_secondarySsov));
        _isValidAddress(address(_primaryToken));
        _isValidAddress(address(_secondaryToken));
        _isValidAddress(_governor);
        _isValidAddress(_manager);
        _isValidAddress(_keeper);

        name = _name;
        oneInch = _oneInch;

        // 100%
        basePercentage = LPStrategyLib.basePercentage;

        primarySsov = _primarySsov;
        secondarySsov = _secondarySsov;

        address primaryToken = address(_primaryToken);
        address secondaryToken = address(_secondaryToken);

        _setWhitelistPair(primaryToken, secondaryToken, true);

        allowedToZap[primaryToken] = true;
        allowedToZap[secondaryToken] = true;

        primary = _primaryToken;
        secondary = _secondaryToken;

        primarySsovEpochExpiry = type(uint256).max;
        secondarySsovEpochExpiry = type(uint256).max;

        // Access control
        _grantRole(GOVERNOR, _governor);
        _grantRole(MANAGER, _manager);
        _grantRole(KEEPER, _keeper);
    }

    /**
     * @notice Returns the current stages
     */
    function getStages() external view returns (Stage[4] memory) {
        return stages;
    }

    /**
     * @notice Returns the current stage at index `_index`
     * @param _index The index of the stage
     */
    function getStage(uint256 _index) external view returns (Stage memory) {
        return stages[_index];
    }

    /**
     * @notice Returns the timestamps for each stage expiration
     */
    function getStageExpirations() external view returns (uint256[4] memory) {
        uint256[4] memory expirations;

        Stage[4] memory currentStages = stages;
        uint256 referenceTime = initialTime;

        for (uint256 i; i < currentStages.length; i++) {
            expirations[i] = referenceTime + currentStages[i].duration;
        }

        return expirations;
    }

    /**
     * @notice Returns the strikes from the primary ssov sorted by the distance to be in the money
     */
    function getSortedPrimaryStrikes() public view returns (LPStrategyLib.StrikePerformance[] memory) {
        return LPStrategyLib.getSortedStrikes(primarySsov, primarySsovEpoch);
    }

    /**
     * @notice Returns the strikes from the secondary ssov sorted by the distance to be in the money
     */
    function getSortedSecondaryStrikes() public view returns (LPStrategyLib.StrikePerformance[] memory) {
        return LPStrategyLib.getSortedStrikes(secondarySsov, secondarySsovEpoch);
    }

    /**
     * @notice Returns the pair key generated by `_token0` and `_token1`
     * @param _token0 The address of the first token
     * @param _token1 The address of the second token
     */
    function getPairKey(address _token0, address _token1) public pure returns (bytes32) {
        // Create a pair key using the xor between the two token addresses
        return bytes32(uint256(bytes32(bytes20(_token0))) ^ uint256(bytes32(bytes20(_token1))));
    }

    /**
     * @notice Configures all the execution stages
     * @dev It overrides the current configuration
     * @param _stagesConfig The limits and timeframes for all stages
     */
    function configureMultipleStages(StageConfigInput[4] memory _stagesConfig) external returns (Stage[] memory) {
        Stage[] memory configuredStages = new Stage[](4);

        for (uint256 i; i < _stagesConfig.length; i++) {
            configuredStages[i] = configureSingleStage(_stagesConfig[i], i);
        }

        return configuredStages;
    }

    /**
     * @notice Configures a single stage
     * @dev It overrides the current configuration
     * @param _stageConfig The limits and timeframes for the stage at `_index`
     * @param _index The index of the stage to configure
     */
    function configureSingleStage(StageConfigInput memory _stageConfig, uint256 _index)
        public
        onlyRole(MANAGER)
        returns (Stage memory)
    {
        Stage memory stage = stages[_index];

        // Update the configurable variables of the stage
        // to avoid overriding `usedForPrimary ` and `usedForSecondary`
        stage.limitsForPrimary = _stageConfig.limitsForPrimary;
        stage.limitsForSecondary = _stageConfig.limitsForSecondary;
        stage.limitForSwaps = _stageConfig.limitForSwaps;
        stage.duration = _stageConfig.duration;

        // Update the storage with the new configuration
        stages[_index] = stage;

        emit StageConfigured(
            _index, _stageConfig.limitsForPrimary, _stageConfig.limitsForSecondary, _stageConfig.duration
            );

        return stage;
    }

    /**
     * @notice zaps out `_amount` of `depositToken` to an allowed token
     */
    function zapOut(
        uint256 _amount,
        uint256 _token0PairAmount,
        uint256 _token1PairAmount,
        OneInchZapLib.SwapParams calldata _tokenSwap
    )
        external
        onlyRole(MANAGER)
        returns (uint256)
    {
        _canBeZapped(_tokenSwap.desc.srcToken);
        _canBeZapped(_tokenSwap.desc.dstToken);

        if (_tokenSwap.desc.dstReceiver != address(this)) {
            revert InvalidSwapReceiver();
        }

        uint256 amountOut = oneInch.zapOutToOneTokenFromPair(
            address(depositToken), _amount, _token0PairAmount, _token1PairAmount, _tokenSwap
        );

        emit ManualZap(msg.sender, ZapLib.ZapType.ZAP_OUT, _tokenSwap.desc.dstToken, _amount, amountOut);

        return amountOut;
    }

    /**
     * @notice zaps in `_amount` of allowed tokens to `depositToken`
     */
    function zapIn(
        OneInchZapLib.SwapParams calldata _toPairTokens,
        uint256 _token0Amount,
        uint256 _token1Amount,
        uint256 _minPairTokens
    )
        external
        onlyRole(MANAGER)
        returns (uint256)
    {
        _canBeZapped(_toPairTokens.desc.srcToken);
        _canBeZapped(_toPairTokens.desc.dstToken);

        if (_toPairTokens.desc.dstReceiver != address(this)) {
            revert InvalidSwapReceiver();
        }

        uint256 amountOut =
            oneInch.zapIn(_toPairTokens, address(depositToken), _token0Amount, _token1Amount, _minPairTokens);

        emit ManualZap(
            msg.sender, ZapLib.ZapType.ZAP_IN, _toPairTokens.desc.srcToken, _toPairTokens.desc.amount, amountOut
            );

        return amountOut;
    }

    /**
     * @notice Swaps allowed tokens using 1Inch
     */
    function swap(OneInchZapLib.SwapParams calldata _swapParams) external onlyRole(MANAGER) returns (uint256) {
        _canBeSwapped(_swapParams.desc.srcToken, _swapParams.desc.dstToken);

        if (_swapParams.desc.dstReceiver != address(this)) {
            revert InvalidSwapReceiver();
        }

        IERC20(_swapParams.desc.srcToken).approve(address(oneInch), _swapParams.desc.amount);
        (uint256 output,) = oneInch.swap(_swapParams.caller, _swapParams.desc, _swapParams.data);

        emit ManualSwap(
            msg.sender, _swapParams.desc.srcToken, _swapParams.desc.dstToken, _swapParams.desc.amount, output
            );

        return output;
    }

    /**
     * @notice Purchases `_amount` of `_ssov` options on `_strikeIndex` strike
     * @param _ssov The Ssov where the options are going to be purchased
     * @param _strikeIndex The index of the strike to buy
     * @param _amount The amount of options to purchase
     */
    function purchaseOption(ISsovV3 _ssov, uint256 _strikeIndex, uint256 _amount) public onlyRole(MANAGER) {
        if (_ssov != primarySsov && _ssov != secondarySsov) {
            revert SsovNotSupported();
        }

        IERC20 token = _ssov.collateralToken();

        token.approve(address(_ssov), type(uint256).max);

        _ssov.purchaseOption(_strikeIndex, _amount, address(this));

        token.approve(address(_ssov), 0);

        emit ManualOptionPurchase(msg.sender, address(_ssov), _strikeIndex, _amount);
    }

    /**
     * @notice Settles `_ssovEpoch` on `_ssov` using `_ssovStrikes`
     * @param _ssov The Ssov to settle
     * @param _ssovEpoch The epoch to settle
     * @param _ssovStrikes The strikes to settle
     */
    function settleEpoch(ISsovV3 _ssov, uint256 _ssovEpoch, uint256[] memory _ssovStrikes) public onlyRole(MANAGER) {
        if (_ssov != primarySsov && _ssov != secondarySsov) {
            revert SsovNotSupported();
        }

        _ssov.settleEpoch(address(this), _ssovEpoch, _ssovStrikes);

        emit ManualEpochSettlement(msg.sender, address(_ssov), _ssovEpoch, _ssovStrikes);
    }

    /**
     * @notice Grants the `GOVERNOR` role to `_newGovernor` while it revokes it from the caller
     * @param _newGovernor The address that will be granted with the `GOVERNOR` role
     */
    function transferOwnership(address _newGovernor) external onlyRole(GOVERNOR) {
        _isValidAddress(_newGovernor);

        _revokeRole(GOVERNOR, msg.sender);
        _grantRole(GOVERNOR, _newGovernor);

        emit OwnershipTrasnferred(msg.sender, _newGovernor);
    }

    /**
     * @notice Grants the `MANAGER` role to `_newManager`
     * @param _newManager The address that will be granted with the `MANAGER` role
     */
    function addManager(address _newManager) external onlyRole(GOVERNOR) {
        _isValidAddress(_newManager);

        _grantRole(MANAGER, _newManager);

        emit ManagerAdded(msg.sender, _newManager);
    }

    /**
     * @notice Revokes the `MANAGER` role from `_manager`
     * @param _manager The address that will be revoked
     */
    function removeManager(address _manager) external onlyRole(GOVERNOR) {
        _revokeRole(MANAGER, _manager);

        emit ManagerRemoved(msg.sender, _manager);
    }

    /**
     * @notice Grants the `KEEPER` role to `_newKeeper`
     * @param _newKeeper The address that will be granted with the `KEEPER` role
     */
    function addKeeper(address _newKeeper) external onlyRole(GOVERNOR) {
        _isValidAddress(_newKeeper);

        _grantRole(KEEPER, _newKeeper);

        emit KeeperAdded(msg.sender, _newKeeper);
    }

    /**
     * @notice Revokes the `KEEPER` role from `_keeper`
     * @param _keeper The address that will be revoked
     */
    function removeKeeper(address _keeper) external onlyRole(GOVERNOR) {
        _revokeRole(KEEPER, _keeper);

        emit KeeperRemoved(msg.sender, _keeper);
    }

    /**
     * @notice Enables the swap between `_token0` and `_token1`
     * @dev This will also enables the swap between `_token1` and `_token0`
     * @param _token0 The address of the first asset
     * @param _token1 The address of the second asset
     */
    function enablePairSwap(address _token0, address _token1) external onlyRole(GOVERNOR) returns (bytes32) {
        bytes32 key = _setWhitelistPair(_token0, _token1, true);

        emit PairSwapEnabled(msg.sender, _token0, _token1, key);

        return key;
    }

    /**
     * @notice Disables the swap between `_token0` and `_token1`
     * @dev This will also disable the swap between `_token1` and `_token0`
     * @param _token0 The address of the first asset
     * @param _token1 The address of the second asset
     */
    function disablePairSwap(address _token0, address _token1) external onlyRole(GOVERNOR) returns (bytes32) {
        bytes32 key = _setWhitelistPair(_token0, _token1, false);

        emit PairSwapDisabled(msg.sender, _token0, _token1, key);

        return key;
    }

    /**
     * @notice Allows to zap `_token` for `depositToken`
     * @param _token The address of the asset
     */
    function enableTokenZap(address _token) external onlyRole(GOVERNOR) {
        allowedToZap[_token] = true;

        emit ZapEnabled(msg.sender, _token);
    }

    /**
     * @notice Disables zapping `_token` for `depositToken`
     * @param _token The address of the asset
     */
    function disableTokenZap(address _token) external onlyRole(GOVERNOR) {
        allowedToZap[_token] = false;

        emit ZapDisabled(msg.sender, _token);
    }

    /**
     * @notice Sets the vault and deposit token address
     * @param _newVault the address of the vault
     */
    function setVault(address _newVault) external onlyRole(GOVERNOR) {
        _isValidAddress(_newVault);

        vault = _newVault;
        depositToken = ILPVault(_newVault).depositToken();
    }

    /**
     * @notice Sets the address for the primary ssov
     * @param _primarySsov the new ssov address
     */
    function setPrimarySsov(address _primarySsov) external onlyRole(GOVERNOR) {
        _isValidAddress(_primarySsov);

        primarySsov = ISsovV3(_primarySsov);
    }

    /**
     * @notice Sets the address for the secondary ssov
     * @param _secondarySsov the new ssov address
     */
    function setSecondarySsov(address _secondarySsov) external onlyRole(GOVERNOR) {
        _isValidAddress(_secondarySsov);

        secondarySsov = ISsovV3(_secondarySsov);
    }

    /**
     * @notice Moves assets from the strategy to `_to`
     * @param _assets An array of IERC20 compatible tokens to move out from the strategy
     * @param _withdrawNative `true` if we want to move the native asset from the strategy
     */
    function emergencyWithdraw(address _to, address[] memory _assets, bool _withdrawNative)
        external
        onlyRole(GOVERNOR)
    {
        _isValidAddress(_to);

        for (uint256 i; i < _assets.length; i++) {
            IERC20 asset = IERC20(_assets[i]);
            uint256 assetBalance = asset.balanceOf(address(this));

            // No need to transfer
            if (assetBalance == 0) {
                continue;
            }

            // Transfer the ERC20 tokens
            asset.transfer(_to, assetBalance);
        }

        uint256 nativeBalance = address(this).balance;

        // Nothing else to do
        if (_withdrawNative && nativeBalance > 0) {
            // Transfer the native currency
            payable(_to).transfer(nativeBalance);
        }

        emit EmergencyWithdrawal(msg.sender, _to, _assets, _withdrawNative ? nativeBalance : 0);
    }

    /**
     * @notice To enable/disable swaps between `_token0` and `_token1`
     * @param _token0 The address of the first asset
     * @param _token1 The address of the second asset
     * @param _enable `true` to enable swaps, `false` to disable
     */
    function _setWhitelistPair(address _token0, address _token1, bool _enable) internal returns (bytes32) {
        bytes32 key = getPairKey(_token0, _token1);

        allowedToSwap[key] = _enable;

        return key;
    }

    /**
     * @notice Reverts if `_input` cannot be swapped to `_output`
     * @param _input The input token
     * @param _output The output token
     */
    function _canBeSwapped(address _input, address _output) internal view {
        bytes32 key = getPairKey(_input, _output);

        // 0 means that _input = _ouput
        if (key == bytes32(0)) {
            revert InvalidSwap();
        }

        if (!allowedToSwap[key]) {
            revert SwapIsNotAllowed();
        }
    }

    /**
     * @notice Reverts if `_input` cannot be zapped
     * @param _input The input token
     */
    function _canBeZapped(address _input) internal view {
        if (!allowedToZap[_input]) {
            revert ZapIsNotAllowed();
        }
    }

    /**
     * @notice Reverts if `_addr` is `address(0)`
     */
    function _isValidAddress(address _addr) internal pure {
        if (_addr == address(0)) {
            revert InvalidAddress();
        }
    }

    /**
     * @notice Reverts if the strategy already expired according to the configured stages
     */
    function _notExpired() internal view {
        uint256 expiration = initialTime + stages[3].duration;

        if (block.timestamp > expiration) {
            revert StrategyAlreadyExpired();
        }
    }

    /**
     * @notice Executed after the strategy is settled
     */
    function _afterSettlement() internal virtual {
        emit Settlement(initialBalanceSnapshot);

        // Reset the state
        initialTime = 0;
        initialBalanceSnapshot = 0;
        primaryBalanceSnapshot = 0;
        secondaryBalanceSnapshot = 0;
        primarySsovEpoch = 0;
        secondarySsovEpoch = 0;
        primarySsovEpochExpiry = type(uint256).max;
        secondarySsovEpochExpiry = type(uint256).max;

        Stage[4] storage currentStages = stages;

        // Reset stages state but keep configuration
        for (uint256 i; i < currentStages.length; i++) {
            delete stages[i].usedForPrimary;
            delete stages[i].usedForSecondary;
            stages[i].usedForSwaps = 0;
        }
    }

    /**
     * @notice Takes a snapshot of the initial time and Ssov data
     */
    function _afterInit(uint256 _primaryBalanceSnapshot, uint256 _secondaryBalanceSnapshot) internal {
        // Set the initial time used as reference for stage expiration
        initialTime = block.timestamp;

        ISsovV3 ssov = primarySsov;
        uint256 ssovEpoch = ssov.currentEpoch();

        // Snapshot ssov epochs and expirations
        primarySsovEpoch = ssovEpoch;

        if (keccak256(abi.encodePacked(address(ssov), ssovEpoch)) == _lastPrimarySsovCursor) {
            revert InitOnSameSsovEpoch();
        }

        ISsovV3.EpochData memory primaryEpochData = ssov.getEpochData(ssovEpoch);
        primarySsovEpochExpiry = primaryEpochData.expiry;
        uint256[] memory primaryStrikes = primaryEpochData.strikes;
        _lastPrimarySsovCursor = keccak256(abi.encodePacked(address(ssov), ssovEpoch));

        ssov = secondarySsov;
        ssovEpoch = ssov.currentEpoch();

        if (keccak256(abi.encodePacked(address(ssov), ssovEpoch)) == _lastSecondarySsovCursor) {
            revert InitOnSameSsovEpoch();
        }

        secondarySsovEpoch = ssovEpoch;
        ISsovV3.EpochData memory secondaryEpochData = ssov.getEpochData(ssovEpoch);
        secondarySsovEpochExpiry = secondaryEpochData.expiry;
        uint256[] memory secondaryStrikes = secondaryEpochData.strikes;
        _lastSecondarySsovCursor = keccak256(abi.encodePacked(address(ssov), ssovEpoch));

        for (uint256 i; i < stages.length; i++) {
            stages[i].usedForSecondary = new uint256[](secondaryStrikes.length);
            stages[i].usedForPrimary = new uint256[](primaryStrikes.length);
        }

        primaryBalanceSnapshot = _primaryBalanceSnapshot;
        secondaryBalanceSnapshot = _secondaryBalanceSnapshot;
    }

    /**
     * @notice Executed after a stage execution
     * @param _stageIndex The stage that was executed
     */
    function _afterExecution(uint256 _stageIndex, Stage memory _stage) internal {
        // Snapshot the % of `secondary` options bought
        // And the % of assets swapped to buy `primary` options
        stages[_stageIndex].usedForSecondary = _stage.usedForSecondary;
        stages[_stageIndex].usedForPrimary = _stage.usedForPrimary;
        stages[_stageIndex].usedForSwaps = _stage.usedForSwaps;

        emit Execution(_stageIndex, _stage.usedForSecondary, _stage.usedForPrimary);
    }

    event Settlement(uint256 initialBalance);
    event Execution(uint256 indexed stage, uint256[] usedForSecondary, uint256[] usedForPrimary);
    event StageConfigured(
        uint256 indexed stage, uint256[] limitsForPrimary, uint256[] limitsForSecondary, uint256 duration
    );

    event ManualBorrow(address indexed caller, uint256 borrowed);
    event ManualRepay(address indexed caller, uint256 repaid);
    event ManualZap(
        address indexed caller, ZapLib.ZapType indexed zapType, address indexed input, uint256 amount, uint256 amountOut
    );
    event ManualSwap(
        address indexed caller, address indexed input, address indexed output, uint256 amount, uint256 amountOut
    );
    event ManualOptionPurchase(
        address indexed caller, address indexed ssov, uint256 indexed strikeIndex, uint256 amount
    );
    event ManualEpochSettlement(address indexed caller, address indexed ssov, uint256 indexed epoch, uint256[] strikes);

    event OwnershipTrasnferred(address indexed oldGovernor, address indexed newGovernor);
    event ManagerAdded(address indexed caller, address indexed newManager);
    event ManagerRemoved(address indexed caller, address indexed removedManager);
    event KeeperAdded(address indexed caller, address indexed newKeeper);
    event KeeperRemoved(address indexed caller, address indexed removedKeeper);
    event PairSwapEnabled(address indexed calller, address indexed token0, address indexed token1, bytes32 pairKey);
    event ZapEnabled(address indexed caller, address indexed token);
    event ZapDisabled(address indexed caller, address indexed token);
    event PairSwapDisabled(address indexed caller, address indexed token0, address indexed token1, bytes32 pairKey);
    event EmergencyWithdrawal(address indexed caller, address indexed receiver, address[] tokens, uint256 nativeBalance);

    error StrategyAlreadyInitialized();
    error StrategyNotInitialized();
    error AboveSwapLimit();
    error SettleBeforeExpiry();
    error SwapIsNotAllowed();
    error InvalidSwap();
    error ZapIsNotAllowed();
    error SsovNotSupported();
    error InvalidAddress();
    error StrategyAlreadyExpired();
    error ExecutingUnexpectedStage(uint256 expected, uint256 actual);
    error InvalidSwapReceiver();
    error InitOnSameSsovEpoch();
}

