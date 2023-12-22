// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

// ====================================================================
// |     ______                   _______                             |
// |    / _____________ __  __   / ____(_____  ____ _____  ________   |
// |   / /_  / ___/ __ `| |/_/  / /_  / / __ \/ __ `/ __ \/ ___/ _ \  |
// |  / __/ / /  / /_/ _>  <   / __/ / / / / / /_/ / / / / /__/  __/  |
// | /_/   /_/   \__,_/_/|_|  /_/   /_/_/ /_/\__,_/_/ /_/\___/\___/   |
// |                                                                  |
// ====================================================================
// ========================= StateRootOracle ==========================
// ====================================================================
// Frax Finance: https://github.com/FraxFinance

// Authors
// Jon Walch: https://github.com/jonwalch
// Dennis: https://github.com/denett

// Reviewers
// Drake Evans: https://github.com/DrakeEvans

// ====================================================================
import { ERC165Storage } from "./ERC165Storage.sol";
import { Timelock2Step } from "./Timelock2Step.sol";
import { ITimelock2Step } from "./ITimelock2Step.sol";
import { StateProofVerifier as Verifier } from "./StateProofVerifier.sol";
import { IBlockHashProvider } from "./IBlockHashProvider.sol";
import { IStateRootOracle } from "./IStateRootOracle.sol";

/// @title StateRootOracle
/// @author Jon Walch (Frax Finance) https://github.com/jonwalch
/// @notice Oracle for proving state root hashes on L2 that originate from L1 block headers
contract StateRootOracle is IStateRootOracle, ERC165Storage, Timelock2Step {
    /// @notice Minimum number of block hash providers needed to prove the state root.
    uint256 public minimumRequiredProviders;

    /// @notice Mapping from block number to BlockInfo struct that stores proven state root data.
    mapping(uint256 blockNumber => BlockInfo) public blockNumberToBlockInfo;

    /// @notice List of configured block hash providers.
    IBlockHashProvider[] public blockHashProviders;

    /// @notice The ```constructor``` function
    /// @param _providers List of block hash provider addresses
    /// @param _minimumRequiredProviders Initial number of required block hash provider
    /// @param _timelockAddress Address of Timelock contract on L2
    constructor(
        IBlockHashProvider[] memory _providers,
        uint256 _minimumRequiredProviders,
        address _timelockAddress
    ) Timelock2Step() {
        _setTimelock({ _newTimelock: _timelockAddress });
        _registerInterface({ interfaceId: type(ITimelock2Step).interfaceId });
        _registerInterface({ interfaceId: type(IStateRootOracle).interfaceId });

        _setMinimumRequiredProviders(_minimumRequiredProviders);

        for (uint256 i = 0; i < _providers.length; ++i) {
            _addProvider(_providers[i]);
        }
    }

    // ====================================================================
    // Events
    // ====================================================================

    /// @notice The ```BlockVerified``` event is emitted when a block is proven / verified
    /// @param blockNumber The block number of the block that was verified
    /// @param timestamp The timestamp corresponding to the block that was verified
    /// @param stateRootHash The state root hash of the verified block
    event BlockVerified(uint40 blockNumber, uint40 timestamp, bytes32 stateRootHash);

    /// @notice The ```ProviderAdded``` event is emitted when a new block hash provider is added
    /// @param provider Address of the provider that was added
    event ProviderAdded(address provider);

    /// @notice The ```ProviderRemoved``` event is emitted when an existing block hash provider is removed
    /// @param provider Address of the provider that was removed
    event ProviderRemoved(address provider);

    /// @notice The ```SetMinimumRequiredProviders``` event is emitted when the value of minimumRequiredProviders is changed
    /// @param oldMinimumRequiredProviders The old value of minimumRequiredProviders
    /// @param newMinimumRequiredProviders The new value of minimumRequiredProviders
    event SetMinimumRequiredProviders(uint256 oldMinimumRequiredProviders, uint256 newMinimumRequiredProviders);

    // ====================================================================
    // External Getters
    // ====================================================================

    /// @notice The ```getBlockHashProvidersCount``` function returns the number of configured block hash providers
    /// @return _providersCount The number of configured block hash providers
    function getBlockHashProvidersCount() external view returns (uint256 _providersCount) {
        _providersCount = blockHashProviders.length;
    }

    /// @notice The ```getBlockInfo``` function returns the BlockInfo corresponding to _blockNumber
    /// @param _blockNumber The block number
    /// @return _blockInfo The BlockInfo struct corresponding to the _blockNumber
    function getBlockInfo(uint256 _blockNumber) external view returns (BlockInfo memory _blockInfo) {
        _blockInfo = blockNumberToBlockInfo[_blockNumber];
    }

    // ====================================================================
    // Proof Function
    // ====================================================================

    /// @notice The ```proveStateRoot``` function proves a state root hash given enough block hash providers
    /// @dev Since a _blockHeader can be forged, a higher number of reputable providers implies higher confidence in a block header
    /// @param _blockHeader RLP encoded block header retrieved from eth_getBlockByNumber
    function proveStateRoot(bytes memory _blockHeader) external {
        Verifier.BlockHeader memory _parsedBlockHeader = Verifier.parseBlockHeader(_blockHeader);
        BlockInfo memory currentBlockInfo = blockNumberToBlockInfo[_parsedBlockHeader.number];

        if (currentBlockInfo.stateRootHash != 0) {
            revert StateRootAlreadyProvenForBlockNumber(_parsedBlockHeader.number);
        }

        uint256 _count = 0;
        uint256 _providersLength = blockHashProviders.length;
        for (uint256 i = 0; i < _providersLength; ++i) {
            if (blockHashProviders[i].blockHashStored(_parsedBlockHeader.hash)) {
                ++_count;
            }
        }

        if (_count < minimumRequiredProviders) revert NotEnoughProviders();

        blockNumberToBlockInfo[_parsedBlockHeader.number] = BlockInfo({
            stateRootHash: _parsedBlockHeader.stateRootHash,
            timestamp: uint40(_parsedBlockHeader.timestamp)
        });

        emit BlockVerified({
            blockNumber: uint40(_parsedBlockHeader.number),
            stateRootHash: _parsedBlockHeader.stateRootHash,
            timestamp: uint40(_parsedBlockHeader.timestamp)
        });
    }

    // ====================================================================
    // Configuration Setters
    // ====================================================================

    /// @notice The ```_setMinimumRequiredProviders``` function sets the minimumRequiredProviders
    /// @param _minimumRequiredProviders The new minimumRequiredProviders
    function _setMinimumRequiredProviders(uint256 _minimumRequiredProviders) internal {
        if (_minimumRequiredProviders == 0) revert MinimumRequiredProvidersTooLow();

        uint256 _currentMinimumRequiredProviders = minimumRequiredProviders;
        if (_minimumRequiredProviders == _currentMinimumRequiredProviders) revert SameMinimumRequiredProviders();

        emit SetMinimumRequiredProviders({
            oldMinimumRequiredProviders: _currentMinimumRequiredProviders,
            newMinimumRequiredProviders: _minimumRequiredProviders
        });
        minimumRequiredProviders = _minimumRequiredProviders;
    }

    /// @notice The ```setMinimumRequiredProviders``` function sets the minimumRequiredProviders
    /// @dev Requires msg.sender to be the timelock address
    /// @param _minimumRequiredProviders The new minimumRequiredProviders
    function setMinimumRequiredProviders(uint256 _minimumRequiredProviders) external {
        _requireTimelock();
        _setMinimumRequiredProviders(_minimumRequiredProviders);
    }

    /// @notice The ```_addProvider``` function adds a new block hash provider to blockHashProviders
    /// @param _provider The block hash provider to add to blockHashProviders
    function _addProvider(IBlockHashProvider _provider) internal {
        uint256 providersLength = blockHashProviders.length;
        for (uint256 i = 0; i < providersLength; ++i) {
            if (blockHashProviders[i] == _provider) {
                revert ProviderAlreadyAdded();
            }
        }

        emit ProviderAdded(address(_provider));
        blockHashProviders.push(_provider);
    }

    /// @notice The ```addProvider``` function adds a new block hash provider to blockHashProviders
    /// @dev Requires msg.sender to be the timelock address
    /// @param _provider The block hash provider to add to blockHashProviders
    function addProvider(IBlockHashProvider _provider) external {
        _requireTimelock();
        _addProvider(_provider);
    }

    /// @notice The ```removeProvider``` function removes an existing block hash provider from blockHashProviders
    /// @dev Requires msg.sender to be the timelock address
    /// @param _provider The block hash provider to remove from blockHashProviders
    function removeProvider(IBlockHashProvider _provider) external {
        _requireTimelock();
        uint256 providersLength = blockHashProviders.length;

        for (uint256 i = 0; i < providersLength; ++i) {
            if (blockHashProviders[i] == _provider) {
                emit ProviderRemoved(address(_provider));
                blockHashProviders[i] = blockHashProviders[providersLength - 1];
                blockHashProviders.pop();
                return;
            }
        }
        revert ProviderNotFound();
    }

    // ====================================================================
    // Errors
    // ====================================================================

    error MinimumRequiredProvidersTooLow();
    error NotEnoughProviders();
    error ProviderAlreadyAdded();
    error ProviderNotFound();
    error SameMinimumRequiredProviders();
    error StateRootAlreadyProvenForBlockNumber(uint256 blockNumber);
}

