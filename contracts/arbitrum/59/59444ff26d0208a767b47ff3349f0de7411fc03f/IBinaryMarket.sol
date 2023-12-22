// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./IOracle.sol";
import "./IBinaryVault.sol";

interface IBinaryMarket {
    function oracle() external view returns (IOracle);

    function vault() external view returns (IBinaryVault);

    function marketName() external view returns (string memory);
}

