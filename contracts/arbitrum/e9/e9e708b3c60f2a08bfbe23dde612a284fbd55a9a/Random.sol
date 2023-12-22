// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;
import "./Ownable.sol";

/**
 * @title Owner
 * @dev Set & change owner
 */
abstract contract Random is Ownable {
    enum Status {
        UNKNOWN,
        WAITING,
        RESOLVED
    }

    address[] internal nodes;
    uint256 internalId;
    uint256[] private unresolved;
    event Request(uint256 internalId, uint256 id, address requestor);

    constructor() {
        internalId = 0;
    }

    function nodeIsAllowed(address n) internal view returns (bool) {
        for (uint256 i = 0; i < nodes.length; i++) {
            if (n == nodes[i]) {
                return true;
            }
        }
        return false;
    }

    function requestIsUnresolved(uint256 id) internal view returns (bool) {
        for (uint256 i = 0; i < unresolved.length; i++) {
            if (id == unresolved[i]) {
                return true;
            }
        }
        return false;
    }

    function requestRandomNumber(uint256 id) internal {
        ++internalId;
        unresolved.push(internalId);
        emit Request(internalId, id, address(this));
    }

    function reciveRandomNumberInternal(
        uint256 internalId_res,
        uint256 id,
        uint256 number
    ) public {
        require(nodeIsAllowed(msg.sender), "Not allowed node");
        require(
            requestIsUnresolved(internalId_res),
            "Request is not unresolved."
        );
        for (uint256 i = 0; i < unresolved.length; i++) {
            if (unresolved[i] == internalId_res) {
                unresolved[i] = unresolved[nodes.length - 1];
                unresolved.pop();
                break;
            }
        }
        reciveRandomNumber(id, number);
    }

    function reciveRandomNumber(uint256 id, uint256 number) internal virtual;

    function removeOracle(address addr) public onlyOwner {
        for (uint256 i = 0; i < nodes.length; i++) {
            if (nodes[i] == addr) {
                nodes[i] = nodes[nodes.length - 1];
                nodes.pop();
                return;
            }
        }
    }

    function addOracle(address addr) public onlyOwner {
        nodes.push(addr);
    }

    function getOracles() public view returns (address[] memory) {
        return nodes;
    }

    function getUnresolved() public view returns (uint256[] memory) {
        return unresolved;
    }
}

