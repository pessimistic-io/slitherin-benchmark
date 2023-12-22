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
// ====================== MerkleProofPriceSource ======================
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
import { MerkleTreeProver } from "./MerkleTreeProver.sol";
import { StateProofVerifier as Verifier } from "./StateProofVerifier.sol";
import { IPriceSourceReceiver } from "./IPriceSourceReceiver.sol";
import { IStateRootOracle } from "./IStateRootOracle.sol";

/// @title MerkleProofPriceSource
/// @author Jon Walch (Frax Finance) https://github.com/jonwalch
/// @notice Proves price round data from an L1 Frax Oracle and pushes the price data to an L2 Frax Oracle
contract MerkleProofPriceSource is ERC165Storage, Timelock2Step {
    /// @notice Illustrative example. The layer 1 Frax Oracle's `rounds` storage slot index is 6.
    // uint256 public constant FRAX_ORACLE_LAYER_1_ROUNDS_STORAGE_SLOT_INDEX = 6;

    /// @notice The slot representing the Layer 1 Frax Oracle's `rounds` storage slot
    /// @dev FRAX_ORACLE_LAYER_1_ROUNDS_STORAGE_SLOT = uint256(keccak256(abi.encodePacked(FRAX_ORACLE_LAYER_1_ROUNDS_STORAGE_SLOT_INDEX)))
    uint256 public constant FRAX_ORACLE_LAYER_1_ROUNDS_STORAGE_SLOT =
        111_414_077_815_863_400_510_004_064_629_973_595_961_579_173_665_589_224_203_503_662_149_373_724_986_687;

    /// @notice The address of the StateRootOracle on Layer 2
    IStateRootOracle public immutable STATE_ROOT_ORACLE;

    /// @notice Configuration linking Frax Oracles for the same asset on L1 / L2
    mapping(address layer2FraxOracle => address layer1FraxOracle) public oracleLookup;

    /// @notice The ```constructor``` function
    /// @param _stateRootOracle Address of the L2 StateRootOracle
    /// @param _timelockAddress Address of Timelock contract on L2
    constructor(address _stateRootOracle, address _timelockAddress) Timelock2Step() {
        _setTimelock({ _newTimelock: _timelockAddress });
        _registerInterface({ interfaceId: type(ITimelock2Step).interfaceId });

        STATE_ROOT_ORACLE = IStateRootOracle(_stateRootOracle);
    }

    // ====================================================================
    // Events
    // ====================================================================

    /// @notice The ```OraclePairAdded``` event is emitted when a new Frax Oracle pair is added
    /// @param fraxOracleLayer1 The address of the layer 1 Frax Oracle
    /// @param fraxOracleLayer2 The address of the layer 2 Frax Oracle
    event OraclePairAdded(address indexed fraxOracleLayer1, address indexed fraxOracleLayer2);

    // ====================================================================
    // Configuration Setters
    // ====================================================================

    /// @dev A pair of addresses that are the Frax Oracles for the same asset on layer 1 and layer 2
    struct OraclePair {
        address layer1FraxOracle;
        address layer2FraxOracle;
    }

    /// @notice The ```addOraclePairs``` function sets an L1/L2 pair if they haven't been set already
    /// @param _oraclePairs List of OraclePairs representing the same oracle on L1 and L2
    function addOraclePairs(OraclePair[] calldata _oraclePairs) external {
        _requireTimelock();

        for (uint256 i = 0; i < _oraclePairs.length; ++i) {
            OraclePair memory _oraclePair = _oraclePairs[i];
            if (oracleLookup[_oraclePair.layer2FraxOracle] != address(0)) {
                revert OraclePairAlreadySet({
                    fraxOracleLayer1: oracleLookup[_oraclePair.layer2FraxOracle],
                    fraxOracleLayer2: _oraclePair.layer2FraxOracle
                });
            }
            oracleLookup[_oraclePair.layer2FraxOracle] = _oraclePair.layer1FraxOracle;
            emit OraclePairAdded({
                fraxOracleLayer1: _oraclePair.layer1FraxOracle,
                fraxOracleLayer2: _oraclePair.layer2FraxOracle
            });
        }
    }

    // ====================================================================
    // Proof / Add Price Function
    // ====================================================================

    /// @notice The ```addRoundData``` function uses merkle proofs to prove L1 Frax Oracle price data and posts it to the L2 Frax Oracle.
    /// @dev Proves the storage root using block info from the L2 StateRootOracle. Then uses storage root hash to prove the value
    /// @dev of an L1 Frax Oracle slot, which is price information. Decodes price information and then posts to
    /// @dev L2 Frax Oracle. L2 Frax Oracle must be configured to accept price data from this contract.
    /// @param _fraxOracleLayer2 The address of the L2 Frax Oracle
    /// @param _blockNumber The block number
    /// @param _roundNumber The price round number from the L1 Frax Oracle
    /// @param _accountProof The accountProof retrieved from eth_getProof
    /// @param _storageProof The storageProof.proof retrieved from eth_getProof
    function addRoundData(
        IPriceSourceReceiver _fraxOracleLayer2,
        uint256 _blockNumber,
        uint256 _roundNumber,
        bytes[] memory _accountProof,
        bytes[] memory _storageProof
    ) external {
        address _proofAddress = oracleLookup[address(_fraxOracleLayer2)];
        if (_proofAddress == address(0)) revert WrongOracleAddress();

        IStateRootOracle.BlockInfo memory _blockInfo = STATE_ROOT_ORACLE.getBlockInfo(_blockNumber);
        Verifier.Account memory _accountPool = MerkleTreeProver.proveStorageRoot({
            stateRootHash: _blockInfo.stateRootHash,
            proofAddress: _proofAddress,
            accountProof: _accountProof
        });

        // slot + round number offset
        bytes32 _slot = bytes32(FRAX_ORACLE_LAYER_1_ROUNDS_STORAGE_SLOT + _roundNumber);

        // _value is one packed storage slot corresponding to a FRAX_ORACLE_LAYER_1 price round
        uint256 _value = uint256(
            MerkleTreeProver
                .proveStorageSlotValue({
                    storageRootHash: _accountPool.storageRoot,
                    slot: _slot,
                    storageProof: _storageProof
                })
                .value
        );

        // First 104 bits is priceLow
        uint104 _priceLow = uint104(_value);
        // Next 104 bits is priceHigh
        uint104 _priceHigh = uint104(_value >> 104);
        // Next 40 bits is the timestamp
        uint40 _timestamp = uint40(_value >> 208);
        // Final 8 bits is isBadData
        bool _isBadData = uint8(_value >> 248) == 1;

        _fraxOracleLayer2.addRoundData({
            isBadData: _isBadData,
            priceLow: _priceLow,
            priceHigh: _priceHigh,
            timestamp: _timestamp
        });
    }

    // ====================================================================
    // Errors
    // ====================================================================

    error OraclePairAlreadySet(address fraxOracleLayer1, address fraxOracleLayer2);
    error WrongOracleAddress();
}

