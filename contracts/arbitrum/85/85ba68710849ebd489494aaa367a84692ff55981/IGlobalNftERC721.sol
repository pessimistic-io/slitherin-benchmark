pragma solidity ^0.8.0;

interface IGlobalNft {
    function initialize(address _bridge, uint64 _originChain, bool _originIsERC1155, address _originAddr) external;

    function bridge() external view returns (address);

    function originChain() external view returns (uint64);

    function originIsERC1155() external view returns (bool);

    function originAddr() external view returns (address);
}

