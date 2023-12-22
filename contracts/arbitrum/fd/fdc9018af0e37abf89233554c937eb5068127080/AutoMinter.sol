pragma solidity 0.8.9;

import "./Ownable.sol";


interface MyToken{
    function cost() external view returns (uint256);
    function mint() external payable;
}

contract AutoMinter is Ownable {
    MyToken merkly;

    function setMerkly(address c) public onlyOwner {
        merkly = MyToken(c);
    }

    function mint(uint amount) external payable{
       require(amount <= 40, "Too many, bruv");
       uint cost = merkly.cost();
       require(msg.value >= cost*amount, "Not enough ether sent");
       
       for(uint i = 0; i < amount; i++){
            merkly.mint{value:cost}();
       }
    }

    function withdraw() public payable onlyOwner {
        (bool success, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        require(success);
    }
}

