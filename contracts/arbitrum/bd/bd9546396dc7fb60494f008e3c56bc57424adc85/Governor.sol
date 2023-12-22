// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";

contract Governor is UUPSUpgradeable {
    address public owner;

    uint256 public kickoff;

    function initialize(address owner_) external {
        require(owner == address(0));
        owner = owner_;
    }

    function setOwner(address owner_) external {
        require(msg.sender == owner, "Aloe: only owner");
        owner = owner_;
    }

    function setRewardsRate(
        address factory,
        address lender,
        uint64 rate
    ) external {
        require(msg.sender == owner, "Aloe: only owner");
        (bool success, ) = factory.call(
            abi.encodeWithSignature(
                "governRewardsRate(address,uint64)",
                lender,
                rate
            )
        );
        require(success);
    }

    function call(address target, bytes calldata data) external {
        require(msg.sender == owner, "Aloe: only owner");
        require(kickoff == 0, "Aloe: too late");
        (bool success, ) = target.call(data);
        require(success);
    }

    function setKickoff(uint256 kickoff_) external {
        require(msg.sender == owner, "Aloe: only owner");
        require(kickoff == 0, "Aloe: too late");
        kickoff = kickoff_;
    }

    function _authorizeUpgrade(address) internal view override {
        require(msg.sender == owner, "Aloe: only owner");
        require(kickoff != 0 && block.timestamp > kickoff, "Aloe: too soon");
    }
}

