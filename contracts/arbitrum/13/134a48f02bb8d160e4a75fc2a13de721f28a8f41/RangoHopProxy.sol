// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "./BaseProxyContract.sol";
import "./IRangoHop.sol";
import "./RangoHopModels.sol";

/// @title The functions that allow users to perform a Hop call with or without some arbitrary DEX calls
/// @author Uchiha Sasuke
/// @notice It contains functions to call Hop bridge
/// @dev This contract only handles the DEX part and calls RangoHop.sol functions via contact call to perform the bridiging step
contract RangoHopProxy is BaseProxyContract {

    /// @dev keccak256("exchange.rango.hop.proxy")
    bytes32 internal constant RANGO_HOP_PROXY_NAMESPACE = hex"15410819d7d6216709939083a650939157bf8023516c3537a5272f9c42b704a2";

    struct HopProxyStorage {
        address rangoHopAddress;
    }

    /// @notice Notifies that the RangoHop.sol contract address is updated
    /// @param _oldAddress The previous deployed address
    /// @param _newAddress The new deployed address
    event RangoHopAddressUpdated(address _oldAddress, address _newAddress);

    /// @notice Updates the address of deployed RangoHop.sol contract
    /// @param _address The address
    function updateRangoHopAddress(address _address) external onlyOwner {
        HopProxyStorage storage proxyStorage = getHopProxyStorage();

        address oldAddress = proxyStorage.rangoHopAddress;
        proxyStorage.rangoHopAddress = _address;

        emit RangoHopAddressUpdated(oldAddress, _address);
    }

    /// @notice Executes a DEX (arbitrary) call + a Hop bridge call
    /// @dev The bridge part is handled in the RangoHop.sol contract
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest required data for the bridging step, including the destination chain and recipient wallet address
    function hopBridge(
        SwapRequest memory request,
        Call[] calldata calls,
        RangoHopModels.HopRequest memory bridgeRequest
    ) external payable whenNotPaused nonReentrant {
        HopProxyStorage storage proxyStorage = getHopProxyStorage();
        require(proxyStorage.rangoHopAddress != NULL_ADDRESS, 'Hop address in Rango contract not set');

        bool isNative = request.fromToken == NULL_ADDRESS;
        uint minimumRequiredValue = isNative ? request.feeIn + request.affiliateIn + request.amountIn : 0;
        require(msg.value >= minimumRequiredValue, 'Send more ETH to cover input amount + fee');

        (, uint out) = onChainSwapsInternal(request, calls);
        if (request.toToken != NULL_ADDRESS)
            approve(request.toToken, proxyStorage.rangoHopAddress, out);

        uint value = request.toToken == NULL_ADDRESS ? (out > 0 ? out : request.amountIn) : 0;

        IRangoHop(proxyStorage.rangoHopAddress).hopBridge{value: value}(bridgeRequest, request.toToken, out);
    }

    /// @notice A utility function to fetch storage from a predefined random slot using assembly
    /// @return s The storage object
    function getHopProxyStorage() internal pure returns (HopProxyStorage storage s) {
        bytes32 namespace = RANGO_HOP_PROXY_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}
