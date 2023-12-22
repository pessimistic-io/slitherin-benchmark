// SPDX-License-Identifier: MIT
pragma solidity =0.8.15;

import "./XVIP.sol";

contract XvipAirdrop is Ownable {
    XVIP public immutable token;
    uint256 public totalPoints;
    mapping(address => uint256) public points;
    mapping(address => bool) public claimed;

    event Claimed(address addr, uint256 amount);

    constructor(XVIP _token) {
        token = _token;
    }

    function setPoints(address[] calldata addresses, uint256[] calldata _points) external  onlyOwner{
        require(addresses.length == _points.length, "Length not equal");
        for (uint256 i = 0; i < addresses.length; i++) {
            totalPoints += _points[i];
            points[addresses[i]] = _points[i];
        }
    }

    function claim() external {
        require(points[msg.sender] > 0, "No points");
        require(!claimed[msg.sender], "Already claimed");
        uint256 amount = token.balanceOf(address(this)) * points[msg.sender] / totalPoints;
        claimed[msg.sender] = true;
        require(token.transfer(msg.sender, amount), "Transfer failed");
        emit Claimed(msg.sender, amount);
    }

    //Expired and unclaimed , will be burned.
    function burn() external onlyOwner{
        token.burn(token.balanceOf(address(this)));
    }
}

