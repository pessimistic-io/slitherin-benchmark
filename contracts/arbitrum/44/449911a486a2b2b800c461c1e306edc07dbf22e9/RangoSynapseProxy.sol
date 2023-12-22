// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "./IRangoSynapse.sol";
import "./BaseProxyContract.sol";
import "./RangoSynapseModels.sol";

/// @title The functions that allow users to perform a Synapse Bridge call with or without some arbitrary DEX calls
/// @author Rango DeXter
/// @notice It contains functions to call Synapse Bridge
/// @dev This contract only handles the DEX part and calls RangoSynapse.sol functions via contact call to perform the bridiging step
contract RangoSynapseProxy is BaseProxyContract {

    /// @dev keccak256("exchange.rango.synapse.proxy")
    bytes32 internal constant RANGO_SYNAPSE_PROXY_NAMESPACE = hex"7dc8ccf29e8b10d28e02c4846353748fbada8a9e309da5c2ec784c1a746210f8";

    struct SynapseProxyStorage {
        address rangoSynapseAddress;
    }

    /// @notice Updates the address of deployed RangoSynapse.sol contract
    /// @param _address The address
    function updateRangoSynapseAddress(address _address) external onlyOwner {
        SynapseProxyStorage storage proxyStorage = getSynapseProxyStorage();
        proxyStorage.rangoSynapseAddress = _address;
    }

    /// @notice Executes a DEX (arbitrary) call + a Synapse bridge call
    /// @dev The Synapse part is handled in the RangoSynapse.sol contract
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest required data for the bridging step, including the destination chain and recipient wallet address
    function synapseBridge(
        SwapRequest memory request,
        Call[] calldata calls,
        RangoSynapseModels.SynapseBridgeRequest memory bridgeRequest
    ) external payable whenNotPaused nonReentrant {
        SynapseProxyStorage storage synapseStorage = getSynapseProxyStorage();
        require(synapseStorage.rangoSynapseAddress != NULL_ADDRESS, 'Synapse address in Rango contract not set');

        bool isNative = request.fromToken == NULL_ADDRESS;
        uint minimumRequiredValue = isNative ? request.feeIn + request.affiliateIn + request.amountIn : 0;
        require(msg.value >= minimumRequiredValue, 'Send more ETH to cover input amount + fee');

        (, uint out) = onChainSwapsInternal(request, calls);

        address bridgeFrom = calls.length > 0 ? request.toToken : request.fromToken;
        if (bridgeFrom != NULL_ADDRESS)
            approve(bridgeFrom, synapseStorage.rangoSynapseAddress, out);

        uint value = bridgeFrom == NULL_ADDRESS ? (out > 0 ? out : request.amountIn) : 0;

        IRangoSynapse(synapseStorage.rangoSynapseAddress).synapseBridge{value : value}(
            bridgeFrom,
            out,
            bridgeRequest
        );
    }

    /// @notice A utility function to fetch storage from a predefined random slot using assembly
    /// @return s The storage object
    function getSynapseProxyStorage() internal pure returns (SynapseProxyStorage storage s) {
        bytes32 namespace = RANGO_SYNAPSE_PROXY_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}
