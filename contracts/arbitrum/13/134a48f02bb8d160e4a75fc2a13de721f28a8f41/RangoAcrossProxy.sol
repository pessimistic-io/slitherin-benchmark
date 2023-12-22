// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "./BaseProxyContract.sol";
import "./IRangoAcross.sol";

/// @title The functions that allow users to perform an Across call with or without some arbitrary DEX calls
/// @author Uchiha Sasuke
/// @notice It contains functions to call Across bridge
/// @dev This contract only handles the DEX part and calls RangoAcross.sol functions via contact call to perform the bridiging step
contract RangoAcrossProxy is BaseProxyContract {

    /// @dev keccak256("exchange.rango.across.proxy")
    bytes32 internal constant RANGO_ACROSS_PROXY_NAMESPACE = hex"677e79f0e4009f1792a10267078e7120af47266c8ce03085f21aef7ba016b06f";

    struct AcrossProxyStorage {
        address rangoAcrossAddress;
    }

    /// @notice Notifies that the RangoAcross.sol contract address is updated
    /// @param _oldAddress The previous deployed address
    /// @param _newAddress The new deployed address
    event RangoAcrossAddressUpdated(address _oldAddress, address _newAddress);

    /// @notice The request object for Across bridge call
    /// @param spokePoolAddress The address of Across spoke pool that deposit should be done to
    /// @param recipient Address to receive funds at on destination chain.
    /// @param originToken Token to lock into this contract to initiate deposit.
    /// @param destinationChainId Denotes network where user will receive funds from SpokePool by a relayer.
    /// @param relayerFeePct % of deposit amount taken out to incentivize a fast relayer.
    /// @param quoteTimestamp Timestamp used by relayers to compute this deposit's realizedLPFeePct which is paid to LP pool on HubPool.
    struct AcrossBridgeRequest {
        address spokePoolAddress;
        address recipient;
        address originToken;
        uint256 destinationChainId;
        uint64 relayerFeePct;
        uint32 quoteTimestamp;
    }

    /// @notice Updates the address of deployed RangoAcross.sol contract
    /// @param _address The address
    function updateRangoAcrossAddress(address _address) external onlyOwner {
        AcrossProxyStorage storage acrossProxyStorage = getAcrossProxyStorage();

        address oldAddress = acrossProxyStorage.rangoAcrossAddress;
        acrossProxyStorage.rangoAcrossAddress = _address;

        emit RangoAcrossAddressUpdated(oldAddress, _address);
    }

    /// @notice Executes a DEX (arbitrary) call + a Across bridge call
    /// @dev The bridge part is handled in the RangoAcross.sol contract
    /// @param request The general swap request containing from/to token and fee/affiliate rewards
    /// @param calls The list of DEX calls, if this list is empty, it means that there is no DEX call and we are only bridging
    /// @param bridgeRequest required data for the bridging step, including the destination chain and recipient wallet address
    function acrossBridge(
        SwapRequest memory request,
        Call[] calldata calls,
        AcrossBridgeRequest memory bridgeRequest
    ) external payable whenNotPaused nonReentrant {
        AcrossProxyStorage storage proxyStorage = getAcrossProxyStorage();
        require(proxyStorage.rangoAcrossAddress != NULL_ADDRESS, 'Across address in Rango contract not set');

        bool isNative = request.fromToken == NULL_ADDRESS;
        uint minimumRequiredValue = isNative ? request.feeIn + request.affiliateIn + request.amountIn : 0;
        require(msg.value >= minimumRequiredValue, 'Send more ETH to cover input amount + fee');

        (, uint out) = onChainSwapsInternal(request, calls);
        if (request.toToken != NULL_ADDRESS)
            approve(request.toToken, proxyStorage.rangoAcrossAddress, out);

        uint value = request.toToken == NULL_ADDRESS ? (out > 0 ? out : request.amountIn) : 0;

        IRangoAcross(proxyStorage.rangoAcrossAddress).acrossBridge{value: value}(
            bridgeRequest.spokePoolAddress,
            request.toToken,
            bridgeRequest.recipient,
            bridgeRequest.originToken,
            out,
            bridgeRequest.destinationChainId,
            bridgeRequest.relayerFeePct,
            bridgeRequest.quoteTimestamp
        );
    }

    /// @notice A utility function to fetch storage from a predefined random slot using assembly
    /// @return s The storage object
    function getAcrossProxyStorage() internal pure returns (AcrossProxyStorage storage s) {
        bytes32 namespace = RANGO_ACROSS_PROXY_NAMESPACE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := namespace
        }
    }
}
