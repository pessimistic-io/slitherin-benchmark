// SPDX-License-Identifier: MIT-License
pragma solidity ^0.8.4;

import "./ReentrancyGuard.sol";
import "./ERC20.sol";
import "./Ownable.sol";

/// @custom:security-contact @francisthefirst on telegram
contract LysTreasuryChestTimelock is ReentrancyGuard, Ownable {

    // the name of the chest
    string public chestName;
    // the address of the timelocked token
    address public timeLockedTokenAddress;
    // the start time of the timelock
    uint public startTime;
    // the locking period of the timelock. Here 2 years. 
    uint public lockingPeriod = 60*60*24*365*2; // 2 years

    /**
     * @dev Constructor sets up the starting time at the current block timestamp
     *  the chest name and the timelocked token address.
     * @param _name Use of the chest.
     * @param _timeLockedTokenAddress Address of the token to timelock.
     */
    constructor(string memory _name, address _timeLockedTokenAddress) {
        chestName = _name;
        startTime = block.timestamp;
        timeLockedTokenAddress = _timeLockedTokenAddress;
    }

    /**
     * @dev lets the owner of the contract transfer _amount(s) ERC20 tokens to the _recipient address
     * if _contract is the timelocked token address then the current block timestamp must be greater than
     * the start time + locking period
     * @param _contract Address of the ERC20 token contract.
     * @param _recipient Address of the recipient.
     * @param _amount Amount of tokens to transfer.
     */
    function transferERC20(address _contract, address _recipient, uint256 _amount) public nonReentrant onlyOwner {
        if (_contract == timeLockedTokenAddress){
            require(startTime + lockingPeriod < block.timestamp, "Locking period has not expired yet");
        }
        ERC20 _token = ERC20(_contract);
        _token.transfer(_recipient, _amount);
    }

    /**
     * @dev returns the name of the contract.
     */
    function getName() public view returns (string memory) {
        return chestName;
    }

    /**
     * @dev receive function
     * Note contract does not accepts ether.
     */
    receive() external payable {
        revert("Contract does not accepts ETH");
    }
}

