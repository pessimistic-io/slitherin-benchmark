// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./EnumerableMap.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";

import "./IFactorMsgSendEndpoint.sol";
import "./ILayerZeroEndpoint.sol";
import "./LayerZeroHelper.sol";

/**
 * @dev Initially, currently we will use layer zero's default send and receive version (which is most updated)
 * So we can leave the configuration unset.
 */

contract FactorMsgSendEndpoint is IFactorMsgSendEndpoint, OwnableUpgradeable {
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    error OnlyWhitelisted();

    address payable public refundAddress;
    ILayerZeroEndpoint public lzEndpoint;

    mapping(address => bool) public isWhitelisted;
    EnumerableMap.UintToAddressMap internal receiveEndpoints;

    modifier onlyWhitelisted() {
        if (!isWhitelisted[msg.sender]) revert OnlyWhitelisted();
        _;
    }

    function initialize(address _refundAddress, address _lzEndpoint) public initializer {
        __Ownable_init(msg.sender);

        refundAddress = payable(_refundAddress);
        lzEndpoint = ILayerZeroEndpoint(_lzEndpoint);
    }

    function calcFee(
        address dstAddress,
        uint256 dstChainId,
        bytes memory payload,
        uint256 estimatedGasAmount
    ) external view returns (uint256 fee) {
        (fee, ) = lzEndpoint.estimateFees(
            LayerZeroHelper._getLayerZeroChainIds(dstChainId),
            receiveEndpoints.get(dstChainId),
            abi.encode(dstAddress, payload),
            false,
            _getAdapterParams(estimatedGasAmount)
        );
    }

    function sendMessage(
        address dstAddress,
        uint256 dstChainId,
        bytes calldata payload,
        uint256 estimatedGasAmount
    ) external payable onlyWhitelisted {
        bytes memory path = abi.encodePacked(receiveEndpoints.get(dstChainId), address(this));

        lzEndpoint.send{ value: msg.value }(
            LayerZeroHelper._getLayerZeroChainIds(dstChainId),
            path,
            abi.encode(dstAddress, payload),
            refundAddress,
            address(0),
            _getAdapterParams(estimatedGasAmount)
        );
    }

    function addReceiveEndpoints(address endpointAddr, uint256 endpointChainId) external payable onlyOwner {
        receiveEndpoints.set(endpointChainId, endpointAddr);
    }

    function setWhitelisted(address addr, bool status) external onlyOwner {
        isWhitelisted[addr] = status;
    }

    function setLzSendVersion(uint16 _newVersion) external onlyOwner {
        lzEndpoint.setSendVersion(_newVersion);
    }

    function getAllReceiveEndpoints() external view returns (uint256[] memory chainIds, address[] memory addrs) {
        uint256 length = receiveEndpoints.length();
        chainIds = new uint256[](length);
        addrs = new address[](length);

        for (uint256 i = 0; i < length; ++i) {
            (chainIds[i], addrs[i]) = receiveEndpoints.at(i);
        }
    }

    function _getAdapterParams(uint256 estimatedGasAmount) internal pure returns (bytes memory adapterParams) {
        // this is more like "type" rather than version
        // It is the type of adapter params you want to pass to relayer
        adapterParams = abi.encodePacked(uint16(1), estimatedGasAmount);
    }
}

