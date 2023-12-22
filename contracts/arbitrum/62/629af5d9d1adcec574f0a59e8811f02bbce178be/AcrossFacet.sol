// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./ERC20.sol";
import "./IERC20.sol";
import { ILiFi } from "./ILiFi.sol";
import { IAcrossSpokePool } from "./IAcrossSpokePool.sol";
import { LibDiamond } from "./LibDiamond.sol";
import { LibAsset } from "./LibAsset.sol";
import { LibSwap } from "./LibSwap.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { InvalidAmount, NativeValueWithERC, InvalidConfig } from "./GenericErrors.sol";
import { Swapper } from "./Swapper.sol";

// @title Across Facet
/// @author LI.FI (https://li.fi)
/// @notice Provides functionality for bridging through Across Protocol
contract AcrossFacet is ILiFi, ReentrancyGuard, Swapper {
    /// Storage ///
    bytes32 internal constant NAMESPACE = hex"c2f0b34693bd32d5a7baf53803100a174650293fd2f4c4bad2415c582c046d46"; // keccak256("com.lifi.facets.across");
    struct Storage {
        // solhint-disable-next-line var-name-mixedcase
        address ZERO_ADDRESS;
        // solhint-disable-next-line var-name-mixedcase
        address WETH;
        // solhint-disable-next-line var-name-mixedcase
        address SPOKE_POOL;
    }

    /// Types ///

    struct AcrossData {
        address recipient;
        address token;
        uint256 amount;
        uint256 destinationChainId;
        uint64 relayerFeePct;
        uint32 quoteTimestamp;
    }

    /// Errors ///

    error UseWethInstead();

    /// Events ///

    event AcrossInitialized(address weth, address spokePool);

    /// Init ///

    /// @notice Initializes local variables for the Across facet
    /// @param _weth WETH contract address for the current chain
    /// @param _spokePool Across spoke pool contract address
    function initAcross(address _weth, address _spokePool) external {
        LibDiamond.enforceIsContractOwner();
        Storage storage s = getStorage();
        s.ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;
        s.WETH = _weth;
        s.SPOKE_POOL = _spokePool;
        emit AcrossInitialized(_weth, _spokePool);
    }

    /// External Methods ///

    /// @notice Bridges tokens via Across
    /// @param _lifiData data used purely for tracking and analytics
    /// @param _acrossData data specific to Across
    function startBridgeTokensViaAcross(LiFiData memory _lifiData, AcrossData calldata _acrossData)
        external
        payable
        nonReentrant
    {
        LibAsset.depositAsset(_acrossData.token, _acrossData.amount);
        _startBridge(_acrossData);

        emit LiFiTransferStarted(
            _lifiData.transactionId,
            "across",
            "",
            _lifiData.integrator,
            _lifiData.referrer,
            _acrossData.token,
            _lifiData.receivingAssetId,
            _acrossData.recipient,
            _acrossData.amount,
            _lifiData.destinationChainId,
            false,
            false
        );
    }

    /// @notice Performs a swap before bridging via Across
    /// @param _lifiData data used purely for tracking and analytics
    /// @param _swapData an array of swap related data for performing swaps before bridging
    /// @param _acrossData data specific to Across
    function swapAndStartBridgeTokensViaAcross(
        LiFiData calldata _lifiData,
        LibSwap.SwapData[] calldata _swapData,
        AcrossData memory _acrossData
    ) external payable nonReentrant {
        _acrossData.amount = _executeAndCheckSwaps(_lifiData, _swapData);
        _startBridge(_acrossData);

        emit LiFiTransferStarted(
            _lifiData.transactionId,
            "across",
            "",
            _lifiData.integrator,
            _lifiData.referrer,
            _swapData[0].sendingAssetId,
            _lifiData.receivingAssetId,
            _acrossData.recipient,
            _swapData[0].fromAmount,
            _lifiData.destinationChainId,
            true,
            false
        );
    }

    /// External Methods ///

    /// @notice Sets WETH contract address
    /// @param _weth the WETH contract address for the current chain
    function setWeth(address _weth) external {
        LibDiamond.enforceIsContractOwner();
        Storage storage s = getStorage();
        s.WETH = _weth;
    }

    /// @notice Sets spoke pool contract address
    /// @param _spokePool Across spoke pool contract address
    function setSpokePool(address _spokePool) external {
        LibDiamond.enforceIsContractOwner();
        Storage storage s = getStorage();
        s.SPOKE_POOL = _spokePool;
    }

    /// Internal Methods ///

    /// @dev Contains the business logic for the bridge via Across
    /// @param _acrossData data specific to Across
    function _startBridge(AcrossData memory _acrossData) internal {
        Storage storage s = getStorage();
        if (_acrossData.token == s.ZERO_ADDRESS) _acrossData.token = s.WETH;
        else LibAsset.maxApproveERC20(IERC20(_acrossData.token), s.SPOKE_POOL, _acrossData.amount);
        IAcrossSpokePool pool = IAcrossSpokePool(s.SPOKE_POOL);
        pool.deposit{ value: msg.value }(
            _acrossData.recipient,
            _acrossData.token,
            _acrossData.amount,
            _acrossData.destinationChainId,
            _acrossData.relayerFeePct,
            _acrossData.quoteTimestamp
        );
    }

    /// @dev fetch local storage
    function getStorage() private pure returns (Storage storage s) {
        bytes32 namespace = NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}

