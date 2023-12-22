// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface ISgBridge {
    error TokenNotSupported(address token, uint16 destChainId);

    event Bridge(uint16 indexed chainId, uint256 amount);

    function initialize(address _router, uint16 _currentChainId) external;

    function setRouter(address _router) external;

    function setSlippage(uint256 _slippage) external;

    function setDstGasForCall(uint256 _dstGasForCall) external;

    function setCurrentChainId(uint16 _currentChainId) external;

    function setStargatePoolId(
        address _token,
        uint16 _chainId,
        uint256 _poolId
    ) external;

    function revokeFunds() external;

    function bridge(
        address _token,
        uint256 _amount,
        uint16 _destChainId,
        address _destinationAddress,
        bytes memory _message
    ) external payable;

    function feeForBridge(
        uint16 _destChainId,
        address _destinationContract,
        bytes memory _payload
    ) external view returns (uint256);
}

