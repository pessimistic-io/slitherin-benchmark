// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./IERC20.sol";
import "./ERC20Upgradeable.sol";
import "./IERC20.sol";
import "./ERC20PermitUpgradeable.sol";
import "./IERC20Metadata.sol";
import "./SafeERC20.sol";
import "./Strings.sol";
import "./ReentrancyGuard.sol";

import "./IStrategVaultFactory.sol";
import "./IStrategBlockRegistry.sol";
import "./IStrategERC3525.sol";
import "./IStrategAssetBuffer.sol";
import "./StrategVaultManagement.sol";
import "./StrategERC4626Upgradeable.sol";
import {LibBlock} from "./LibBlock.sol";
import {DataTypes} from "./DataTypes.sol";
import {LibOracleState} from "./LibOracleState.sol";
import {IStrategStrategyBlock} from "./IStrategStrategyBlock.sol";

import {IStrategAssetBuffer} from "./IStrategAssetBuffer.sol";

/**
 * Errors
 */
error NotOperator();
error EmergencyExecutionReverted(address _address, bytes _data);

error NotPositionManager();
error StrategyNotInitialized();
error StrategyAlreadyInitialized();
error DepositMoreThanMax();
error WithdrawMoreThanMax();
error BlockListNotValid();
error NoSharesMinted();

/**
 * @title StrategVault
 * @author Bliiitz
 * @notice Strateg. Vault implementation
 */
contract StrategVault is
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    StrategERC4626Upgradeable,
    StrategVaultManagement,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using VaultConfiguration for DataTypes.VaultConfigurationMap;
    using LibOracleState for DataTypes.OracleState;

    address public immutable buffer;
    address immutable operator;
    address immutable registry;
    address immutable feeCollector;

    bool public stratInitialized;

    uint256 private nativeTVL;
    uint256 private lastNativeTVLUpdate;

    mapping(uint256 => address) private strategyBlocks;
    mapping(uint256 => address) private harvestBlocks;
    mapping(address => bool) private isOwnedPositionManager;

    event StrategyInitialized(
        address[] _stratBlocksIndex,
        bytes[] _stratBlocksParameters,
        address[] _harvestBlocksIndex,
        bytes[] _harvestBlocksParameters
    );

    modifier onlyOperator() {
        if (msg.sender != operator) revert NotOperator();
        _;
    }

    modifier onlyPositionManager() {
        if (!isOwnedPositionManager[msg.sender]) revert NotPositionManager();
        _;
    }

    /**
     * @dev Set the underlying asset contract. This must be an ERC20-compatible contract (ERC20 or ERC777).
     */
    constructor(address _buffer, address _operator, address _registry, address _feeCollector) {
        buffer = _buffer;
        operator = _operator;
        registry = _registry;
        feeCollector = _feeCollector;
        _disableInitializers();
    }

    /**
     * @dev Initalize function call by the factory on deployment
     * @param _owner owner of the vault (strategist)
     * @param _erc3525 ERC3525 address
     * @param _name vault name
     * @param _symbol vault symbol
     * @param _asset native asset
     * @param _strategy Middleware strategy
     * @param _bufferSize Percentage of the buffer
     * @param _creatorFee Creator fees where 100% is 10000
     * @param _harvestFee Harvester fees where 100% is 10000
     */
    function initialize(
        address _owner,
        address _erc3525,
        string memory _name,
        string memory _symbol,
        address _asset,
        uint256 _strategy,
        uint256 _bufferSize,
        uint256 _creatorFee,
        uint256 _harvestFee
    ) external initializer {
        __ERC20_init(_name, _symbol);
        __ERC20Permit_init(_name);
        __ERC4626_init(IERC20(_asset), buffer);
        __StrategVaultManagement_init(msg.sender, _erc3525, _strategy, _creatorFee, _harvestFee);

        //erc3525 = _erc3525;
        DataTypes.VaultConfigurationMap memory c = config;
        c.setMiddlewareStrategy(_strategy);
        c.setBufferSize(_bufferSize);
        c.setBufferDerivation(500);
        c.setCreatorFee(_creatorFee);
        c.setHarvestFee(_harvestFee);
        c.setLastHarvestIndex(10000);
        config = c;

        _whitelistInit(_owner);

        IERC20(_asset).safeIncreaseAllowance(buffer, type(uint256).max);
    }

    

    /**
     * @dev Set the decimal value for the vault token.
     * @return The number of decimals for the vault token.
     */
    function decimals() public view virtual override(StrategERC4626Upgradeable, ERC20Upgradeable) returns (uint8) {
        return StrategERC4626Upgradeable.decimals();
    }

    /**
     * @dev Set the strategy blocks for the vault.
     * @param _positionManagers Array of position managers.
     * @param _stratBlocks Array of strategy blocks.
     * @param _stratBlocksParameters Array of strategy block parameters.
     * @param _harvestBlocks Array of harvest blocks.
     * @param _harvestBlocksParameters Array of harvest block parameters.
     */
    function setStrat(
        address[] memory _positionManagers,
        address[] memory _stratBlocks,
        bytes[] memory _stratBlocksParameters,
        address[] memory _harvestBlocks,
        bytes[] memory _harvestBlocksParameters
    ) external onlyFactory {
        if (stratInitialized) revert StrategyAlreadyInitialized();

        IStrategyBlockRegistry r = IStrategyBlockRegistry(registry);

        uint256 _blocksToVerifyCurrentIndex = 0;
        uint256 _blocksToVerifyLength = _stratBlocks.length + _harvestBlocks.length;
        address[] memory _blocksToVerify = new address[](_blocksToVerifyLength);

        for (uint256 i = 0; i < _stratBlocks.length; i++) {
            strategyBlocks[i] = _stratBlocks[i];
            _blocksToVerify[_blocksToVerifyCurrentIndex] = _stratBlocks[i];
            _blocksToVerifyCurrentIndex = _blocksToVerifyCurrentIndex + 1;

            LibBlock.setupStrategyBlockData(i, _stratBlocksParameters[i]);
        }

        for (uint256 i = 0; i < _harvestBlocks.length; i++) {
            harvestBlocks[i] = _harvestBlocks[i];
            _blocksToVerify[_blocksToVerifyCurrentIndex] = _harvestBlocks[i];
            _blocksToVerifyCurrentIndex = _blocksToVerifyCurrentIndex + 1;

            LibBlock.setupHarvestBlockData(i, _harvestBlocksParameters[i]);
        }

        if (!r.blocksValid(_blocksToVerify)) revert BlockListNotValid();

        for (uint256 i = 0; i < _positionManagers.length; i++) {
            isOwnedPositionManager[_positionManagers[i]] = true;
        }

        DataTypes.VaultConfigurationMap memory c = config;
        c.setStrategyBlocksLength(_stratBlocks.length);
        c.setHarvestBlocksLength(_harvestBlocks.length);
        config = c;

        stratInitialized = true;

        emit StrategVaultUpdate(
            StrategVaultUpdateType.StrategyInitialized,
            abi.encode(_stratBlocks, _stratBlocksParameters, _harvestBlocks, _harvestBlocksParameters)
        );
    }

    /**
     * @dev Get the strategy blocks for the vault.
     * @return config Array of strategy blocks.
     */
    function configuration() external view returns (DataTypes.VaultConfigurationMap memory) {
        return config;
    }

    /**
     * @dev Get the strategy blocks for the vault.
     * @return _strategyBlocks Array of strategy blocks.
     * @return _strategyBlocksParameters Array of strategy blocks.
     * @return _harvestBlocks Array of strategy blocks.
     * @return _harvestBlocksParameters Array of strategy blocks.
     */
    function getStrat()
        external
        view
        returns (
            address[] memory _strategyBlocks,
            bytes[] memory _strategyBlocksParameters,
            address[] memory _harvestBlocks,
            bytes[] memory _harvestBlocksParameters
        )
    {
        DataTypes.VaultConfigurationMap memory c = config;
        uint256 strategyLength = c.getStrategyBlocksLength();
        uint256 harvestLength = c.getHarvestBlocksLength();

        _strategyBlocks = new address[](strategyLength);
        _strategyBlocksParameters = new bytes[](strategyLength);
        _harvestBlocks = new address[](harvestLength);
        _harvestBlocksParameters = new bytes[](harvestLength);

        for (uint256 i = 0; i < strategyLength; i++) {
            _strategyBlocks[i] = strategyBlocks[i];
            _strategyBlocksParameters[i] = LibBlock.getStrategyStorageByIndex(i);
        }

        for (uint256 i = 0; i < harvestLength; i++) {
            _harvestBlocks[i] = harvestBlocks[i];
            _harvestBlocksParameters[i] = LibBlock.getHarvestStorageByIndex(i);
        }
    }

    /**
     * @notice Executes partial strategy enter for a given range of strategy blocks.
     * @dev Executes the strategy enter function for a subset of strategy blocks, starting from `_from` index.
     *      The `_dynParamsIndex` array and `_dynParams` array provide dynamic parameters for the strategy blocks.
     * @param _from The starting index of the strategy blocks.
     * @param _dynParamsIndex The array of dynamic parameter indices.
     * @param _dynParams The array of dynamic parameter values.
     */
    function partialStrategyEnter(uint256 _from, uint256[] memory _dynParamsIndex, bytes[] memory _dynParams)
        external
        onlyPositionManager
    {
        _storeDynamicParams(_dynParamsIndex, _dynParams);
        uint256 length = config.getStrategyBlocksLength();
        uint256 startAt = _from + 1;
        for (uint256 i = startAt; i < length; i++) {
            LibBlock.executeStrategyEnter(strategyBlocks[i], i);
        }
        _purgeDynamicParams(_dynParamsIndex);
    }

    /**
     * @notice Executes partial strategy exit for a given range of strategy blocks.
     * @dev Executes the strategy exit function for a subset of strategy blocks, ending at `_to` index.
     *      The `_dynParamsIndex` array and `_dynParams` array provide dynamic parameters for the strategy blocks.
     * @param _to The ending index of the strategy blocks.
     * @param _dynParamsIndex The array of dynamic parameter block indexes.
     * @param _dynParams The array of dynamic parameter values.
     */
    function partialStrategyExit(uint256 _to, uint256[] memory _dynParamsIndex, bytes[] memory _dynParams)
        external
        onlyPositionManager
    {
        _storeDynamicParams(_dynParamsIndex, _dynParams);
        uint256 length = config.getStrategyBlocksLength();
        uint256 revertedIndex = length - 1;

        for (uint256 i = 0; i < length; i++) {
            if (revertedIndex - i < _to + 1) break;
            uint256 index = revertedIndex - i;
            LibBlock.executeStrategyExit(strategyBlocks[index], index, 10000);
        }
        _purgeDynamicParams(_dynParamsIndex);
    }

    /**
     * @dev Internal function to fetch the native TVL (Total Value Locked) of the vault.
     * @param _force Boolean flag to force an update of the native TVL.
     * @return The native TVL of the vault.
     */
    function _fetchNativeTVL(bool _force) internal returns (uint256) {
        if (lastNativeTVLUpdate == block.timestamp && !_force) return nativeTVL;

        lastNativeTVLUpdate = block.timestamp;
        return _getNativeTVL();
    }

    /**
     * @dev Internal function to get the native TVL (Total Value Locked) of the vault.
     * @return The native TVL of the vault.
     */
    function _getNativeTVL() internal view returns (uint256) {
        address _asset = asset();

        DataTypes.OracleState memory oracleState;
        oracleState.vault = address(this);

        uint256 strategyBlocksLength = config.getStrategyBlocksLength();
        if (strategyBlocksLength == 0) {
            return IERC20(_asset).balanceOf(address(this)) + IERC20(_asset).allowance(buffer, address(this));
        } else if (strategyBlocksLength == 1) {
            oracleState =
                IStrategStrategyBlock(strategyBlocks[0]).oracleExit(oracleState, LibBlock.getStrategyStorageByIndex(0));
        } else {
            uint256 revertedIndex = strategyBlocksLength - 1;
            for (uint256 i = 0; i < strategyBlocksLength; i++) {
                uint256 index = revertedIndex - i;
                oracleState = IStrategStrategyBlock(strategyBlocks[index]).oracleExit(
                    oracleState, LibBlock.getStrategyStorageByIndex(index)
                );
            }
        }

        return oracleState.findTokenAmount(_asset) + IERC20(_asset).balanceOf(address(this))
            + IERC20(_asset).allowance(buffer, address(this));
    }

    /**
     * @dev Get the total assets (TVL) of the vault.
     * @return The total assets (TVL) of the vault.
     */
    function totalAssets() public view virtual override returns (uint256) {
        return _getNativeTVL();
    }

    /**
     * @dev Internal function to harvest strategy rewards.
     */
    function _harvestStrategy() private {
        uint256 harvestBlocksLength = config.getHarvestBlocksLength();
        for (uint256 i = 0; i < harvestBlocksLength; i++) {
            LibBlock.executeHarvest(harvestBlocks[i], i);
        }
    }

    /**
     * @dev Internal function to enter the vault assets into the strategy.
     */
    function _enterInStrategy() private {
        uint256 tvl = _fetchNativeTVL(true);
        if (tvl < vaultMinDeposit) {
            return;
        }

        uint256 stratBlocksLength = config.getStrategyBlocksLength();
        for (uint256 i = 0; i < stratBlocksLength; i++) {
            LibBlock.executeStrategyEnter(strategyBlocks[i], i);
        }
    }

    /**
     * @dev Internal function to exit the vault from the strategy.
     * @param _percent The percentage of assets to exit from the strategy.
     */
    function _exitStrategy(uint256 _percent) private {
        uint256 stratBlocksLength = config.getStrategyBlocksLength();

        if (stratBlocksLength == 0) return;

        if (stratBlocksLength == 1) {
            LibBlock.executeStrategyExit(strategyBlocks[0], 0, _percent);
        } else {
            uint256 revertedIndex = stratBlocksLength - 1;
            for (uint256 i = 0; i < stratBlocksLength; i++) {
                uint256 index = revertedIndex - i;
                if (i == 0) {
                    LibBlock.executeStrategyExit(strategyBlocks[index], index, _percent);
                } else {
                    LibBlock.executeStrategyExit(strategyBlocks[index], index, 10000);
                }
            }
        }

        _fetchNativeTVL(true);
    }

    /**
     * @dev Internal function to harvest fees from the vault.
     */
    function _harvestFees() private {
        _fetchNativeTVL(false);
        DataTypes.VaultConfigurationMap memory c = config;
        uint256 tSupply = totalSupply();
        uint256 _lastFeeHarvestIndex = c.getLastHarvestIndex();
        uint256 currentVaultIndex = (totalAssets() * 10000) / tSupply;

        uint256 _protocolFee = IStrategVaultFactory(factory).protocolFee();
        uint256 _creatorFee = config.getCreatorFee();
        uint256 _harvestFee = config.getHarvestFee();

        if (_lastFeeHarvestIndex == currentVaultIndex || currentVaultIndex < _lastFeeHarvestIndex) {
            c.setLastHarvestIndex(currentVaultIndex);
            config = c;
            return;
        }

        uint256 lastFeeHarvestIndexDiff = currentVaultIndex - _lastFeeHarvestIndex;
        uint256 taxableValue = (lastFeeHarvestIndexDiff * tSupply) / 10000;

        c.setLastHarvestIndex(
            currentVaultIndex - ((lastFeeHarvestIndexDiff * (_creatorFee + _harvestFee + _protocolFee)) / 10000)
        );
        config = c;

        IERC20 _asset = IERC20(asset());

        //creatorFee
        uint256 creatorFeeAmount = (taxableValue * _creatorFee) / 10000;
        _asset.safeTransferFrom(buffer, address(this), creatorFeeAmount);
        _asset.safeIncreaseAllowance(erc3525, creatorFeeAmount);
        IStrategERC3525(erc3525).addRewards(creatorFeeAmount);

        //harvestFee
        _asset.safeTransferFrom(buffer, msg.sender, (taxableValue * _harvestFee) / 10000);

        //protocolFee
        _asset.safeTransferFrom(buffer, feeCollector, (taxableValue * _protocolFee) / 10000);
    }

    /**
     * @dev Deposit assets into the vault and mint shares to the receiver.
     * @param assets The amount of assets to deposit.
     * @param receiver The address to receive the minted shares.
     * @return The amount of shares minted.
     */
    function deposit(uint256 assets, address receiver) public virtual override nonReentrant returns (uint256) {
        if (!stratInitialized) revert StrategyNotInitialized();
        if (assets > maxDeposit(receiver)) revert DepositMoreThanMax();

        address sender = _msgSender();
        uint256 shares = previewDeposit(assets);

        _applyMiddleware(assets, _fetchNativeTVL(false));
        _resetTimelock(sender);
        _deposit(sender, receiver, assets, shares);
        _incrementValueDeposited(sender, shares);
        if (shares == 0) revert NoSharesMinted();

        return shares;
    }

    /**
     * @dev Mint shares to the receiver.
     * @param shares The amount of shares to mint.
     * @param receiver The address to receive the minted shares.
     * @return The amount of assets minted.
     */
    function mint(uint256 shares, address receiver) public virtual override nonReentrant returns (uint256) {
        if (!stratInitialized) revert StrategyNotInitialized();
        if (shares > maxMint(receiver)) revert DepositMoreThanMax();

        address sender = _msgSender();
        uint256 vaultTVL = _fetchNativeTVL(false);
        uint256 assets = previewMint(shares);

        _applyMiddleware(assets, vaultTVL);
        _resetTimelock(sender);
        _deposit(sender, receiver, assets, shares);
        _incrementValueDeposited(sender, shares);

        return assets;
    }

    /**
     * @dev Withdraw assets from the vault and burn the corresponding shares.
     * @param assets The amount of assets to withdraw.
     * @param receiver The address to receive the withdrawn assets.
     * @param owner The owner of the shares being burned.
     * @return The amount of shares burned.
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override
        nonReentrant
        returns (uint256)
    {
        _applyTimelock();
        if (assets > maxWithdraw(owner)) revert WithdrawMoreThanMax();

        uint256 shares = previewWithdraw(assets);
        _decreaseValueDeposited(_msgSender(), shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return shares;
    }

    /**
     * @dev Redeem shares for assets from the vault.
     * @param shares The amount of shares to redeem.
     * @param receiver The address to receive the redeemed assets.
     * @param owner The owner of the shares being redeemed.
     * @return The amount of assets redeemed.
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        virtual
        override
        nonReentrant
        returns (uint256)
    {
        _applyTimelock();
        if (shares > maxRedeem(owner)) revert WithdrawMoreThanMax();

        uint256 assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);
        _decreaseValueDeposited(_msgSender(), shares);

        return assets;
    }

    /**
     * @dev Internal function to stop the strategy, harvest fees, and perform rebalancing.
     * @param _dynParamsIndex The array of dynamic parameter indices.
     * @param _dynParams The array of dynamic parameter values.
     */
    function stopStrategy(uint256[] memory _dynParamsIndex, bytes[] memory _dynParams) external onlyOperator {
        _storeDynamicParams(_dynParamsIndex, _dynParams);
        _fetchNativeTVL(false);
        _harvestStrategy();
        _exitStrategy(10000);
        _harvestFees();
        _purgeDynamicParams(_dynParamsIndex);
    }

    /**
     * @dev Internal function to harvest strategy rewards.
     * @param _dynParamsIndex The array of dynamic parameter indices.
     * @param _dynParams The array of dynamic parameter values.
     */
    function harvest(uint256[] memory _dynParamsIndex, bytes[] memory _dynParams) external onlyOperator {
        _storeDynamicParams(_dynParamsIndex, _dynParams);
        _fetchNativeTVL(false);
        _harvestStrategy();
        _harvestFees();
        _purgeDynamicParams(_dynParamsIndex);
    }

    /**
     * @dev Function to execute the buffer rebalancing process.
     * @param _dynParamsIndexEnter The array of dynamic parameter indices for strategy enter.
     * @param _dynParamsEnter The array of dynamic parameters for strategy enter.
     * @param _dynParamsIndexExit The array of dynamic parameter indices for strategy exit.
     * @param _dynParamsExit The array of dynamic parameters for strategy exit.
     */
    function rebalance(
        uint256[] memory _dynParamsIndexEnter,
        bytes[] memory _dynParamsEnter,
        uint256[] memory _dynParamsIndexExit,
        bytes[] memory _dynParamsExit
    ) external onlyOperator {
        _rebalance(_dynParamsIndexEnter, _dynParamsEnter, _dynParamsIndexExit, _dynParamsExit);
    }

    /**
     * @dev Function to perform a withdrawal rebalance.
     * @param _user The user address requesting the withdrawal.
     * @param _amount The amount of assets to be withdrawn.
     * @param _dynParamsIndexEnter The array of dynamic parameter indices for strategy enter.
     * @param _dynParamsEnter The array of dynamic parameters for strategy enter.
     * @param _dynParamsIndexExit The array of dynamic parameter indices for strategy exit.
     * @param _dynParamsExit The array of dynamic parameters for strategy exit.
     */
    function withdrawalRebalance(
        address _user,
        uint256 _amount,
        uint256[] memory _dynParamsIndexEnter,
        bytes[] memory _dynParamsEnter,
        uint256[] memory _dynParamsIndexExit,
        bytes[] memory _dynParamsExit
    ) external onlyOperator {
        _storeDynamicParams(_dynParamsIndexExit, _dynParamsExit);

        IERC20 _asset = IERC20(asset());
        /**
         * Exit strategy funds
         */
        _exitStrategy((_amount * 10000) / _fetchNativeTVL(false));

        /**
         * Check if there is sufficient assets owned by the vault to send them
         * if not sufficient: transfer assets from the buffer
         */
        uint256 availableAssets = _asset.balanceOf(address(this));
        if (_amount > availableAssets) {
            IERC20(_asset).safeTransferFrom(buffer, address(this), _amount - availableAssets);
        }

        /**
         * @dev Execute user withdrawal with ERC4626 low level function
         */
        uint256 shares = previewWithdraw(_amount);
        _burn(msg.sender, shares);
        IERC20(asset()).safeTransfer(_user, _amount);
        emit Withdraw(msg.sender, _user, msg.sender, _amount, shares);

        /**
         * Calculate new buffer size and rebalance the vault
         */
        _rebalance(_dynParamsIndexEnter, _dynParamsEnter, _dynParamsIndexExit, _dynParamsExit);
        _purgeDynamicParams(_dynParamsIndexEnter);
    }

    /**
     * @dev Internal function to execute the buffer rebalancing process.
     * @param _dynParamsIndexEnter The array of dynamic parameter indices for strategy enter.
     * @param _dynParamsEnter The array of dynamic parameters for strategy enter.
     * @param _dynParamsIndexExit The array of dynamic parameter indices for strategy exit.
     * @param _dynParamsExit The array of dynamic parameters for strategy exit.
     */
    function _rebalance(
        uint256[] memory _dynParamsIndexEnter,
        bytes[] memory _dynParamsEnter,
        uint256[] memory _dynParamsIndexExit,
        bytes[] memory _dynParamsExit
    ) internal {
        uint256 _bufferSize = IERC20(asset()).allowance(buffer, address(this));
        uint256 _nativeTVL = _fetchNativeTVL(true);

        if (_nativeTVL == 0) return;

        uint256 bufferSize = config.getBufferSize();
        uint256 currentBufferSize = (_bufferSize * 10000) / _nativeTVL;
        uint256 derivation = config.getBufferDerivation();
        /**
         * Buffer oversized
         */
        if (currentBufferSize > bufferSize + derivation) {
            _storeDynamicParams(_dynParamsIndexEnter, _dynParamsEnter);
            uint256 amountToDeposit = (_nativeTVL * (currentBufferSize - bufferSize)) / 10000;
            IERC20(asset()).safeTransferFrom(buffer, address(this), amountToDeposit);
            _enterInStrategy();
        }

        /**
         * Buffer undersized
         */
        if (currentBufferSize < bufferSize - derivation) {
            _storeDynamicParams(_dynParamsIndexExit, _dynParamsExit);
            _exitStrategy(bufferSize - currentBufferSize);
            IERC20 token = IERC20(asset());
            IStrategAssetBuffer(buffer).putInBuffer(address(token), token.balanceOf(address(this)));
        }

        _purgeDynamicParams(_dynParamsIndexEnter);
    }

    /**
     * @dev Internal function to store dynamic block parameters.
     * @param _dynParamsIndex The array of dynamic parameter indices.
     * @param _dynParams The array of dynamic parameter values.
     */
    function _storeDynamicParams(uint256[] memory _dynParamsIndex, bytes[] memory _dynParams) internal {
        uint256 arrLength = _dynParamsIndex.length;
        for (uint256 i = 0; i < arrLength; i++) {
            LibBlock.setupDynamicBlockData(_dynParamsIndex[i], _dynParams[i]);
        }
    }

    /**
     * @dev Internal function to purge dynamic block parameters.
     * @param _dynParamsIndex The array of dynamic parameter indices.
     */
    function _purgeDynamicParams(uint256[] memory _dynParamsIndex) internal {
        uint256 arrLength = _dynParamsIndex.length;
        for (uint256 i = 0; i < arrLength; i++) {
            LibBlock.purgeDynamicBlockData(_dynParamsIndex[i]);
        }
    }

    /**
     * @dev Internal function to perform emergency execution.
     * @param _targets The array of target addresses to call for executing the emergency execution.
     * @param _datas The array of data provided to perform emergency execution..
     */
    function emergencyExecution(address[] memory _targets, bytes[] memory _datas) external onlyFactory {
        for (uint256 i = 0; i < _targets.length; i++) {
            (bool success, bytes memory _data) = _targets[i].call(abi.encode(_datas[i]));
            if (!success) revert EmergencyExecutionReverted(_targets[i], _data);
        }
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        emit StrategVaultUpdate(
            StrategVaultUpdateType.Transfer,
            abi.encode(from, to, value)
        );
    }
}

