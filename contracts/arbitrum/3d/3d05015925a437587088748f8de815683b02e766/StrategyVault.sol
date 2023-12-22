// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "./Ownable.sol";
import {ERC4626} from "./ERC4626.sol";
import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {IErrors} from "./IErrors.sol";
import {IEarthquake} from "./IEarthquake.sol";
import {IStrategyVault} from "./IStrategyVault.sol";
import {IHook} from "./IHook.sol";
import {IQueueContract} from "./IQueueContract.sol";
import {VaultGetter} from "./VaultGetter.sol";
import {PositionSizer} from "./PositionSizer.sol";
import {HookChecker} from "./HookChecker.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {ERC1155Holder} from "./ERC1155Holder.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";

// NOTE: Planning to deposit liquidity to tackle the inflation attack of ERC4626
contract StrategyVault is
    ERC4626,
    ERC1155Holder,
    Ownable,
    ReentrancyGuard,
    IErrors
{
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;
    using HookChecker for uint16;

    struct Position {
        address[] vaults;
        uint256[] epochIds;
        uint256[] amounts;
    }

    struct QueueDeposit {
        address receiver;
        uint256 assets;
    }

    struct QueueCache {
        uint256 totalSupply;
        uint128 totalAssets;
        uint128 queued;
    }

    struct QueueItem {
        uint128 deploymentId;
        uint128 shares;
    }

    struct QueueInfo {
        uint256 shares;
        QueueItem[] queue;
    }

    struct Market {
        IEarthquake vault;
        address emissionsToken;
        uint256 marketId;
    }

    struct Hook {
        IHook addr;
        uint16 command;
    }

    enum UpdateAction {
        AppendVaults,
        ReplaceVaults,
        RemoveVaults,
        DeleteVaults
    }

    /// @notice Precision used to scale up emissions
    uint256 public constant PRECISION = 1e18;

    /// @notice Emissions accumulated per share used to calculate claimable per user
    uint256 public accEmissionPerShare;

    /// @notice Struct with hook contract address and byte encoded command
    Hook public hook;

    /// @notice Struct with list of vaults, epochIds, and amounts for the active position
    Position activePosition;

    /// @notice funds deployed to Y2K vaults state
    bool public fundsDeployed;

    /// @notice 1 = equal weight, 2 = fixed weight, 3 = threshold weight
    uint8 public weightStrategy;

    /// @notice proportion of vault funds to use in each deployment to strategy (max. 99.99%)
    uint16 public weightProportion;

    /// @notice maximum size of deposits to be pulled
    uint16 public maxQueuePull;

    /// @notice deployment id for funds
    uint128 public deploymentId;

    /// @notice interface of contract used to hold queued deposits funds
    IQueueContract public queueContract;

    /// @notice minimum deposit amount when queuing deposit
    uint128 public minDeposit;

    /// @notice total amount of assets queued for deposit
    uint128 public totalQueuedDeposits;

    /// @notice total amount of asset queued for withdrawal
    uint256 public queuedWithdrawalTvl;

    /// @notice list of Y2K vaults to use in fund deployment
    address[] public vaultList;

    /// @notice weights assigned to vault (zeroed when using equal weight or threshold return appended in threshold weight)
    uint256[] public vaultWeights;

    /// @notice struct information about queued deposits (incl. receiver and assets)
    QueueDeposit[] public queueDeposits;

    /// @notice mapping of vaults to withdraw queue information
    mapping(address => QueueInfo) public withdrawQueue;

    /// @notice cached info for totalSupply and totalAssets used when processed queuedWithdrawals where current deploy id has passed (i.e. assets + supply will mismatch)
    mapping(uint256 => QueueCache) public queueCache;

    /// @notice total amount of shares queued for withdrawal
    mapping(uint256 => uint256) public totalQueuedShares;

    /// @notice total emissions unclaimable by user (used to calculate claimable)
    mapping(address => int256) public userEmissionDebt;

    event FundsDeployed(
        address[] vaults,
        uint256[] epochIds,
        uint256[] amounts
    );
    event FundsWithdrawn(
        address[] vaults,
        uint256[] epochIds,
        uint256[] amounts,
        uint256[] receivedAmounts,
        uint256 vaultBalance
    );
    event BulkDeposit(
        address sender,
        address[] receivers,
        uint256[] assets,
        uint256[] shares
    );
    event DepositQueued(address sender, address receiver, uint256 amount);
    event WithdrawalQueued(address sender, uint256 amount);
    event WithdrawalUnqueued(address sender, uint256 amount);
    event VaultsUpdated(address sender, address[] vaults);
    event WeightStrategyUpdated(
        uint8 weightId,
        uint16 proportion,
        uint256[] fixedWeights
    );
    event MinDepositUpdated(uint256 newMin);
    event HookUpdated(Hook newHook);
    event MaxQueueSizeUpdated(uint16 newMax);
    event EmissionsUpdated(
        uint256 deploymentId,
        uint256 totalSupply,
        uint256 totalEmissionsBalance,
        uint256 accEmissionsPerShare
    );
    event EmissionsClaimed(address sender, address receiver, uint256 amount);

    /**
        @notice Constructor initializing the queueContract, hook, emissions token, maxPull, minDeposit, asset, name, and symbol
        @dev ERC4626 is initialiazed meaning if the _asset does not have decimals it will revert
     */
    constructor(
        IQueueContract _queueContract,
        Hook memory _hook,
        ERC20 _emissionToken,
        uint16 _maxQueuePull,
        uint128 _minDeposit,
        ERC20 _asset,
        string memory _name,
        string memory _symbol
    ) ERC4626(_asset, _emissionToken, _name, _symbol) {
        if (address(_queueContract) == address(0)) revert InvalidInput();
        if (address(_emissionToken) == address(0)) revert InvalidInput();
        if (_maxQueuePull == 0) revert InvalidQueueSize();
        if (_minDeposit == 0) revert InvalidInput();

        queueContract = _queueContract;
        hook = _hook;
        maxQueuePull = _maxQueuePull;
        minDeposit = _minDeposit;
    }

    //////////////////////////////////////////////
    //                 ADMIN - CONFIG           //
    //////////////////////////////////////////////
    /**
        @notice Update the vault list
        @dev 0 = appendVaults, 1 = replaceVaults, 2 = removeVaults(s), and 3 = deleteVaults
        @dev Editing vaults whilst deployed will not impact closePosition as we store position
        @param vaults Array of vaults to update the list with
        @param updateAction Action to perform on the vault list
        @return newVaultList Updated vault list
     */
    function updateActiveList(
        address[] calldata vaults,
        UpdateAction updateAction
    ) external onlyOwner returns (address[] memory newVaultList) {
        if (updateAction != UpdateAction.DeleteVaults)
            VaultGetter.checkVaultsValid(vaults);

        if (updateAction == UpdateAction.AppendVaults)
            newVaultList = _appendVaults(vaults);
        else if (updateAction == UpdateAction.ReplaceVaults)
            newVaultList = _replaceVaults(vaults);
        if (updateAction == UpdateAction.RemoveVaults)
            newVaultList = _removeVaults(vaults);
        else if (updateAction == UpdateAction.DeleteVaults) {
            delete vaultList;
        }

        emit VaultsUpdated(msg.sender, newVaultList);
    }

    /**
        @notice Update the weight strategy used when deploying funds
        @dev 1 = EqualWeight, 2 = FixedWeight, 3 = ThresholdWeight
        @dev Max weight set to 9_999 to avoid the zero issue i.e. totalSupply() > 0 and totalAssets() = 0
        creates issues when funds deposited with ERC4626 logic
        @dev Threshold weight inputs an array that includes marketId for vault (V1 vaults) or is empty (V2 vaults) and threshold return is appended
        @param weightId Weight strategy id to update
        @param proportion Proportion of funds to use for the weight strategy (max 9_999)
        @param fixedWeights Array of fixed weights to use for each vault (in order of vaultList)
     */
    function setWeightStrategy(
        uint8 weightId,
        uint16 proportion,
        uint256[] calldata fixedWeights
    ) external onlyOwner {
        if (weightId == 0) revert InvalidWeightId();
        if (proportion > 9_999) revert InvalidInput();
        if (weightId > strategyCount()) revert InvalidWeightId();
        if (fixedWeights.length > 0) {
            if (weightId == 2) {
                if (fixedWeights.length != vaultList.length)
                    revert InvalidLengths();
                _checkWeightLimit(fixedWeights);
            } else if (
                weightId == 3 && fixedWeights.length != vaultList.length + 1
            ) revert InvalidLengths();
        }

        weightStrategy = weightId;
        weightProportion = proportion;
        vaultWeights = fixedWeights;
        emit WeightStrategyUpdated(weightId, proportion, fixedWeights);
    }

    /**
        @notice Update the minimum deposit size for queued deposits
        @param newMin New minimum deposit size
     */
    function updateMinDeposit(uint128 newMin) external onlyOwner {
        if (newMin == 0) revert InvalidInput();
        minDeposit = newMin;
        emit MinDepositUpdated(newMin);
    }

    /**
        @notice Update the hook struct
        @param newHook Struct with hook address and byte command
     */
    function updateHook(Hook calldata newHook) external onlyOwner {
        if (address(newHook.addr) == address(0)) revert InvalidInput();
        hook = newHook;
        emit HookUpdated(newHook);
    }

    /**
        @notice Update the max queue size (used to check if queue can be automatically pulled)
        @param newSize New max queue size
     */
    function updateMaxQueueSize(uint16 newSize) external onlyOwner {
        if (newSize == 0) revert InvalidQueueSize();
        maxQueuePull = newSize;
        emit MaxQueueSizeUpdated(newSize);
    }

    /**
        @notice Clear a fixed amount of deposits in the queue
        @dev Funds queued are kept in the queue contract until they are cleared
        @param queueSize Number of deposits to clear
        @return pulledAmount Amount of assets pulled from the queue
     */
    function clearQueuedDeposits(
        uint256 queueSize
    ) external onlyOwner returns (uint256 pulledAmount) {
        address[] memory receivers = new address[](queueSize);
        uint256[] memory assets = new uint256[](queueSize);
        uint256[] memory sharesReceived = new uint256[](queueSize);
        uint256 depositLength = queueDeposits.length;
        uint256 cachedSupply = totalSupply;
        uint256 cachedAssets = totalAssets();
        uint256 count;

        for (uint256 i = depositLength; i > depositLength - queueSize; ) {
            QueueDeposit memory qDeposit = queueDeposits[i - 1];
            uint256 shares = qDeposit.assets.mulDivDown(
                cachedSupply,
                cachedAssets
            );

            _updateUserEmissions(qDeposit.receiver, shares, true);

            pulledAmount += qDeposit.assets;
            queueDeposits.pop();

            receivers[count] = qDeposit.receiver;
            assets[count] = qDeposit.assets;
            sharesReceived[count] = shares;

            _mint(qDeposit.receiver, shares);

            unchecked {
                i--;
                count++;
            }
        }

        totalQueuedDeposits -= uint128(pulledAmount);
        queueContract.transferToStrategy(pulledAmount);
        emit BulkDeposit(msg.sender, receivers, assets, sharesReceived);

        if (hook.command.shouldCallAfterDeposit()) {
            asset.safeApprove(address(hook.addr), pulledAmount);
            hook.addr.afterDeposit(pulledAmount);
        }
    }

    //////////////////////////////////////////////
    //             ADMIN - VAULT MGMT           //
    //////////////////////////////////////////////
    /**
        @notice Deploy funds to Y2K vaults based on weightStrategy and proportion
     */
    function deployPosition() external onlyOwner {
        if (fundsDeployed) revert FundsAlreadyDeployed();

        // Hook to conduct any actions before availableAmount calculated
        uint16 command = hook.command;
        if (command.shouldCallBeforeDeploy()) hook.addr.beforeDeploy();

        // Checking available assets and building position info
        (
            uint256[] memory amounts,
            uint256[] memory epochIds,
            uint256[] memory vaultType,
            address[] memory vaults
        ) = fetchDeployAmounts();

        fundsDeployed = true;
        _deployPosition(vaults, epochIds, amounts, vaultType);
        if (command.shouldCallAfterDeploy()) hook.addr.afterDeploy();
    }

    /**
        @notice Close position on Y2K vaults redeeming deployed funds and earnings
        @dev When losing on collateral side of Y2K, a proportion of assets is returned along with emissions earned
        When losing on premium side of Y2K, only emissions are earned
        @dev Casting totalAssets() to uint128 where max is 2 ** 128 - 1 (3.4e38)
        @dev afterCloseTransferAssets() returns an ERC20[] for _transferAssets function
     */
    function closePosition() external onlyOwner {
        if (!fundsDeployed) revert FundsNotDeployed();
        uint256 emissionBalance = emissionToken.balanceOf(address(this));
        Position memory position = activePosition;
        delete activePosition;

        uint16 command = hook.command;
        if (command.shouldCallBeforeClose()) hook.addr.beforeClose();

        _closePosition(position);

        if (command.shouldTransferAfterClose())
            _transferAssets(hook.addr.afterCloseTransferAssets());
        if (command.shouldCallAfterClose()) hook.addr.afterClose();

        // Resolving queueing logic - after hook to ensure balances are correct
        queuedWithdrawalTvl += previewRedeem(totalQueuedShares[deploymentId]);

        // Vault logic
        fundsDeployed = false;
        deploymentId += 1;

        // Resolving emission updates
        _updateVaultEmissions(emissionBalance);

        uint256 deployId = deploymentId - 1;
        if (queueCache[deployId].queued == 1) {
            queueCache[deployId].totalSupply = totalSupply;
            queueCache[deployId].totalAssets = uint128(totalAssets());
        }

        uint256 queueLength = queueDeposits.length;
        if (queueLength > 0 && queueLength < maxQueuePull)
            _pullQueuedDeposits(queueLength);
    }

    //////////////////////////////////////////////
    //                 PUBLIC                   //
    //////////////////////////////////////////////
    /**  
        @notice Deposit assets to strategy if funds not deployed else queue deposit
        @param assets Amount of assets to deposit
        @param receiver Address to receive shares
        @return shares Amount of shares received
    */
    function deposit(
        uint256 assets,
        address receiver
    ) external override nonReentrant returns (uint256 shares) {
        if (fundsDeployed) return _queueDeposit(receiver, assets);

        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");
        _updateUserEmissions(receiver, shares, true);

        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(this), assets);
        _mint(receiver, shares);
        emit Deposit(msg.sender, receiver, assets, shares);

        if (hook.command.shouldCallAfterDeposit()) {
            asset.safeApprove(address(hook.addr), assets);
            hook.addr.afterDeposit(assets);
        }
    }

    /**  
        @notice Withdraw assets from strategy if funds not deployed
        @dev Can not be called if funds have been queued for withdrawal
        @param shares Amount of shares to withdraw
        @param receiver Address to receive assets
        @param owner Address of shares owner
    */
    function withdraw(
        uint256 shares,
        address receiver,
        address owner
    ) external override nonReentrant returns (uint256 assets) {
        if (fundsDeployed) revert FundsAlreadyDeployed();
        if (withdrawQueue[owner].shares > 0) revert QueuedWithdrawalPending();

        assets = previewRedeem(shares);
        if (hook.command.shouldCallBeforeWithdraw()) {
            hook.addr.beforeWithdraw(assets);
        }

        _withdraw(assets, shares, receiver, owner, false);
        _updateUserEmissions(receiver, shares, false);
    }

    /**
        @notice Claim Y2K emissions for user
        @dev Approach inspired by SushiSwap MasterChefV2
        @dev Sender is always used as owner
        @param receiver Address to receive emissions
     */
    function claimEmissions(
        address receiver
    ) external returns (uint256 emissions) {
        int256 accEmissions = int256(
            (balanceOf[msg.sender] * accEmissionPerShare) / PRECISION
        );

        int256 emissionDebt = userEmissionDebt[msg.sender];
        if (accEmissions - emissionDebt <= 0) revert NegativeEmissions();
        emissions = uint256(accEmissions - emissionDebt);

        userEmissionDebt[msg.sender] = accEmissions;

        if (emissions > 0) emissionToken.safeTransfer(receiver, emissions);
        emit EmissionsClaimed(msg.sender, receiver, emissions);
    }

    /**
        @notice Withdraw assets that have been queued for withdrawal
        @dev Can only be called if funds have been queued for withdrawal
        @param receiver Address to receive assets
        @param owner Address of shares owner
     */
    function withdrawFromQueue(
        address receiver,
        address owner
    ) external nonReentrant returns (uint256 assets) {
        if (withdrawQueue[owner].shares == 0) revert NoQueuedWithdrawals();
        uint256 queueId = withdrawQueue[owner]
            .queue[withdrawQueue[owner].queue.length - 1]
            .deploymentId;
        if (queueId == deploymentId) revert PositionClosePending();

        uint256 shares;
        (assets, shares) = _previewQueuedWithdraw(owner);
        if (hook.command.shouldCallBeforeWithdraw()) {
            hook.addr.beforeWithdraw(assets);
        }

        _withdraw(assets, shares, receiver, owner, true);
        _updateUserEmissions(receiver, shares, false);
    }

    /**
        @notice Request an amount of shares to be queued for withdrawal
        @dev Shares are queued as the conversion is unknown while funds are deployed
        @param shares Amount of shares to queue for withdrawal
     */
    function requestWithdrawal(uint256 shares) external {
        if (!fundsDeployed) revert FundsNotDeployed();
        if (shares > balanceOf[msg.sender] - withdrawQueue[msg.sender].shares)
            revert InsufficientBalance();

        uint256 deployId = deploymentId;
        totalQueuedShares[deployId] += shares;
        withdrawQueue[msg.sender].shares += shares;
        uint256 length = withdrawQueue[msg.sender].queue.length;

        if (
            length > 0 &&
            withdrawQueue[msg.sender].queue[length - 1].deploymentId == deployId
        ) withdrawQueue[msg.sender].queue[length - 1].shares += uint128(shares);
        else
            withdrawQueue[msg.sender].queue.push(
                QueueItem(uint128(deployId), uint128(shares))
            );

        if (queueCache[deployId].queued == 0) queueCache[deployId].queued = 1;
        emit WithdrawalQueued(msg.sender, shares);
    }

    /**
        @notice Unqueue an amount of shares that have been queued for withdrawal
        @dev Only allowed to unqueue shares that have been queued with current deploymentId i.e. before position closed
        as hooks may adjust accounting
        @param shares Amount of shares to unqueue
     */
    function unrequestWithdrawal(uint256 shares) external {
        if (shares == 0) revert InvalidInput();
        uint256 length = withdrawQueue[msg.sender].queue.length;
        if (length == 0) revert NoQueuedWithdrawals();

        uint256 deployId = deploymentId;
        QueueItem memory item = withdrawQueue[msg.sender].queue[length - 1];
        if (item.deploymentId != deployId) revert InvalidQueueId();
        if (shares > item.shares) revert InsufficientBalance();

        totalQueuedShares[deployId] -= shares;
        withdrawQueue[msg.sender].shares -= shares;

        if (totalQueuedShares[deployId] == 0) delete queueCache[deployId];
        uint256 remaining = item.shares - shares;
        if (remaining == 0) withdrawQueue[msg.sender].queue.pop();
        else
            withdrawQueue[msg.sender].queue[length - 1].shares = uint128(
                remaining
            );

        emit WithdrawalUnqueued(msg.sender, shares);
    }

    //////////////////////////////////////////////
    //                 GETTERS                  //
    //////////////////////////////////////////////
    /**
        @notice Gets the count of strategies in the position sizer being used
        @return Strategy count
     */
    function strategyCount() public pure returns (uint256) {
        return PositionSizer.strategyCount();
    }

    /**
        @notice Checks if the vaults in the vaultList are valid and returns active list
        @return activeVaults List of active vaults
     */
    function validActiveVaults()
        public
        view
        returns (address[] memory activeVaults)
    {
        (, activeVaults, ) = VaultGetter.fetchEpochIds(vaultList);
    }

    /**
        @notice Gets the total assets of the vault
        @dev Total assets equals balanceOf(underlying) with simple vaults but with LP vaults
        the deposit asset and balance asset will differ e.g. aTokens are balance asset in Aave hook.
        In these cases, the hook will be queried to return the totalAssets for this calculation
        @return Total assets
     */
    function totalAssets() public view override returns (uint256) {
        if (!hook.command.shouldCallForTotalAssets())
            return asset.balanceOf(address(this));
        else return hook.addr.totalAssets();
    }

    /**
        @notice Gets the total Y2K balance/emissions available to be claimed in the whole vault
        @return Total emissions
     */
    function totalEmissions() public view override returns (uint256) {
        return emissionToken.balanceOf(address(this));
    }

    /**
        @notice Gets list of active vaults being deployed to
        @return Array of vault addresses
     */
    function fetchVaultList() external view returns (address[] memory) {
        return vaultList;
    }

    /**
        @notice Gets the vault weights being used in the position sizer (in order of the vaults)
        @return Array of vault weights
     */
    function fetchVaultWeights() external view returns (uint256[] memory) {
        return vaultWeights;
    }

    function fetchListAndWeights()
        external
        view
        returns (address[] memory, uint256[] memory weights)
    {
        weights = new uint256[](vaultList.length);
        if (weightStrategy == 1 || weightStrategy == 3) {
            for (uint256 i; i < vaultList.length; ) {
                weights[i] = 10_000 / vaultList.length;
                unchecked {
                    i++;
                }
            }
        } else {
            weights = vaultWeights;
        }
        return (vaultList, weights);
    }

    /**
        @notice Gets the total list of queued deposit structs
        @return Array of queueDeposit structs
     */
    function fetchDepositQueue() external view returns (QueueDeposit[] memory) {
        return queueDeposits;
    }

    /**
        @notice Gets the shares queued and list of queued withdrawals for an owner
        @param owner Address of the owner
        @return shares item - queued shares and array of queueItem structs
     */
    function fetchWithdrawQueue(
        address owner
    ) external view returns (uint256 shares, QueueItem[] memory item) {
        shares = withdrawQueue[owner].shares;
        item = withdrawQueue[owner].queue;
    }

    /**
        @notice Gets the information related to a new deployment
        @return amounts epochIds vaultType vaults 
     */
    function fetchDeployAmounts()
        public
        view
        returns (
            uint256[] memory amounts,
            uint256[] memory epochIds,
            uint256[] memory vaultType,
            address[] memory vaults
        )
    {
        (epochIds, vaults, vaultType) = VaultGetter.fetchEpochIds(vaultList);
        amounts = hook.command.shouldCallForAvailableAmounts()
            ? hook.addr.availableAmounts(vaults, epochIds, weightStrategy)
            : PositionSizer.fetchWeights(
                vaults,
                epochIds,
                ((totalAssets() - queuedWithdrawalTvl) * weightProportion) /
                    10_000,
                weightStrategy
            );
    }

    /**
        @notice Gets the info about the active vault position in Y2K vaults
        @dev When deploying to V2 vaults a fee is levied on the amount meaning amounts will be less than deployed
        for these V2 positions
        @return vaults epochIds amounts - array of vault addresses, array of epochIds, array of amounts 
     */
    function fetchActivePosition()
        external
        view
        returns (
            address[] memory vaults,
            uint256[] memory epochIds,
            uint256[] memory amounts
        )
    {
        Position memory position = activePosition;
        return (position.vaults, position.epochIds, position.amounts);
    }

    /**
        @notice Gets the emissions eligible for a receiver
        @dev Approach inspired by SushiSwap MasterChefV2
        @param receiver Address of the receiver
        @return Emissions eligible
     */
    function previewEmissions(
        address receiver
    ) external view returns (uint256) {
        int256 accEmissions = int256(
            (balanceOf[receiver] * accEmissionPerShare) / PRECISION
        ) - userEmissionDebt[receiver];
        return uint256(accEmissions);
    }

    //////////////////////////////////////////////
    //             INTERNAL - CONFIG            //
    //////////////////////////////////////////////

    modifier checkQueued(address sender, uint256 amount) {
        if (balanceOf[sender] - withdrawQueue[sender].shares < amount)
            revert InsufficientBalance();
        _;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private checkQueued(from, amount) {
        _updateUserEmissions(from, amount, false);
        _updateUserEmissions(to, amount, true);
    }

    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        _transfer(msg.sender, to, amount);
        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        _transfer(from, to, amount);
        return super.transferFrom(from, to, amount);
    }

    /**
        @notice Helper function to check the weights used for the value do not exceed 100%
        @param weights Array of weights being assigned to vaults
     */
    function _checkWeightLimit(uint256[] calldata weights) internal pure {
        uint256 weightSum;
        for (uint256 i; i < weights.length; ) {
            weightSum += weights[i];
            unchecked {
                i++;
            }
        }
        if (weightSum > 10_000) revert InvalidInput();
    }

    /**
        @notice Helper function appending vault address(es) to the vaultList
        @param vaults Array of vault addresses to append
     */
    function _appendVaults(
        address[] calldata vaults
    ) internal returns (address[] memory) {
        address[] storage list = vaultList;
        for (uint256 i = 0; i < vaults.length; ) {
            list.push(vaults[i]);

            unchecked {
                i++;
            }
        }
        return list;
    }

    /**
        @notice Helper function to replace the vaultList with a new list
        @param vaults Array of vault addresses to replace with
     */
    function _replaceVaults(
        address[] calldata vaults
    ) internal returns (address[] memory) {
        vaultList = vaults;
        return vaults;
    }

    /**
        @notice Helper function to remove vaults from the vaultList
        @param vaults Array of vault addresses to remove
        @return newVaultList List of the new vaults
     */
    function _removeVaults(
        address[] memory vaults
    ) internal returns (address[] memory newVaultList) {
        uint256 removeCount = vaults.length;
        newVaultList = vaultList;

        for (uint256 i; i < newVaultList.length; ) {
            for (uint j; j < removeCount; ) {
                if (vaults[j] == newVaultList[i]) {
                    // Deleting the removeVault from the list
                    if (j == removeCount) {
                        delete vaults[j];
                        removeCount--;
                    } else {
                        if (vaults.length > 1) {
                            vaults[j] = vaults[removeCount - 1];
                            delete vaults[removeCount - 1];
                        } else delete vaults[j];
                        removeCount--;
                    }
                    // Deleting the vault from the newVaultList list
                    if (
                        newVaultList[i] == newVaultList[newVaultList.length - 1]
                    ) {
                        delete newVaultList[i];
                    } else {
                        newVaultList[i] = newVaultList[newVaultList.length - 1];
                        delete newVaultList[newVaultList.length - 1];
                    }
                }
                unchecked {
                    j++;
                }
            }
            unchecked {
                i++;
            }
        }

        vaultList = newVaultList;
        return newVaultList;
    }

    //////////////////////////////////////////////
    //            INTERNAL - VAULT MGMT         //
    //////////////////////////////////////////////
    /**
        @notice Deploys funds to Y2K vaults and stores information
        @dev VaultType is used to calculate fee for V2 vaults as amount deposited will differ from amount deployed
        @param vaults Array of vault addresses to deploy to
        @param ids Array of vault ids to deploy to
        @param amounts Array of amounts to deploy
        @param vaultType Array of vault types to deploy to
     */
    function _deployPosition(
        address[] memory vaults,
        uint256[] memory ids,
        uint256[] memory amounts,
        uint256[] memory vaultType
    ) internal {
        address[] memory assets = new address[](vaults.length);

        for (uint256 i = 0; i < vaults.length; ) {
            uint256 amount = amounts[i];
            if (amount == 0) {
                unchecked {
                    i++;
                }
                continue;
            }

            IEarthquake iVault = IEarthquake(vaults[i]);
            address asset = iVault.asset();
            assets[i] = asset;
            uint256 id = ids[i];

            ERC20(asset).safeApprove(address(iVault), amount);
            iVault.deposit(id, amount, address(this));
            if (vaultType[i] == 2)
                (, amounts[i]) = iVault.getEpochDepositFee(id, amount);
            unchecked {
                i++;
            }
        }

        activePosition = Position({
            vaults: vaults,
            epochIds: ids,
            amounts: amounts
        });

        emit FundsDeployed(vaults, ids, amounts);
    }

    /**
        @notice Withdraws funds from Y2K vaults
        @param position Position to withdraw from Y2K vaults
     */
    function _closePosition(Position memory position) internal {
        uint256[] memory receivedAmounts = new uint256[](
            position.vaults.length
        );

        for (uint256 i = 0; i < position.vaults.length; ) {
            receivedAmounts[i] = IEarthquake(position.vaults[i]).withdraw(
                position.epochIds[i],
                position.amounts[i],
                address(this),
                address(this)
            );
            unchecked {
                i++;
            }
        }

        emit FundsWithdrawn(
            position.vaults,
            position.epochIds,
            position.amounts,
            receivedAmounts,
            asset.balanceOf(address(this))
        );
    }

    /**
        @notice Pulls deposits from the deposit queued
        @dev Only called when the queue > 0 and < maxQueuePull
        @param queueLength Number of deposits to pull
     */
    function _pullQueuedDeposits(
        uint256 queueLength
    ) private returns (uint256 pulledAmount) {
        QueueDeposit[] memory deposits = queueDeposits;

        address[] memory receivers = new address[](queueLength);
        uint256[] memory assets = new uint256[](queueLength);
        uint256[] memory sharesReceived = new uint256[](queueLength);
        uint256 cachedSupply = totalSupply;
        uint256 cachedAssets = totalAssets();

        for (uint256 i; i < queueLength; ) {
            uint256 depositAssets = deposits[i].assets;
            address receiver = deposits[i].receiver;
            pulledAmount += depositAssets;

            uint256 shares = depositAssets.mulDivDown(
                cachedSupply,
                cachedAssets
            );
            _updateUserEmissions(receiver, shares, true);

            receivers[i] = receiver;
            assets[i] = depositAssets;
            sharesReceived[i] = shares;
            _mint(receiver, shares);
            unchecked {
                i++;
            }
        }

        delete totalQueuedDeposits;
        delete queueDeposits;

        // Pulls the whole balance of the queue contract
        queueContract.transferToStrategy(pulledAmount);
        emit BulkDeposit(msg.sender, receivers, assets, sharesReceived);

        if (hook.command.shouldCallAfterDeposit()) {
            asset.safeApprove(address(hook.addr), pulledAmount);
            hook.addr.afterDeposit(pulledAmount);
        }

        return pulledAmount;
    }

    /**
        @notice Transfers assets to receiver
        @dev If only one asset, transfer directly, otherwise loop through assets
        @param assets Array of assets to transfer
     */
    function _transferAssets(ERC20[] memory assets) private {
        if (assets.length == 1)
            assets[0].safeTransfer(
                address(hook.addr),
                assets[0].balanceOf(address(this))
            );
        else {
            address receiver = address(hook.addr);
            for (uint256 i = 0; i < assets.length; ) {
                ERC20 currentAsset = assets[i];
                currentAsset.safeTransfer(
                    receiver,
                    currentAsset.balanceOf(address(this))
                );
                unchecked {
                    i++;
                }
            }
        }
    }

    //////////////////////////////////////////////
    //         INTERNAL - EMISSION MGMT         //
    //////////////////////////////////////////////
    /**
        @notice Updates the vault emissions
        @dev Approach inspired by SushiSwap MasterChefV2
        @dev By comparing balance before position closed and balance after we find newEmissions
        @param emissionBalance Balance of the emission token prior to position closing
     */
    function _updateVaultEmissions(uint256 emissionBalance) private {
        uint256 _totalSupply = totalSupply;
        uint256 _totalEmissionsBalance = emissionToken.balanceOf(address(this));
        uint256 newEmissions = _totalEmissionsBalance - emissionBalance;
        uint256 _accEmissionPerShare = accEmissionPerShare;

        accEmissionPerShare =
            _accEmissionPerShare +
            ((newEmissions * PRECISION) / _totalSupply);
        emit EmissionsUpdated(
            deploymentId,
            _totalSupply,
            _totalEmissionsBalance,
            _accEmissionPerShare
        );
    }

    /**
        @notice Updates the user emissions
        @dev Approach inspired by SushiSwap MasterChefV2
        @param receiver Address of the user to update
        @param shares Amount of shares to update
        @param addDebt Whether to add or subtract debt depending on action (deposit/withdraw)
     */
    function _updateUserEmissions(
        address receiver,
        uint256 shares,
        bool addDebt
    ) private {
        int256 emissionValue = int256(
            (shares * accEmissionPerShare) / PRECISION
        );
        int256 userDebt = userEmissionDebt[receiver];

        if (addDebt) userEmissionDebt[receiver] = userDebt + emissionValue;
        else userEmissionDebt[receiver] = userDebt - emissionValue;
    }

    //////////////////////////////////////////////
    //             INTERNAL - PUBLIC MGMT       //
    //////////////////////////////////////////////
    /**
        @notice Withdraws the deposit asset from the vault
        @dev Overriden logic that relates to ERC4626 withdraw function
        @param assets Amount of assets to withdraw
        @param shares Amount of shares to withdraw
        @param receiver Address to receive the assets
        @param owner Address of the owner of the shares
     */
    function _withdraw(
        uint256 assets,
        uint256 shares,
        address receiver,
        address owner,
        bool fromQueue
    ) private {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.
            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares, fromQueue);

        asset.safeTransfer(receiver, assets);
    }

    /**
        @notice Previews the amount of assets that will be withdrawn based on users withdrawal queue
        @dev To calculate amount due, we loop through queued and use the cachedInfo stored after positions are closed
        @param owner Address of the owner of the shares
        @return assets Amount of assets that will be withdrawn
        @return shareSum Amount of shares that will be withdrawn
     */
    function _previewQueuedWithdraw(
        address owner
    ) internal returns (uint256 assets, uint256 shareSum) {
        uint256 queueLength = withdrawQueue[owner].queue.length;

        for (uint256 i; i < queueLength; ) {
            QueueItem memory item = withdrawQueue[owner].queue[i];

            uint256 shares = item.shares;
            shareSum += shares;
            QueueCache memory cachedInfo = queueCache[item.deploymentId];

            // NOTE: No instance where supply is 0 i.e. cachedInfo.totalSupply == 0 ? shares : <equation> removed
            assets += shares.mulDivDown(
                cachedInfo.totalAssets,
                cachedInfo.totalSupply
            );

            unchecked {
                i++;
            }
        }

        queuedWithdrawalTvl -= assets;
        delete withdrawQueue[owner];
    }

    /**
        @notice Queues deposit for user
        @dev Deposits are transferred to queue contract as ERC4626 shares relate to balance and balance will be 
        incorrect when funds are deployed i.e. funds are held elsewhere and pulled once balances are updated after
        position is closed.
        @param receiver Address of the user to receive the assets
        @param assets Amount of assets to deposit
        @return 0 - as expected return from deposit function
     */
    function _queueDeposit(
        address receiver,
        uint256 assets
    ) internal returns (uint256) {
        if (assets < minDeposit) revert InvalidDepositAmount();
        queueDeposits.push(QueueDeposit(receiver, assets));
        totalQueuedDeposits += uint128(assets);

        queueContract.transferToQueue(msg.sender, assets);

        emit DepositQueued(msg.sender, receiver, assets);
        return 0;
    }
}

