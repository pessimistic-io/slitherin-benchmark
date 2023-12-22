// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./Dev.sol";

abstract contract BlackList is Dev {
    mapping(address => bool) private list;

    function setBlackList(
        address[] memory _evilUsers,
        bool _is
    ) external onlyManger {
        for (uint256 i = 0; i < _evilUsers.length; i++) {
            list[_evilUsers[i]] = _is;
        }
    }

    function getBlackListStatus(address _maker) public view returns (bool) {
        return list[_maker];
    }
}

