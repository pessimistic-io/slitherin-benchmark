// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

interface IDexSwapFactory {
    event ContractsWhitelistAdded(address[] contracts);
    event ContractsWhitelistRemoved(address[] contracts);
    event FeeUpdated(uint256 fee);
    event ProtocolShareUpdated(uint256 share);
    event FeePairUpdated(address indexed token0, address indexed token1, uint256 fee);
    event ProtocolSharePairUpdated(address indexed token0, address indexed token1, uint256 share);
    event FeeWhitelistAdded(address[] accounts);
    event FeeWhitelistRemoved(address[] accounts);
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);
    event PeripheryWhitelistAdded(address[] periphery);
    event PeripheryWhitelistRemoved(address[] periphery);
    event Skimmed(address indexed token0, address indexed token1, address to);

    function INIT_CODE_PAIR_HASH() external view returns (bytes32);

    function contractsWhitelistList(uint256 offset, uint256 limit) external view returns (address[] memory output);

    function contractsWhitelist(uint256 index) external view returns (address);

    function contractsWhitelistContains(address contract_) external view returns (bool);

    function contractsWhitelistCount() external view returns (uint256);

    function protocolShare() external view returns (uint256);

    function fee() external view returns (uint256);

    function feeWhitelistList(uint256 offset, uint256 limit) external view returns (address[] memory output);

    function feeWhitelist(uint256 index) external view returns (address);

    function feeWhitelistContains(address account) external view returns (bool);

    function feeWhitelistCount() external view returns (uint256);

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);

    function peripheryWhitelistList(uint256 offset, uint256 limit) external view returns (address[] memory output);

    function peripheryWhitelist(uint256 index) external view returns (address);

    function peripheryWhitelistContains(address account) external view returns (bool);

    function peripheryWhitelistCount() external view returns (uint256);

    function getPair(address tokenA, address tokenB) external view returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function addContractsWhitelist(address[] memory contracts) external returns (bool);

    function addFeeWhitelist(address[] memory accounts) external returns (bool);

    function addPeripheryWhitelist(address[] memory periphery) external returns (bool);

    function removeContractsWhitelist(address[] memory contracts) external returns (bool);

    function removeFeeWhitelist(address[] memory accounts) external returns (bool);

    function removePeripheryWhitelist(address[] memory periphery) external returns (bool);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function updateFee(uint256 fee_) external returns (bool);

    function updateProtocolShare(uint256 share) external returns (bool);

    function updateFeePair(address token0, address token1, uint256 fee_) external returns (bool);

    function updateProtocolSharePair(address token0, address token1, uint256 share) external returns (bool);

    function setFeeTo(address) external;

    function setFeeToSetter(address) external;

    function skim(address token0, address token1, address to) external returns (bool);
}

