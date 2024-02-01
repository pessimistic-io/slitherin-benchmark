pragma solidity ^0.5.17;
pragma experimental ABIEncoderV2;

import "./Decimal.sol";

contract IOracle {
    function update() public;
    function consult() public returns (Decimal.D256 memory, bool);
    function averageDollarPrice() public returns (Decimal.D256 memory, bool);

    function pair() external view returns (address);
}
