/**
 * Copyright 2017-2021, bZxDao. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0.
 */

pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "./State.sol";
import "./PausableGuardian.sol";


contract ProtocolPausableGuardian is State, PausableGuardian {

    function initialize(
        address target)
        external
        onlyOwner
    {
        _setTarget(this._isPaused.selector, target);
        _setTarget(this.toggleFunctionPause.selector, target);
        _setTarget(this.toggleFunctionUnPause.selector, target);
        _setTarget(this.changeGuardian.selector, target);
        _setTarget(this.getGuardian.selector, target);
    }
}

