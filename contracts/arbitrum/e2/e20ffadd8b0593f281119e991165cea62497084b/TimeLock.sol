pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IERC20.sol";

contract TimeLock is Ownable {
    uint256 public endTimeLock;

    constructor() {
        endTimeLock = block.timestamp + 365 days;
    }

    function withdraw(address _to, uint256 _amount) external onlyOwner {
        require(block.timestamp > endTimeLock, "Locking period");
        payable(_to).transfer(_amount);
    }
    
    function withdrawToken(address _token, address _to, uint256 _amount) external onlyOwner {
        require(block.timestamp > endTimeLock, "Locking period");
        IERC20(_token).transfer(_to, _amount);
    }
}
