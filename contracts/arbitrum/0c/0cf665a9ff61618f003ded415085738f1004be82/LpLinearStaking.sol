//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.18;

import {SpartaDexPair} from "./SpartaDexPair.sol";
import {LinearStaking} from "./LinearStaking.sol";
import {IERC20} from "./IERC20.sol";
import {IAccessControl} from "./IAccessControl.sol";

contract LpLinearStaking is LinearStaking {
    constructor(
        SpartaDexPair _lpToken,
        IERC20 _reward,
        IAccessControl _acl,
        address _treasury,
        uint256 _value
    )
        LinearStaking(
            IERC20(address(_lpToken)),
            _reward,
            _acl,
            _treasury,
            _value
        )
    {}
}

