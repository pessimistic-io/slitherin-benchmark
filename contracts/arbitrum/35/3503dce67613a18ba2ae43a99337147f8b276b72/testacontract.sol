pragma solidity ^0.8.0;


interface someInterface {
    function totalSupply() external view returns (uint256);
}

library testacontract {
    function gimmeSupply(someInterface a) public view returns (uint256) {
        return a.totalSupply();
    }
}