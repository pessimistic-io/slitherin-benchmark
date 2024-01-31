pragma solidity >=0.5.0;

interface IRudaV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function WLOn() external view returns (bool);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;

    function addAddressToWL(address, bool) external;
    function WLControl(bool) external;
    function getWLaddress(address _address) external view returns (bool);
}

