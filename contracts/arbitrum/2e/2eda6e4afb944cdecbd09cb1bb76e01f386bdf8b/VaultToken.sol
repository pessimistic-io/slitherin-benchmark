// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./SafeMath.sol";
import "./Initializable.sol";
import "./IERC20.sol";
import "./OwnableUpgradeable.sol";

contract VaultToken is Initializable, OwnableUpgradeable {
    IERC20 public token;
    address public farmer;

    function initialize(address _token, address _farmer) public initializer {
        __Ownable_init();
        token = IERC20(_token);
        farmer = _farmer;
    }

    function farm(address _to, uint256 _amount) external {
        require(msg.sender == farmer, "only farmer");
        token.transfer(_to, _amount);
    }
    function setFarmer(address _newFarmer) external onlyOwner {
        farmer = _newFarmer;
    }
    function getBlockNumber() public view returns(uint){
        return block.number;
    }

    function getBlockTime() public view returns(uint) {
        return block.timestamp;
    }
}

