pragma solidity 0.6.6;

import {UpgradableProxy} from "./UpgradableProxy.sol";

contract EtherPredicateProxy is UpgradableProxy {
    constructor(address _proxyTo)
        public
        UpgradableProxy(_proxyTo)
    {}
}

