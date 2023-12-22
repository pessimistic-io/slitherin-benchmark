//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "./console.sol";

contract Greeter1 {
    string private greeting;
    mapping(uint256 => uint256) public myMap;

    event GreetingSet(string greeting);

    function initialize(string memory _greeting) public {
        console.log("Deploying a Greeter with greeting: ", _greeting);
        greeting = _greeting;
    }

    function greet() public view returns (string memory) {
        return greeting;
    }

    function setGreeting(string memory _greeting) public {
        console.log("Changing greeting from '%s' to '%s'", greeting, _greeting);
        greeting = _greeting;
        emit GreetingSet(_greeting);
    }

    function addMapping(uint256 key, uint256 value) public {
        myMap[key] = value;
    }
}

