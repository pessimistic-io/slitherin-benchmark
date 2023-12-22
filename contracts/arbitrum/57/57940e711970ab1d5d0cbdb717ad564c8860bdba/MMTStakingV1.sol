// SPDX-License-Identifier: MIT
import "./NftInterfaceV5.sol";
import "./TokenInterfaceV5.sol";
import "./MMTStaking.sol";
pragma solidity 0.8.10;

contract MMTStakingV1 is MMTStaking {
    function setToken(TokenInterfaceV5 _token) public onlyGov {
        token = _token;
    }
}

