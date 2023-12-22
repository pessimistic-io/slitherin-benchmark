

//SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./ISidPriceOracle.sol";

interface IARBRegistrarControllerV2 {
    function rentPrice(string memory, uint256)
        external
        view
        returns (ISidPriceOracle.Price memory);

    function available(string memory) external returns (bool);

    function rentPrice(string memory, uint256, address)
        external
        view
        returns (ISidPriceOracle.Price memory);

    function makeCommitment(
        string memory,
        address,
        bytes32
    ) external pure returns (bytes32);

    function commit(bytes32) external;

    function registerWithConfig(
        string calldata,
        address,
        uint256,
        bytes32,
        address,
        bool
    ) external payable;

    function registerWithConfigAndPoint(
        string calldata,
        address,
        uint256,
        bytes32,
        address,
        bool,
        bool
    ) external payable;

    function renew(string calldata, uint256) external payable;

    function renewWithPoint(string calldata, uint256, bool)
        external
        payable;
}
