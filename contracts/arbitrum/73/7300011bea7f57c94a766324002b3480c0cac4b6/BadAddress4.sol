// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20QuestRewards.sol";
import "./console.sol";

contract BadAddress4 {

    uint96 rewardId;
    uint96 userId;
    uint256 amountToClaim;
    bytes signature;

    function storeParams(uint96 _rewardId, uint96 _userId, uint256 _amountToClaim, bytes memory _signature) public {
        rewardId = _rewardId;
        userId = _userId;
        amountToClaim = _amountToClaim;
        signature = _signature;
    }
    
    receive() external payable {
        console.log("BadAddress4: msg.sender: %s", msg.sender);
        try  ERC20QuestRewards(payable(msg.sender)).claim(rewardId, userId, amountToClaim, signature) {
            
        } catch Error(string memory reason) {
            // catch failing revert() and require()
            console.log("BadAddress4: Error: %s", reason);
        } catch (bytes memory reason) {
            // catch failing assert()
            console.logBytes(reason);
        }
    }

    function attack(address payable _target) public payable {
        ERC20QuestRewards(_target).claim(rewardId, userId, amountToClaim, signature);
    }

}
