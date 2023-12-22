// SPDX-License-Identifier: MIT
import "./IOracle.sol";
import "./IBinaryVault.sol";

pragma solidity 0.8.18;

interface IBinaryMarket {
    function oracle() external view returns (IOracle);

    function vault() external view returns (IBinaryVault);

    function marketName() external view returns (string memory);
}

