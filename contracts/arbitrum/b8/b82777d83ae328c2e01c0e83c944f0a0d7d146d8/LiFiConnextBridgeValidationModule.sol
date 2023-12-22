// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {decodeExecuteCallOpCalldata} from "./DecodeUtils.sol";
import {ECDSA} from "./ECDSA.sol";
import {UserOperation, ISessionValidationModule} from "./ISessionValidationModule.sol";

interface ILiFi {
    struct BridgeData {
        bytes32 transactionId;
        string bridge;
        string integrator;
        address referrer;
        address sendingAssetId;
        address receiver;
        uint256 minAmount;
        uint256 destinationChainId;
        bool hasSourceSwaps;
        bool hasDestinationCall;
    }
}

interface IGenericSwapFacet {
    struct SwapData {
        address callTo;
        address approveTo;
        address sendingAssetId;
        address receivingAssetId;
        uint256 fromAmount;
        bytes callData;
        bool requiresDeposit;
    }

    /// @notice Performs multiple swaps in one transaction
    /// @param _transactionId the transaction id associated with the operation
    /// @param _integrator the name of the integrator
    /// @param _referrer the address of the referrer
    /// @param _receiver the address to receive the swapped tokens into (also excess tokens)
    /// @param _minAmount the minimum amount of the final asset to receive
    /// @param _swapData an object containing swap related data to perform swaps before bridging
    function swapTokensGeneric(
        bytes32 _transactionId,
        string calldata _integrator,
        string calldata _referrer,
        address payable _receiver,
        uint256 _minAmount,
        SwapData[] calldata _swapData
    ) external payable;
}

interface IAmarokFacet {
    /// @param callData The data to execute on the receiving chain. If no crosschain call is needed, then leave empty.
    /// @param callTo The address of the contract on dest chain that will receive bridged funds and execute data
    /// @param relayerFee The amount of relayer fee the tx called xcall with
    /// @param slippageTol Max bps of original due to slippage (i.e. would be 9995 to tolerate .05% slippage)
    /// @param delegate Destination delegate address
    /// @param destChainDomainId The Amarok-specific domainId of the destination chain
    /// @param payFeeWithSendingAsset Whether to pay the relayer fee with the sending asset or not
    struct AmarokData {
        bytes callData;
        address callTo;
        uint256 relayerFee;
        uint256 slippageTol;
        address delegate;
        uint32 destChainDomainId;
        bool payFeeWithSendingAsset;
    }

    /// @notice Bridges tokens via Amarok
    /// @param _bridgeData Data containing core information for bridging
    /// @param _amarokData Data specific to bridge
    function startBridgeTokensViaAmarok(
        ILiFi.BridgeData calldata _bridgeData,
        AmarokData calldata _amarokData
    ) external payable;

    /// @notice Performs a swap before bridging via Amarok
    /// @param _bridgeData The core information needed for bridging
    /// @param _swapData An array of swap related data for performing swaps before bridging
    /// @param _amarokData Data specific to Amarok
    function swapAndStartBridgeTokensViaAmarok(
        ILiFi.BridgeData memory _bridgeData,
        IGenericSwapFacet.SwapData[] calldata _swapData,
        AmarokData calldata _amarokData
    ) external payable;
}

contract LiFiConnextBridgeValidationModule is ISessionValidationModule {
    uint256 constant MAX_SLIPPAGE_TOL = 300;

    /// @dev same on all chains, single entrypoint
    address constant LIFI_DIAMOND =
        address(0x1231DEB6f5749EF6cE6943a275A1D3E7486F4EaE);
    /// @dev same on all chains, used as temporary receiver on dst chain to execute swaps
    address constant LIFI_RECEIVER =
        address(0x5439f8ca43f832DD21a28C5BF038dad4c07ad02c);

    /**
     * @dev validates if the _op (UserOperation) matches the SessionKey permissions
     * and that _op has been signed by this SessionKey
     * Please mind the decimals of your exact token when setting maxAmount
     * @param _op User Operation to be validated.
     * @param _userOpHash Hash of the User Operation to be validated.
     * @param _sessionKeyData SessionKey data, that describes sessionKey permissions
     * @param _sessionKeySignature Signature over the the _userOpHash.
     * @return true if the _op is valid, false otherwise.
     */
    function validateSessionUserOp(
        UserOperation calldata _op,
        bytes32 _userOpHash,
        bytes calldata _sessionKeyData,
        bytes calldata _sessionKeySignature
    ) external pure override returns (bool) {
        revert("LiFiConnextBridgeValidationModule: Not Implemented");
    }

    /**
     * @dev validates that the call (destinationContract, callValue, funcCallData)
     * complies with the Session Key permissions represented by sessionKeyData
     * @param destinationContract address of the contract to be called
     * @param callValue value to be sent with the call
     * @param _funcCallData the data for the call. is parsed inside the SVM
     * @param _sessionKeyData SessionKey data, that describes sessionKey permissions
     */
    function validateSessionParams(
        address destinationContract,
        uint256 callValue,
        bytes calldata _funcCallData,
        bytes calldata _sessionKeyData,
        bytes calldata _callSpecificData
    ) external virtual override returns (address) {
        address sender = address(bytes20(_sessionKeyData[20:40]));

        // bytes (bytes4 selector + padded address of 32 bytes + uint256 of 32 bytes + offset of bytes32 + length of bytes32 + bytes4 of selector) i.e. 4+32+32+32+32 = 132 to 132+4 = 136
        bytes4 selector = bytes4(_funcCallData[0:4]);

        // bytes (bytes4 selector + padded address of 32 bytes + uint256 of 32 bytes + offset of bytes32 + length of bytes32 + bytes4 of selector) i.e. 4+32+32+32+32+4 = 136 to end
        bytes calldata data = _funcCallData[4:];

        if (destinationContract != LIFI_DIAMOND)
            revert("LiFiConnextBridgeValidationModule: !destination");

        bool matched;

        if (selector == IGenericSwapFacet.swapTokensGeneric.selector) {
            matched = true;
            _validateSwap(data, sender);
        }

        if (selector == IAmarokFacet.startBridgeTokensViaAmarok.selector) {
            matched = true;
            _validateBridge(data, sender);
        }

        if (
            selector == IAmarokFacet.swapAndStartBridgeTokensViaAmarok.selector
        ) {
            matched = true;
            _validateSwapAndBridge(data, sender);
        }

        if (!matched) revert("LiFiConnextBridgeValidationModule: !selector");

        return address(bytes20(_sessionKeyData[:20]));
    }

    function _validateSwapData(
        IGenericSwapFacet.SwapData[] memory swapData
    ) internal view {
        // TODO: cap slippage
    }

    function _validateSwap(
        bytes calldata _calldata,
        address opSender
    ) internal view {
        (
            ,
            ,
            ,
            address receiver,
            ,
            IGenericSwapFacet.SwapData[] memory swapData
        ) = abi.decode(
                _calldata,
                (
                    bytes32,
                    string,
                    string,
                    address,
                    uint256,
                    IGenericSwapFacet.SwapData[]
                )
            );

        if (receiver != opSender)
            revert("LiFiConnextBridgeValidationModule: !receiver");

        _validateSwapData(swapData);
    }

    function _validateBridgeData(
        ILiFi.BridgeData memory bridgeData,
        IAmarokFacet.AmarokData memory amarokData,
        address opSender
    ) internal view {
        if (
            keccak256(abi.encodePacked(bridgeData.bridge)) !=
            keccak256(abi.encodePacked("amarok"))
        ) revert("LiFiConnextBridgeValidationModule: !bridge");

        if (bridgeData.receiver != opSender)
            revert("LiFiConnextBridgeValidationModule: !receiver");

        if (
            bridgeData.destinationChainId == block.chainid ||
            (bridgeData.destinationChainId != 10 &&
                bridgeData.destinationChainId != 137 &&
                bridgeData.destinationChainId != 42161)
        ) revert("LiFiConnextBridgeValidationModule: !chainId");

        if (bridgeData.hasDestinationCall && amarokData.callTo != LIFI_RECEIVER)
            revert("LiFiConnextBridgeValidationModule: !dstCall");

        if (amarokData.slippageTol > MAX_SLIPPAGE_TOL)
            revert("LiFiConnextBridgeValidationModule: !slippage");

        // TODO: evaluate if delegate can be checked against

        // TODO: decode destination calldata and cap slippage
    }

    function _validateBridge(
        bytes calldata _calldata,
        address opSender
    ) internal view {
        (
            ILiFi.BridgeData memory bridgeData,
            IAmarokFacet.AmarokData memory amarokData
        ) = abi.decode(_calldata, (ILiFi.BridgeData, IAmarokFacet.AmarokData));

        _validateBridgeData(bridgeData, amarokData, opSender);
    }

    function _validateSwapAndBridge(
        bytes calldata _calldata,
        address opSender
    ) internal view {
        (
            ILiFi.BridgeData memory bridgeData,
            IGenericSwapFacet.SwapData[] memory swapData,
            IAmarokFacet.AmarokData memory amarokData
        ) = abi.decode(
                _calldata,
                (
                    ILiFi.BridgeData,
                    IGenericSwapFacet.SwapData[],
                    IAmarokFacet.AmarokData
                )
            );

        _validateSwapData(swapData);
        _validateBridgeData(bridgeData, amarokData, opSender);
    }
}

