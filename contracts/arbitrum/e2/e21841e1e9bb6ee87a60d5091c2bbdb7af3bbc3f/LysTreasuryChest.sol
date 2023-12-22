// SPDX-License-Identifier: MIT-License
pragma solidity ^0.8.3;

import "./ReentrancyGuard.sol";
import "./ERC20.sol";
import "./Ownable.sol";


contract LysTreasuryChest is ReentrancyGuard, Ownable {

    // To what the funds are reserved for
    string public chestName;

    constructor(string memory _name) {
        chestName = _name;
    }

    function getName() public view returns (string memory) {
        return chestName;
    }

    function transferERC20(address _contract, address _recipient, uint256 _amount) public nonReentrant onlyOwner {
        ERC20 _token = ERC20(_contract);
        _token.transfer(_recipient, _amount);
    }

    /**
     * @dev receive function 
     * Note contract does not accepts ether
     */
    receive() external payable {
        revert("Contract does not accepts ETH");
    }
}

