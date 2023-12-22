// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "./Ownable.sol";
import "./Stealcam.sol";

contract StealcamPeek is Ownable {

    event Peek(address peeker, uint256 id, address creator, address owner);

    uint256 public peekPrice;
    Stealcam public stealcam;

    constructor(
        uint256 _peekPrice,
        address _stealcam
    ) {
        peekPrice = _peekPrice;
        stealcam = Stealcam(_stealcam);
    }

    function peek(uint256 id) public payable {
        require(msg.value >= peekPrice, 'Insufficient payment');

        address owner = stealcam.ownerOf(id);
        address creator = stealcam.creator(id);
        uint256 amount = msg.value * 45 / 100;

        emit Peek(msg.sender, id, creator, owner);

        payable(owner).transfer(amount);
        payable(creator).transfer(amount);
    }

    function setPeekPrice(uint256 _peekPrice) public onlyOwner {
        peekPrice = _peekPrice;
    }

    function withdraw() public onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
}
