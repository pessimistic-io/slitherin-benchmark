// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;
import "./IBinaryMarket.sol";

interface IBinaryMarketManager {
    function registerMarket(IBinaryMarket market) external;
}

