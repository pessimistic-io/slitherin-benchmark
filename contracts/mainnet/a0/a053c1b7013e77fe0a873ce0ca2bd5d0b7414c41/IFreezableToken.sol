pragma solidity ^0.4.23;

interface IFreezableToken {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Freeze(address indexed owner, address indexed user, bool status);

    function totalSupply() external view returns (uint256);
    function balanceOf(address who) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function increaseApproval(address spender, uint256 addedValue) external returns (bool);
    function decreaseApproval(address spender, uint256 subtractedValue) external returns (bool);
    function freeze(address user) external returns (bool);
    function unfreeze(address user) external returns (bool);
    function freezing(address user) external view returns (bool);
}

