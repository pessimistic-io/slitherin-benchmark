pragma solidity >=0.6.0 <0.8.0;

import "./BeaconProxy.sol";

contract ClonableBeaconProxy is BeaconProxy {
    constructor() public BeaconProxy(msg.sender, "") {}
}
