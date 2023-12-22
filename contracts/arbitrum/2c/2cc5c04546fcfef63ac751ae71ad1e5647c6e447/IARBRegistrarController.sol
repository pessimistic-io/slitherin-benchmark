

//SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./IPriceOracle.sol";

interface IARBRegistrarController {
    function rentPrice(string memory, uint256)
        external
        view
        returns (IPriceOracle.Price memory);

    function available(string memory) external returns (bool);

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

    function renew(string calldata, uint256) external payable;
}
