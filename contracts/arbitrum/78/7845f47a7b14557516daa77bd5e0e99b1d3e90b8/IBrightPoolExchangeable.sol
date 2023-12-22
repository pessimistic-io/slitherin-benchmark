pragma solidity 0.8.16;

import "./IBrightPoolConsumer.sol";
import "./IBrightPoolLedger.sol";

interface IBrightPoolExchangeable {
    function exchange(IBrightPoolConsumer consumer_, IBrightPoolLedger.Order memory order_, uint256 bestExchange_)
        external
        payable;
}

