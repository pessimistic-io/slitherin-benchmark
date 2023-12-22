/* solhint-disable */
// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

interface IUniswapV2FactoryCustomFee {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;

    // CUSTOM FEE: CUSTOM FEE FUNCTIONS
    function fee() external view returns (uint256);
    function owner() external view returns (uint256);
    function pendingOwner() external view returns (uint256);
    function setWhitelistStatus(address tokenA, address tokenB, address account, bool status) external;
}
/* solhint-enable */
