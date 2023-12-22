// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "./BaseProxyContract.sol";
import "./IRangoHyphen.sol";

/// @title The functions that allow users to perform a hyphen call
/// @author Hellboy
/// @notice It contains functions to call hyphenBridge for bridging funds between chains
/// @dev This contract only handles the DEX part and calls RangoHyphen.sol functions via contact call to perform the bridging step
contract RangoHyphenProxy is BaseProxyContract {

    //keccak256("exchange.rango.hyphen.proxy")
    bytes32 internal constant RANGO_HYPHEN_PROXY_NAMESPACE = hex"a2cc4f41cf11b520eef4f1381031d11e095bbe59b53dc2a554b45e899a0f9f81";

    struct HyphenProxyStorage {
        address rangoHyphenAddress;
    }

    /// @notice Notifies that the RangoHyphen.sol contract address is updated
    /// @param _oldAddress The previous deployed address
    /// @param _newAddress The new deployed address
    event RangoHyphenAddressUpdated(address _oldAddress, address _newAddress);

    /// @notice Updates the address of deployed RangoHyphen.sol contract
    /// @param _address The address of rangoHyphen contract
    function updateRangoHyphenAddress(address _address) external onlyOwner {
        HyphenProxyStorage storage hyphenProxyStorage = getHyphenProxyStorage();
        address oldAddress = hyphenProxyStorage.rangoHyphenAddress;
        hyphenProxyStorage.rangoHyphenAddress = _address;

        emit RangoHyphenAddressUpdated(oldAddress, _address);
    }

    /// @param receiver The receiver address in the destination chain
    /// @param toChainId The network id of destination chain, ex: 56 for BSC
    struct HyphenBridgeRequest {
        address receiver;
        uint256 toChainId;
    }

    /// @notice Executes a DEX (arbitrary) call + a hyphen bridge function
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest data related to hyphen bridge
    /// @dev The hyphen bridge part is handled in the RangoHyphen.sol contract
    /// @dev If this function is a success, user will automatically receive the fund in the destination in their wallet (_receiver)
    function hyphenBridge(
        SwapRequest memory request,
        Call[] calldata calls,
        HyphenBridgeRequest memory bridgeRequest
    ) external payable whenNotPaused nonReentrant {
        HyphenProxyStorage storage hyphenProxyStorage = getHyphenProxyStorage();
        require(hyphenProxyStorage.rangoHyphenAddress != NULL_ADDRESS, 'hyphen address in Rango contract not set');
        bool isNative = request.fromToken == NULL_ADDRESS;
        uint minimumRequiredValue = isNative ? request.feeIn + request.affiliateIn + request.amountIn : 0;
        require(msg.value >= minimumRequiredValue, 'Send more ETH to cover input amount');

        (, uint out) = onChainSwapsInternal(request, calls);

        if (request.toToken != NULL_ADDRESS)
            approve(request.toToken, hyphenProxyStorage.rangoHyphenAddress, out);

        IRangoHyphen(hyphenProxyStorage.rangoHyphenAddress).hyphenBridge(bridgeRequest.receiver, request.toToken, out, bridgeRequest.toChainId);
    }

    /// @notice A utility function to fetch storage from a predefined random slot using assembly
    /// @return s The storage object
    function getHyphenProxyStorage() internal pure returns (HyphenProxyStorage storage s) {
        bytes32 namespace = RANGO_HYPHEN_PROXY_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}
