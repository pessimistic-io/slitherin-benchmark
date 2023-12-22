// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import {BFacetOwner} from "./BFacetOwner.sol";
import {LibDiamond} from "./LibDiamond.sol";
import {LibExec} from "./LibExec.sol";

contract ExecAccessFacet is BFacetOwner {
    using LibDiamond for address;
    using LibExec for address;

    // ################ Callable by Gov ################
    function addExecutors(address[] calldata _executors) external onlyOwner {
        for (uint256 i; i < _executors.length; i++)
            require(_executors[i].addExecutor(), "ExecFacet.addExecutors");
    }

    function removeExecutors(address[] calldata _executors) external {
        for (uint256 i; i < _executors.length; i++) {
            require(
                msg.sender == _executors[i] || msg.sender.isContractOwner(),
                "ExecFacet.removeExecutors: msg.sender ! executor || owner"
            );
            require(
                _executors[i].removeExecutor(),
                "ExecFacet.removeExecutors"
            );
        }
    }

    function canExec(address _executor) external view returns (bool) {
        return _executor.canExec();
    }

    function isExecutor(address _executor) external view returns (bool) {
        return _executor.isExecutor();
    }

    function executors() external view returns (address[] memory) {
        return LibExec.executors();
    }

    function numberOfExecutors() external view returns (uint256) {
        return LibExec.numberOfExecutors();
    }
}

