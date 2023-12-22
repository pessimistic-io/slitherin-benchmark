// SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

import "./ILayerZeroEndpoint.sol";
import "./ILayerZeroReceiver.sol";

contract OmniCounter is ILayerZeroReceiver {
    ILayerZeroEndpoint public layerZeroEndpoint;

    bytes public constant PAYLOAD = "\x01\x02\x03\x04";
    constructor(address _lzEndpoint) {
        layerZeroEndpoint = ILayerZeroEndpoint(_lzEndpoint);
    }

    uint256 public counter;

    function estimateFee(uint16 _dstChainId, bool _useZro, bytes calldata _adapterParams) public view returns (uint nativeFee, uint zroFee) {
        return layerZeroEndpoint.estimateFees(_dstChainId, address(this), PAYLOAD, _useZro, _adapterParams);
    }

    function send(uint16 _dstChainId, bytes memory _dstAddress) public payable {
        layerZeroEndpoint.send{value : msg.value}(_dstChainId, _dstAddress, PAYLOAD, address(0), address(0), bytes(""));
    }

    function lzReceive(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes calldata _payload) public virtual override {
//        require(msg.sender == address(layerZeroEndpoint), "invalid endpoint caller");
        counter++;
    }

    function setConfig(uint16 _version, uint16 _chainId, uint _configType, bytes calldata _config) public {
        layerZeroEndpoint.setConfig(_version, _chainId, _configType, _config);
    }

    function getConfig(uint16 _version, uint16 _chainId, uint _configType) view public returns(bytes memory){
       return  layerZeroEndpoint.getConfig(_version, _chainId, address(this), _configType);
    }

    function setOracle(uint16 dstChainId, address oracle) external  {
        uint TYPE_ORACLE = 6;
        // set the Oracle
        layerZeroEndpoint.setConfig(layerZeroEndpoint.getSendVersion(address(this)), dstChainId, TYPE_ORACLE, abi.encode(oracle));
    }
}
